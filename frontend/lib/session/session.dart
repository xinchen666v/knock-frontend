import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:shared_preferences/shared_preferences.dart';

import '../protocol/invite.dart';
import '../protocol/protocol.dart';

/// 会话阶段：驱动 UI 页面切换
enum SessionPhase {
  idle, // 未开始
  connecting, // 正在连接服务器
  waitingForPeer, // 已创建队列，等待对方敲门
  chatting, // 双方已握手，可聊天
  closed, // 连接关闭
  failed, // 出错
}

/// 对端状态：只在 chatting 阶段有意义
enum PeerStatus {
  unknown,
  waiting, // 已订阅对方，但还没收到对方消息
  online, // 收到过对方消息
  offline, // 发消息时收到 503
}

/// 一条聊天消息（UI 渲染用）
class ChatMessage {
  final String text;
  final bool isMine;
  final DateTime time;
  final String? mid;
  final bool failed;
  const ChatMessage({
    required this.text,
    required this.isMine,
    required this.time,
    this.mid,
    this.failed = false,
  });

  ChatMessage copyWith({bool? failed}) => ChatMessage(
        text: text,
        isMine: isMine,
        time: time,
        mid: mid,
        failed: failed ?? this.failed,
      );
}

class Session extends ChangeNotifier {
  // === 连接层 ===
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pingTimer;

  // === 请求-响应配对（启动阶段串行使用）===
  Completer<Envelope>? _pendingRequest;
  String? _pendingExpected;

  // === 对外状态 ===
  SessionPhase phase = SessionPhase.idle;
  PeerStatus peerStatus = PeerStatus.unknown;
  String? errorMessage;

  String? myQid; // 我的队列（对方 SUB 后从这里收）
  String? peerQid; // 对方的队列（我 SUB 后从这里收）

  // 广播地址：从对方链接继承，用于生成我自己的邀请
  String advHost = 'localhost';
  int advPort = 8080;

  final List<ChatMessage> messages = [];
  final Set<String> _seenMids = {};

  // ====================================================================
  // 创建会话：NEW，得到自己的 qid，进入 waitingForPeer
  // ====================================================================
  // Future<bool> createSession({String server = 'localhost:8080'}) async {
  //   final (host, port) = _parseAddr(server);
  //   advHost = host;
  //   advPort = port;

  //   _setPhase(SessionPhase.connecting);
  //   try {
  //     await _connect(host, port);
  //     final resp = await _request(Envelope(type: kTypeNew));
  //     if (resp.type == kTypeError) {
  //       final err = ErrorPayload.fromMap(resp.payload);
  //       throw Exception('服务器拒绝 NEW：${err.message}');
  //     }
  //     myQid = NewOkPayload.fromMap(resp.payload).queueId;
  //     peerStatus = PeerStatus.waiting;
  //     _setPhase(SessionPhase.waitingForPeer);
  //     return true;
  //   } catch (e) {
  //     errorMessage = e.toString();
  //     _setPhase(SessionPhase.failed);
  //     return false;
  //   }
  // }

  // M2重构
  Future<bool> createSession({String? server}) async {
    final prefs = await SharedPreferences.getInstance();
    final savedHost = prefs.getString('adv_host');
    final savedPort = prefs.getInt('adv_port') ?? 0;

    String host;
    int port;
    if (server != null && server.isNotEmpty) {
      (host, port) = _parseAddr(server);
    } else if (savedHost != null && savedHost.isNotEmpty) {
      host = savedHost; // 沿用上次的广播地址——隧道用户重启后还是隧道
      port = savedPort;
    } else {
      (host, port) = _parseAddr('localhost:8080');
    }

    if (!await _ensureIdentity(host, port)) return false;
    if (!await _ensureConnected(host, port)) return false;

    peerStatus = PeerStatus.waiting;
    _setPhase(SessionPhase.waitingForPeer);
    return true;
  }

  // ====================================================================
  // 订阅对方队列：SUB，成功后进入 chatting
  // 调用时机：用户在邀请页粘贴对方的邀请链接
  // ====================================================================
  // Future<bool> subscribeToPeer(String peerLink) async {
  //   final invite = Invite.tryParse(peerLink);
  //   if (invite == null) {
  //     errorMessage = '邀请链接不合法';
  //     return false;
  //   }

  //   //新增：不能订阅自己的队列
  //   if (myQid != null && invite.queueId == myQid) {
  //     errorMessage = '这个是你自己的邀请链接，请粘贴对方的';
  //     return false;
  //   }

  //   // 如果还没连接（加入模式），先连接
  //   if (_channel == null) {
  //     advHost = invite.host;
  //     advPort = invite.port;
  //     _setPhase(SessionPhase.connecting);
  //     try {
  //       await _connect(invite.host, invite.port);
  //       final resp = await _request(Envelope(type: kTypeNew));
  //       if (resp.type == kTypeError) {
  //         final err = ErrorPayload.fromMap(resp.payload);
  //         throw Exception('创建队列失败：${err.message}');
  //       }
  //       myQid = NewOkPayload.fromMap(resp.payload).queueId;
  //     } catch (e) {
  //       errorMessage = e.toString();
  //       _setPhase(SessionPhase.failed);
  //       return false;
  //     }
  //   }

  //   // 发送 SUB
  //   try {
  //     final resp = await _request(Envelope(
  //       type: kTypeSub,
  //       queueId: invite.queueId,
  //     ));
  //     if (resp.type == kTypeError) {
  //       final err = ErrorPayload.fromMap(resp.payload);
  //       errorMessage = err.message;
  //       return false;
  //     }
  //     peerQid = invite.queueId;
  //     peerStatus = PeerStatus.waiting;
  //     _setPhase(SessionPhase.chatting);
  //     return true;
  //   } catch (e) {
  //     errorMessage = e.toString();
  //     return false;
  //   }
  // }

  Future<bool> subscribeToPeer(String peerLink) async {
    final invite = Invite.tryParse(peerLink);
    if (invite == null) {
      errorMessage = '邀请链接不合法';
      return false;
    }

    // 先装载身份，再比较——顺序错了检查就是摆设
    if (!await _ensureIdentity(invite.host, invite.port)) return false;
    if (myQid != null && invite.queueId == myQid) {
      errorMessage = '这个是你自己的邀请链接，请粘贴对方的';
      return false;
    }

    // 服务器由对方链接决定；身份属于这台服务器则复用，否则 NEW
    if (!await _ensureIdentity(invite.host, invite.port)) return false;
    if (!await _ensureConnected(invite.host, invite.port)) return false;

    try {
      final resp = await _request(Envelope(
        type: kTypeSub,
        queueId: invite.queueId,
      ));
      if (resp.type == kTypeError) {
        errorMessage = ErrorPayload.fromMap(resp.payload).message;
        return false;
      }
      peerQid = invite.queueId;
      peerStatus = PeerStatus.waiting;
      _setPhase(SessionPhase.chatting);

      // 记住最近的对话，欢迎页提供"继续上次对话"入口
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_peer_link', peerLink.trim());

      return true;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    }
  }

  // ====================================================================
  // 发送消息：只有 chatting 阶段可用，且需要 peerQid
  // ====================================================================
  void sendMessage(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (myQid == null) return; //check myQid

    final mid = generateId();
    messages.add(ChatMessage(
      text: trimmed,
      isMine: true,
      time: DateTime.now(),
      mid: mid,
    ));
    notifyListeners();

    _send(Envelope(
      type: kTypeSend,
      queueId: myQid,
      msgId: mid,
      payload: ChatPayload(text: trimmed).toMap(),
    ));
  }

  // ====================================================================
  // 生成我自己的邀请链接（给对端用）
  // ====================================================================
  String get myInviteLink {
    if (myQid == null) return '';
    return Invite(host: advHost, port: advPort, queueId: myQid!)
        .toInviteString();
  }

  // ====================================================================
  // 关闭会话
  // ====================================================================
  Future<void> close() async {
    // _pingTimer?.cancel();
    // _pingTimer = null;
    // await _sub?.cancel();
    // _sub = null;
    // try {
    //   await _channel?.sink.close(ws_status.normalClosure);
    // } catch (_) {}
    // _channel = null;
    await _teardownSocket();
    _setPhase(SessionPhase.closed);
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close(ws_status.normalClosure);
    super.dispose();
  }

  // ====================================================================
  // 内部实现
  // ====================================================================

  void _setPhase(SessionPhase p) {
    phase = p;
    notifyListeners();
  }

  (String, int) _parseAddr(String addr) {
    // "host:port" → (host, port)
    // "host"      → (host, 0)  ← 隧道模式
    final idx = addr.indexOf(':');
    if (idx < 0) return (addr, 0);
    final host = addr.substring(0, idx);
    final portStr = addr.substring(idx + 1);
    final port = int.tryParse(portStr);
    if (port == null || port < 1 || port > 65535) return (host, 0);
    return (host, port);
  }

  Future<void> _connect(String host, int port) async {
    final invite = Invite(host: host, port: port, queueId: '');
    final url = invite.toWsUrl();
    debugPrint('[knock] dialing: $url');

    _channel = WebSocketChannel.connect(Uri.parse(url));
    await _channel!.ready;

    _sub = _channel!.stream.listen(
      _onMessage,
      onError: _onSocketError,
      onDone: _onSocketDone,
      cancelOnError: false,
    );

    _startHeartbeat();
  }

  void _startHeartbeat() {
    _pingTimer?.cancel();
    // 服务器 pongWait=60s, pingPeriod=45s。客户端取更保守的 30s。
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _send(Envelope(type: kTypePing));
    });
  }

  void _send(Envelope env) {
    try {
      _channel?.sink.add(env.encode());
    } catch (e) {
      debugPrint('[knock] send failed: $e');
    }
  }

  Future<Envelope> _request(Envelope env,
      {Duration timeout = const Duration(seconds: 5)}) {
    final completer = Completer<Envelope>();
    _pendingRequest = completer;
    _pendingExpected = _expectedResponse(env.type);
    _send(env);

    return completer.future.timeout(timeout, onTimeout: () {
      _pendingRequest = null;
      _pendingExpected = null;
      throw Exception('等待 ${env.type} 响应超时');
    });
  }

  String? _expectedResponse(String requestType) {
    switch (requestType) {
      case kTypeNew:
        return kTypeNewOk;
      case kTypeSub:
        return kTypeSubOk;
      default:
        return null;
    }
  }

  void _onMessage(dynamic data) {
    if (data is! String) return;
    Envelope env;
    try {
      env = Envelope.decode(data);
    } catch (e) {
      debugPrint('[knock] bad frame: $e');
      return;
    }

    // 1) 唤醒等待中的请求
    if (_pendingRequest != null) {
      final expected = _pendingExpected;
      if (env.type == expected || env.type == kTypeError) {
        final c = _pendingRequest!;
        _pendingRequest = null;
        _pendingExpected = null;
        c.complete(env);
        return;
      }
    }

    // 2) 主动推送分发
    switch (env.type) {
      case kTypePong:
        // 心跳应答，什么也不做
        break;

      case kTypeDeliver:
        _handleDeliver(env);
        break;

      case kTypeError:
        _handleAsyncError(env);
        break;

      case kTypePing:
        // 服务端不会主动 PING 客户端，忽略
        break;
    }
  }

  void _handleDeliver(Envelope env) {
    if (env.msgId != null) {
      if (_seenMids.contains(env.msgId)) return;
      _seenMids.add(env.msgId!);
    }

    final chat = ChatPayload.fromMap(env.payload);
    messages.add(ChatMessage(
      text: chat.text,
      isMine: false,
      time: DateTime.now(),
      mid: env.msgId,
    ));

    if (peerStatus != PeerStatus.online) {
      peerStatus = PeerStatus.online;
    }
    // 收到 DELIVER 意味着对方已订阅我们，进入 chatting
    if (phase != SessionPhase.chatting) {
      phase = SessionPhase.chatting;
    }

    // 回 ACK（服务器目前只记录日志，但保持协议完整）
    if (env.msgId != null && peerQid != null) {
      _send(Envelope(
        type: kTypeAck,
        queueId: peerQid,
        msgId: env.msgId,
      ));
    }

    notifyListeners();
  }

  void _handleAsyncError(Envelope env) async {
    final err = ErrorPayload.fromMap(env.payload);
    debugPrint('[knock] server error ${err.code}: ${err.message}');

    if (err.code == kCodeNoSubscriber) {
      // 503：对方离线
      peerStatus = PeerStatus.offline;
      _markLastMineFailed();
      notifyListeners();
      return;
    }

    if (err.code == 403) {
      // 新增：协议使用错误
      _markLastMineFailed();
      errorMessage = '发送失败：${err.message}';
      notifyListeners();
    }

    if (err.code == kCodeQueueNotFound) {
      // 只有"自己的队列"404 才触发身份恢复；SUB 不存在的对方队列是另一回事
      if (env.queueId == myQid) {
        await _recoverStaleIdentity();
      } else {
        _markLastMineFailed();
        errorMessage = '对方队列不存在';
      }
      notifyListeners();
      return;
    }
  }

  /// 本机保存的 qid 在服务器上已不存在（换库/换服务器）→ 作废重建
  Future<void> _recoverStaleIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('my_qid');
    myQid = null;

    final ok = await _ensureIdentity(advHost, advPort);
    _markLastMineFailed();
    errorMessage = ok ? '原队列已失效，已自动重建身份（旧链接作废，请重新分享）' : '身份恢复失败：$errorMessage';
    notifyListeners();
  }

// 抽出辅助方法，标记最近一条自己发的消息为失败
  void _markLastMineFailed() {
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].isMine && !messages[i].failed) {
        messages[i] = messages[i].copyWith(failed: true);
        break;
      }
    }
  }

  void _onSocketError(Object err) {
    _pingTimer?.cancel();
    debugPrint('[knock] socket error: $err');
    errorMessage = err.toString();
    if (phase != SessionPhase.idle && phase != SessionPhase.closed) {
      _setPhase(SessionPhase.failed);
    }
  }

  void _onSocketDone() {
    _pingTimer?.cancel();
    debugPrint('[knock] socket closed');
    if (phase != SessionPhase.idle && phase != SessionPhase.closed) {
      _setPhase(SessionPhase.closed);
    }
  }

  // === 身份持久化：qid 绑定服务器，重启后复活 ===

  Future<void> _saveIdentity() async {
    if (myQid == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('my_qid', myQid!);
    await prefs.setString('adv_host', advHost);
    await prefs.setInt('adv_port', advPort);
  }

  Future<void> _teardownSocket() async {
    _pingTimer?.cancel();
    _pingTimer = null;
    await _sub?.cancel();
    _sub = null;
    try {
      await _channel?.sink.close(ws_status.normalClosure);
    } catch (_) {}
    _channel = null;
  }

  Future<bool> _ensureConnected(String host, int port) async {
    if (_channel != null && advHost == host && advPort == port) return true;
    if (_channel != null) await _teardownSocket(); // 换服务器，先断旧连接
    try {
      await _connect(host, port);
      return true;
    } catch (e) {
      errorMessage = '连接服务器失败：$e';
      _setPhase(SessionPhase.failed);
      return false;
    }
  }

  /// 身份决策核心：本机保存过【这台服务器铸造的】qid 就复用（零网络请求），
  /// 否则 NEW 新队列并保存。
  Future<bool> _ensureIdentity(String host, int port) async {
    // 内存里已有这台服务器的身份
    if (myQid != null && advHost == host && advPort == port) return true;

    final prefs = await SharedPreferences.getInstance();
    final savedQid = prefs.getString('my_qid');
    final savedHost = prefs.getString('adv_host');
    final savedPort = prefs.getInt('adv_port') ?? 0;

    if (savedQid != null &&
        validQueueId(savedQid) &&
        savedHost == host && // ★ 服务器匹配才复用
        savedPort == port) {
      myQid = savedQid;
      advHost = host;
      advPort = port;
      return true; // 惰性复活：队列在服务器 DB 里，SUB/SEND 时自然生效
    }

    // 没有（或不匹配）→ NEW，先连上
    if (!await _ensureConnected(host, port)) return false;
    try {
      final resp = await _request(Envelope(type: kTypeNew));
      if (resp.type == kTypeError) {
        final err = ErrorPayload.fromMap(resp.payload);
        throw Exception('服务器拒绝 NEW：${err.message}');
      }
      myQid = NewOkPayload.fromMap(resp.payload).queueId;
      advHost = host;
      advPort = port;
      await _saveIdentity();
      return true;
    } catch (e) {
      errorMessage = e.toString();
      _setPhase(SessionPhase.failed);
      return false;
    }
  }

/// 作废当前身份：断开连接、清除本地保存的 qid。
/// 保留服务器地址设置（adv_host/adv_port）。
/// 注意：服务器 DB 里的旧队列依然存在，会由 TTL 清理回收
/// （M2 服务器没有"删除队列"的协议动作，见已知限制）。
/// 调用后由 UI 导航回邀请流程，createSession 会自动铸造新身份。
Future<void> resetIdentity() async {
  // 1. 完整断开：可能在 chatting 中途触发
  await _teardownSocket();
  peerQid = null;
  peerStatus = PeerStatus.unknown;
  messages.clear();
  _seenMids.clear();
  errorMessage = null;

  // 2. 清身份：只删 qid，不动服务器配置
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('my_qid');
  await prefs.remove('last_peer_link');
  myQid = null;

  // 3. 回到初始态（_setPhase 内部会 notifyListeners）
  _setPhase(SessionPhase.idle);
}


}
