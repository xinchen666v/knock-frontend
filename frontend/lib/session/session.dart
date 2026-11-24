import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../contacts/contact.dart';
import '../crypto/knock_crypto.dart';
import '../history/history_store.dart';
import '../identity/identity_models.dart';
import '../identity/identity_store.dart';
import '../platform/app_env.dart';
import '../protocol/invite.dart';
import '../protocol/protocol.dart';
import 'chat_message.dart';

export 'chat_message.dart';

enum SessionPhase {
  idle,
  connecting,
  waitingForPeer,
  chatting,
  reconnecting,
  closed,
  failed,
}

enum PeerStatus { unknown, waiting, online, offline }

class _Outgoing {
  final String mid;
  final Envelope envelope;
  Timer? timer;
  int attempts = 0;

  _Outgoing(this.mid, this.envelope);
}

class Session extends ChangeNotifier {
  static const int _seenLimit = 4096;
  static const Duration _requestTimeout = Duration(seconds: 5);
  static const Duration _connectTimeout = Duration(seconds: 10);
  static const Duration _ackTimeout = Duration(seconds: 8);
  static const Duration _signalMinInterval = Duration(seconds: 1);
  static const String defaultServerAddress = '47.254.238.173:7801';

  final AppEnv env;
  late final IdentityStore _store;
  late final HistoryStore _history;
  bool _historyReady = false;
  Future<void>? _historyOpening;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  Timer? _typingStopTimer;
  Timer? _typingClearTimer;

  Completer<Envelope>? _pendingRequest;
  String? _pendingExpected;

  Identity? _identity;
  SessionState _state = SessionState();
  bool _stateLoaded = false;

  Uint8List? _peerBoxPub;
  String? _myFP;
  String? _peerFP;
  String? _peerAlias;
  String? _sas;
  bool _iamA = false;
  bool _keysReady = false;
  bool _peerVerified = false;

  bool _peerTyping = false;
  String? _peerActivity;
  bool _chatVisible = false;

  bool _intentionalClose = false;
  int _generation = 0;
  int _reconnectAttempt = 0;
  bool _disposed = false;

  DateTime? _lastTypingSent;
  DateTime? _lastReadSent;

  final LinkedHashSet<String> _seenMids = LinkedHashSet<String>();
  final Map<String, _Outgoing> _outgoing = <String, _Outgoing>{};
  final List<Envelope> _pendingDelivers = <Envelope>[];

  Session({required this.env}) {
    _store = createIdentityStore(env);
    _history = createHistoryStore(env);
  }

  // === 对外状态 ===
  SessionPhase phase = SessionPhase.idle;
  PeerStatus peerStatus = PeerStatus.unknown;
  String? errorMessage;

  String? myQid;
  String? peerQid;

  String advHost = 'localhost';
  int advPort = 0;

  final List<ChatMessage> messages = <ChatMessage>[];

  String? get myFingerprint => _myFP;
  String? get peerFingerprint => _peerFP;
  String get peerDisplayName {
    final fingerprint = _peerFP;
    if (fingerprint == null) return '加密对话';
    return contactDisplayName(fingerprint, _peerAlias);
  }
  String? get sasCode => _sas;
  bool get peerVerified => _peerVerified;
  bool get peerTyping => _peerTyping;
  String? get peerActivity => _peerActivity;
  bool get isDebug => env.isDebug;

  /// 创建新门时会使用的服务器。
  /// 调试环境变量 > 界面设置 > 上次成功使用的服务器 > 内置云端地址。
  String get effectiveServer {
    final envServer = env.server?.trim();
    if (envServer != null && envServer.isNotEmpty) return envServer;
    final override = _state.server?.trim();
    if (override != null && override.isNotEmpty) return override;
    final host = _state.host;
    final port = _state.port;
    if (host != null && host.isNotEmpty && port != null) {
      return port == 0 ? host : '$host:$port';
    }
    return defaultServerAddress;
  }

  static String? validateServerAddress(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '请输入服务器地址';
    if (RegExp(r'\s').hasMatch(value)) return '地址不能包含空格';
    final lower = value.toLowerCase();
    if (lower.startsWith('ws://') ||
        lower.startsWith('wss://') ||
        lower.startsWith('http://') ||
        lower.startsWith('https://')) {
      return '只填 host:port，不要带协议前缀';
    }
    final index = value.lastIndexOf(':');
    if (index <= 0) {
      if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(value)) {
        return 'IP 地址请带上端口，例如 $value:7801';
      }
      return null;
    }
    final host = value.substring(0, index);
    final port = int.tryParse(value.substring(index + 1));
    if (host.isEmpty || port == null || port < 1 || port > 65535) {
      return '端口应在 1–65535 之间';
    }
    return null;
  }

  Future<bool> setServer(String raw) async {
    if (validateServerAddress(raw) != null) return false;
    await _ensureStateLoaded();
    _state.server = raw.trim();
    await _store.saveState(_state);
    _notify();
    return true;
  }

  String get myInviteLink {
    final identity = _identity;
    final qid = myQid;
    if (identity == null || qid == null || qid.isEmpty) return '';
    return Invite(
      host: advHost,
      port: advPort,
      queueId: qid,
      boxPub: identity.boxPub,
    ).toLink();
  }

  // ====================================================================
  // 生命周期
  // ====================================================================

  Future<bool> createSession({String? server}) async {
    _intentionalClose = false;
    _setPhase(SessionPhase.connecting);
    try {
      await _ensureStateLoaded();
      final (host, port) = _resolveServer(server);
      advHost = host;
      advPort = port;
      _state.host = host;
      _state.port = port;
      await _store.saveState(_state);

      if (!await _ensureConnected(host, port)) return false;
      await _ensureIdentity(host, port);
      peerStatus = PeerStatus.waiting;
      _setPhase(SessionPhase.waitingForPeer);
      return true;
    } catch (e) {
      errorMessage = _humanError(e);
      _setPhase(SessionPhase.failed);
      return false;
    }
  }

  Future<bool> subscribeToPeer(String peerLink) async {
    _intentionalClose = false;
    try {
      final invite = Invite.parse(peerLink);
      await _ensureStateLoaded();
      if (myQid != null && invite.queueId == myQid) {
        errorMessage = '这个是你自己的邀请链接，请粘贴对方的';
        return false;
      }
      await _openHistory();

      final switchingPeer = peerQid != null && peerQid != invite.queueId;
      if (switchingPeer) {
        // 服务端按队列记录订阅者：复用同一条连接会让旧联系人的
        // 消息继续投过来，而客户端只有一套密钥。换人时直接断开。
        await _teardownSocket();
        _clearConversation();
        peerStatus = PeerStatus.unknown;
      }

      advHost = invite.host;
      advPort = invite.port;
      if (!await _ensureConnected(invite.host, invite.port)) return false;
      await _ensureIdentity(invite.host, invite.port);
      if (myQid == invite.queueId) {
        errorMessage = '这个是你自己的邀请链接，请粘贴对方的';
        return false;
      }

      _setPhase(SessionPhase.connecting);
      final resp = await _request(
        Envelope(type: kTypeSub, queueId: invite.queueId),
      );
      if (resp.type == kTypeError) {
        final err = ErrorPayload.fromMap(resp.payload);
        errorMessage = _errorText(err);
        _setPhase(SessionPhase.waitingForPeer);
        return false;
      }

      peerQid = invite.queueId;
      await _setupKeys(invite);
      await _loadHistory();

      final canonicalLink = invite.toLink();
      final peerFp = _peerFP;
      if (peerFp != null && _historyReady) {
        try {
          await _history.upsertContact(
            fingerprint: peerFp,
            inviteLink: canonicalLink,
            lastSeen: DateTime.now(),
          );
          _peerAlias = await _history.contactAlias(peerFp);
        } catch (e) {
          debugPrint('[knock] contact save failed: $e');
        }
      }

      _state.lastPeerLink = canonicalLink;
      _state.host = invite.host;
      _state.port = invite.port;
      await _store.saveState(_state);

      peerStatus = PeerStatus.waiting;
      _setPhase(SessionPhase.chatting);
      unawaited(_flushPendingDelivers());
      return true;
    } on InviteException catch (e) {
      errorMessage = e.message;
      _setPhase(
          myQid == null ? SessionPhase.idle : SessionPhase.waitingForPeer);
      return false;
    } catch (e) {
      errorMessage = _humanError(e);
      _setPhase(SessionPhase.failed);
      return false;
    }
  }

  Future<void> close() async {
    _intentionalClose = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _typingStopTimer?.cancel();
    _typingClearTimer?.cancel();
    await _teardownSocket();
    peerStatus = PeerStatus.offline;
    _peerTyping = false;
    _setPhase(SessionPhase.closed);
  }

  @override
  void dispose() {
    _disposed = true;
    _intentionalClose = true;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _typingStopTimer?.cancel();
    _typingClearTimer?.cancel();
    for (final outgoing in _outgoing.values) {
      outgoing.timer?.cancel();
    }
    _outgoing.clear();
    _sub?.cancel();
    _channel?.sink.close(ws_status.normalClosure);
    unawaited(_history.close());
    super.dispose();
  }

  // ====================================================================
  // 发送 / 已读 / 输入中
  // ====================================================================

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (myQid == null || _identity == null || !_keysReady) {
      errorMessage = '加密会话尚未就绪';
      _notify();
      return;
    }

    final mid = generateId();
    final now = DateTime.now();
    messages.add(ChatMessage(
      text: trimmed,
      isMine: true,
      time: now,
      mid: mid,
      status: MessageStatus.sending,
    ));
    _notify();

    try {
      final encrypted = await _seal(
        myQid!,
        mid,
        ChatBody(
          from: _myFP!,
          text: trimmed,
          ts: now.millisecondsSinceEpoch ~/ 1000,
        ).toMap(),
      );
      final envelope = Envelope(
        type: kTypeSend,
        queueId: myQid,
        msgId: mid,
        payload: encrypted.toMap(),
      );
      final outgoing = _Outgoing(mid, envelope);
      _outgoing[mid] = outgoing;
      _send(envelope);
      outgoing.timer = Timer(_ackTimeout, () => _retryOrFail(mid));
    } catch (e) {
      debugPrint('[knock] encrypt failed: $e');
      _updateStatus(mid, MessageStatus.failed);
    }
  }

  void retryMessage(String mid) {
    final outgoing = _outgoing[mid];
    if (outgoing == null) return;
    outgoing.attempts = 0;
    outgoing.timer?.cancel();
    _updateStatus(mid, MessageStatus.sending);
    _send(outgoing.envelope);
    outgoing.timer = Timer(_ackTimeout, () => _retryOrFail(mid));
  }

  void setChatVisible(bool visible) {
    _chatVisible = visible;
    if (visible) {
      notifyRead();
    } else {
      stopTyping();
    }
  }

  void notifyTyping() {
    if (!_chatVisible || !_keysReady) return;
    _typingStopTimer?.cancel();
    _typingStopTimer = Timer(const Duration(seconds: 2), () {
      _typingStopTimer = null;
      _sendSignal('typing', 'stop');
    });

    final now = DateTime.now();
    if (_lastTypingSent != null &&
        now.difference(_lastTypingSent!) < _signalMinInterval) {
      return;
    }
    _lastTypingSent = now;
    _sendSignal('typing', 'start');
  }

  void stopTyping() {
    _typingStopTimer?.cancel();
    _typingStopTimer = null;
    _sendSignal('typing', 'stop');
  }

  void notifyRead() {
    if (!_chatVisible || !_keysReady) return;
    final hasIncoming = messages.any((m) => !m.isMine && !m.isSystem);
    if (!hasIncoming) return;

    final now = DateTime.now();
    if (_lastReadSent != null &&
        now.difference(_lastReadSent!) < _signalMinInterval) {
      return;
    }
    _lastReadSent = now;
    _sendSignal('read', 'start');
  }

  Future<void> markPeerVerified() async {
    final fp = _peerFP;
    if (fp == null) return;
    _state.verifiedFingerprints.add(fp);
    _peerVerified = true;
    await _store.saveState(_state);
    _notify();
  }

  /// 只清当前联系人；对方的记录不受影响。
  Future<void> clearHistory() async {
    final peerFp = _peerFP;
    if (peerFp != null) {
      await _openHistory();
      if (_historyReady) {
        try {
          await _history.clearPeer(peerFp);
        } catch (e) {
          debugPrint('[knock] history clear failed: $e');
        }
      }
    }
    messages.clear();
    _notify();
  }

  Future<List<Contact>> loadContacts() async {
    await _ensureStateLoaded();
    await _openHistory();
    if (!_historyReady) return const [];
    try {
      var contacts = await _history.loadContacts(
        verifiedFingerprints: _state.verifiedFingerprints,
      );
      if (contacts.isEmpty) {
        // 兼容旧版本的“继续上次对话”：把唯一一条链接升级成联系人。
        final last = _state.lastPeerLink;
        final invite =
            (last == null || last.isEmpty) ? null : Invite.tryParse(last);
        if (invite != null) {
          await _history.upsertContact(
            fingerprint: KnockCrypto.fingerprint(invite.boxPub),
            inviteLink: invite.toLink(),
            lastSeen: DateTime.now(),
          );
          contacts = await _history.loadContacts(
            verifiedFingerprints: _state.verifiedFingerprints,
          );
        }
      }
      return contacts;
    } catch (e) {
      debugPrint('[knock] contacts load failed: $e');
      return const [];
    }
  }

  Future<void> renameContact(String fingerprint, String? alias) async {
    await _openHistory();
    if (!_historyReady) return;
    final normalized =
        (alias == null || alias.trim().isEmpty) ? null : alias.trim();
    try {
      await _history.renameContact(fingerprint, normalized);
    } catch (e) {
      debugPrint('[knock] contact rename failed: $e');
      return;
    }
    if (_peerFP == fingerprint) {
      _peerAlias = normalized;
      _notify();
    }
  }

  /// 删除联系人会一并删除本地聊天记录与“已核实”标记。
  Future<void> deleteContact(Contact contact) async {
    final fingerprint = contact.fingerprint;
    if (_peerFP == fingerprint) {
      await close();
      _clearConversation();
    }
    await _openHistory();
    if (_historyReady) {
      try {
        await _history.deleteContact(fingerprint);
      } catch (e) {
        debugPrint('[knock] contact delete failed: $e');
      }
    }
    _state.verifiedFingerprints.remove(fingerprint);
    final last = _state.lastPeerLink;
    final lastInvite =
        (last == null || last.isEmpty) ? null : Invite.tryParse(last);
    if (lastInvite != null &&
        KnockCrypto.fingerprint(lastInvite.boxPub) == fingerprint) {
      _state.lastPeerLink = null;
    }
    await _store.saveState(_state);
    _notify();
  }

  // ====================================================================
  // 身份 / 连接
  // ====================================================================

  Future<void> _ensureStateLoaded() async {
    if (_stateLoaded) return;
    _identity = await _store.loadOrCreateIdentity();
    _state = await _store.loadState();
    _myFP = _identity!.fingerprint;
    _stateLoaded = true;
    _notify();
  }

  (String, int) _resolveServer(String? server) {
    final raw = (server != null && server.trim().isNotEmpty)
        ? server.trim()
        : effectiveServer;
    return _parseAddr(raw);
  }

  (String, int) _parseAddr(String addr) {
    final index = addr.lastIndexOf(':');
    if (index <= 0) return (addr, 0);
    final host = addr.substring(0, index);
    final port = int.tryParse(addr.substring(index + 1));
    if (port == null || port < 1 || port > 65535) return (host, 0);
    return (host, port);
  }

  Future<bool> _ensureConnected(String host, int port) async {
    if (_channel != null && advHost == host && advPort == port) return true;
    if (_channel != null) {
      await _teardownSocket();
    }
    try {
      await _connect(host, port);
      return true;
    } catch (e) {
      errorMessage = _connectErrorText(host, port, e);
      _setPhase(SessionPhase.failed);
      return false;
    }
  }

  Future<void> _connect(String host, int port) async {
    final generation = ++_generation;
    final url = _wsUrl(host, port);
    debugPrint('[knock] dialing: $url');

    final channel = WebSocketChannel.connect(Uri.parse(url));
    try {
      await channel.ready.timeout(_connectTimeout);
    } catch (e) {
      // 连接失败时 sink.close() 可能永远不完成，不能 await。
      try {
        unawaited(channel.sink.close(ws_status.normalClosure));
      } catch (_) {}
      rethrow;
    }
    _channel = channel;
    _sub = channel.stream.listen(
      _onMessage,
      onError: (Object error) => _onSocketError(error, generation),
      onDone: () => _onSocketDone(generation),
      cancelOnError: false,
    );
    _startHeartbeat();
  }

  String _wsUrl(String host, int port) {
    final hostPart = host.contains(':') ? '[$host]' : host;
    return (port == 0 || port == 443)
        ? 'wss://$hostPart/ws'
        : 'ws://$hostPart:$port/ws';
  }

  /// 把底层异常翻译成能指导操作的提示。
  /// Dart 的 SocketException 在 Windows 上会把本地临时端口写进 port 字段，
  /// 直接展示会误导用户去排查一个无关的端口。
  String _connectErrorText(String host, int port, Object error) {
    final url = _wsUrl(host, port);
    final raw = error.toString();
    final lower = raw.toLowerCase();
    final String reason;
    if (lower.contains('errno = 1225') ||
        lower.contains('refused') ||
        raw.contains('拒绝')) {
      reason = '服务器拒绝连接：$url 上没有服务在监听，或端口没有放行。';
    } else if (lower.contains('errno = 10060') ||
        lower.contains('timed out') ||
        lower.contains('timeout') ||
        raw.contains('超时')) {
      reason = '连接超时：$url 被防火墙拦截或服务器不可达。';
    } else if (lower.contains('handshake') ||
        lower.contains('certificate') ||
        lower.contains('tls')) {
      reason = 'TLS 握手失败：$url 可能不是 wss 服务。';
    } else {
      reason = '无法连接 $url：$raw';
    }
    if (port == 0 && _isIpLiteral(host)) {
      return '$reason\n\n'
          '服务器地址没有写端口，已按 wss 的 443 端口连接。'
          '如果云端是 ws 模式，请把地址写成 $host:7801 这样的「IP:端口」。';
    }
    return reason;
  }

  bool _isIpLiteral(String host) =>
      RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host);

  Future<void> _teardownSocket() async {
    _generation++;
    _pingTimer?.cancel();
    _pingTimer = null;
    await _sub?.cancel();
    _sub = null;
    try {
      await _channel?.sink.close(ws_status.normalClosure);
    } catch (_) {}
    _channel = null;
  }

  void _startHeartbeat() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _send(Envelope(type: kTypePing));
    });
  }

  Future<void> _ensureIdentity(String host, int port) async {
    final saved = _state.outboxFor(host, port);
    if (saved != null && validQueueId(saved)) {
      myQid = saved;
      _state.host = host;
      _state.port = port;
      _state.myQid = saved;
      await _store.saveState(_state);
      return;
    }
    if (myQid != null &&
        validQueueId(myQid!) &&
        _state.host == host &&
        _state.port == port) {
      _state.setOutbox(host, port, myQid);
      await _store.saveState(_state);
      return;
    }

    final resp = await _request(Envelope(type: kTypeNew));
    if (resp.type == kTypeError) {
      final err = ErrorPayload.fromMap(resp.payload);
      throw Exception('服务器拒绝 NEW：${_errorText(err)}');
    }
    final qid = NewOkPayload.fromMap(resp.payload).queueId;
    if (!validQueueId(qid)) throw Exception('服务器返回的队列 ID 不合法');
    myQid = qid;
    _state.setOutbox(host, port, qid);
    _state.myQid = qid;
    _state.host = host;
    _state.port = port;
    await _store.saveState(_state);
  }

  Future<void> _setupKeys(Invite invite) async {
    final identity = _identity!;
    _myFP = identity.fingerprint;
    _peerFP = KnockCrypto.fingerprint(invite.boxPub);
    _iamA = _myFP!.compareTo(_peerFP!) < 0;
    _peerBoxPub = invite.boxPub;
    _sas = KnockCrypto.sasCode(identity.boxPub, invite.boxPub);
    _peerVerified = _state.verifiedFingerprints.contains(_peerFP);
    _keysReady = true;
    _notify();
  }

  // ====================================================================
  // 本地历史（明文 SQLite，最近 30 天）
  // ====================================================================

  Future<void> _openHistory() async {
    if (_historyReady) return;
    final opening = _historyOpening;
    if (opening != null) {
      await opening;
      return;
    }
    final future = _history.open().then((_) {
      _historyReady = true;
    }).catchError((Object e) {
      debugPrint('[knock] history unavailable: $e');
    }).whenComplete(() {
      _historyOpening = null;
    });
    _historyOpening = future;
    await future;
  }

  /// 订阅成功后把本地记录并进当前会话。
  /// 内存里的消息优先，避免刚收到的消息被旧状态覆盖。
  Future<void> _loadHistory() async {
    final peerFp = _peerFP;
    if (peerFp == null) return;
    await _openHistory();
    if (!_historyReady) return;
    try {
      final loaded = await _history.load(peerFp);
      if (loaded.isEmpty) return;
      final byKey = <String, ChatMessage>{};
      for (final message in loaded) {
        byKey[_historyKey(message)] = message;
      }
      for (final message in messages) {
        byKey[_historyKey(message)] = message;
      }
      final merged = byKey.values.toList()
        ..sort((a, b) => a.time.compareTo(b.time));
      messages
        ..clear()
        ..addAll(merged);
      _notify();
    } catch (e) {
      debugPrint('[knock] history load failed: $e');
    }
  }

  String _historyKey(ChatMessage message) {
    final mid = message.mid;
    if (mid != null && mid.isNotEmpty) return 'mid:$mid';
    return '${message.isMine ? 'me' : 'peer'}:'
        '${message.time.microsecondsSinceEpoch}:${message.text}';
  }

  Future<void> _saveHistory(ChatMessage message) async {
    final peerFp = _peerFP;
    final mid = message.mid;
    if (peerFp == null ||
        mid == null ||
        mid.isEmpty ||
        message.isSystem ||
        !_historyReady) {
      return;
    }
    try {
      if (message.status == MessageStatus.failed) {
        await _history.remove(peerFp, mid);
      } else if (message.status != MessageStatus.sending) {
        await _history.save(peerFp, message);
      }
    } catch (e) {
      debugPrint('[knock] history save failed: $e');
    }
  }

  void _persistMessages(Iterable<ChatMessage> list) {
    final peerFp = _peerFP;
    if (peerFp == null || !_historyReady) return;
    final rows = list
        .where((message) =>
            !message.isSystem &&
            message.mid != null &&
            message.mid!.isNotEmpty)
        .toList(growable: false);
    if (rows.isEmpty) return;
    unawaited(_saveHistoryRows(peerFp, rows));
  }

  Future<void> _saveHistoryRows(
    String peerFp,
    List<ChatMessage> rows,
  ) async {
    try {
      final failed = rows
          .where((message) => message.status == MessageStatus.failed)
          .toList(growable: false);
      final saved = rows
          .where((message) =>
              message.status == MessageStatus.sent ||
              message.status == MessageStatus.read)
          .toList(growable: false);
      for (final message in failed) {
        await _history.remove(peerFp, message.mid!);
      }
      await _history.saveAll(peerFp, saved);
    } catch (e) {
      debugPrint('[knock] history save failed: $e');
    }
  }

  // ====================================================================
  // 加密 / 解密
  // ====================================================================

  Uint8List _aad(String qid, String mid) =>
      Uint8List.fromList(utf8.encode('$qid|$mid'));

  Future<EncryptedMessage> _seal(
    String qid,
    String mid,
    Map<String, dynamic> body,
  ) async {
    final identity = _identity!;
    final peerPub = _peerBoxPub!;
    final plaintext = Uint8List.fromList(utf8.encode(jsonEncode(body)));

    final ephemeralPrivate = KnockCrypto.randomBytes(KnockCrypto.keyLength);
    final ephemeralPublic =
        await KnockCrypto.publicKeyFromPrivate(ephemeralPrivate);
    final key = await KnockCrypto.deriveSendKey(
      myStaticPrivateKey: identity.boxPriv,
      peerStaticPublicKey: peerPub,
      ephemeralPrivateKey: ephemeralPrivate,
      iamA: _iamA,
    );
    final nonce = KnockCrypto.randomBytes(KnockCrypto.nonceLength);
    final ciphertext = await KnockCrypto.encrypt(
      key: key,
      plaintext: plaintext,
      aad: _aad(qid, mid),
      nonce: nonce,
    );
    return EncryptedMessage(
      nonce: base64.encode(nonce),
      ciphertext: base64.encode(ciphertext),
      ephemeralPublicKey: base64.encode(ephemeralPublic),
    );
  }

  Future<Uint8List> _decryptRaw(
    String qid,
    String mid,
    Map<String, dynamic> payload,
  ) async {
    if (_peerBoxPub == null) {
      throw const DecryptException('会话密钥尚未建立');
    }
    final encrypted = EncryptedMessage.fromMap(payload);
    if (encrypted.ciphertext.isEmpty) {
      if (payload.containsKey('text')) {
        throw const DecryptException('收到未加密的明文载荷（对端版本过旧）');
      }
      throw const DecryptException('载荷缺少密文字段');
    }
    if (encrypted.version == 0) {
      throw const DecryptException('对端未标注加密载荷版本');
    }
    if (encrypted.version != kEncVersion) {
      throw DecryptException(
        '加密版本不兼容：收到 v${encrypted.version}，本端支持 v$kEncVersion',
      );
    }

    Uint8List nonce;
    Uint8List ciphertext;
    try {
      nonce = base64.decode(encrypted.nonce);
      ciphertext = base64.decode(encrypted.ciphertext);
    } catch (_) {
      throw const DecryptException('nonce/密文不是标准 base64');
    }
    if (nonce.length != KnockCrypto.nonceLength) {
      throw const DecryptException('nonce 长度不正确');
    }
    Uint8List ephemeralPublic;
    try {
      ephemeralPublic = base64.decode(encrypted.ephemeralPublicKey);
    } catch (_) {
      throw const DecryptException('临时公钥不是标准 base64');
    }
    if (ephemeralPublic.length != 32) {
      throw const DecryptException('临时公钥长度不正确');
    }

    final key = await KnockCrypto.deriveRecvKey(
      myStaticPrivateKey: _identity!.boxPriv,
      peerStaticPublicKey: _peerBoxPub!,
      peerEphemeralPublicKey: ephemeralPublic,
      // 接收方向 = 发送方的发送方向。
      iamA: !_iamA,
    );
    try {
      return await KnockCrypto.decrypt(
        key: key,
        ciphertextAndTag: ciphertext,
        nonce: nonce,
        aad: _aad(qid, mid),
      );
    } catch (_) {
      throw const DecryptException('认证失败（密钥不匹配或内容被篡改）');
    }
  }

  Future<ChatBody> _decryptChat(
    String qid,
    String mid,
    Map<String, dynamic> payload,
  ) async {
    final plaintext = await _decryptRaw(qid, mid, payload);
    ChatBody body;
    try {
      body = ChatBody.fromMap(
        jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>,
      );
    } catch (_) {
      throw const DecryptException('明文不是合法 ChatBody');
    }
    if (body.from != _peerFP) {
      throw const DecryptException('发送方身份不匹配');
    }
    return body;
  }

  Future<SignalMessage> _decryptSignal(
    String qid,
    String mid,
    Map<String, dynamic> payload,
  ) async {
    final plaintext = await _decryptRaw(qid, mid, payload);
    try {
      return SignalMessage.fromMap(
        jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>,
      );
    } catch (_) {
      throw const DecryptException('明文不是合法 SignalMessage');
    }
  }

  // ====================================================================
  // 接收
  // ====================================================================

  void _onMessage(dynamic data) {
    if (data is! String) return;
    Envelope envelope;
    try {
      envelope = Envelope.decode(data);
    } catch (e) {
      debugPrint('[knock] bad frame: $e');
      return;
    }

    if (_pendingRequest != null) {
      final expected = _pendingExpected;
      if (envelope.type == expected || envelope.type == kTypeError) {
        final completer = _pendingRequest!;
        _pendingRequest = null;
        _pendingExpected = null;
        completer.complete(envelope);
        return;
      }
    }

    switch (envelope.type) {
      case kTypePong:
        break;
      case kTypeDeliver:
        unawaited(_handleDeliver(envelope));
        break;
      case kTypeSignal:
        unawaited(_handleSignal(envelope));
        break;
      case kTypeAck:
        _handleAck(envelope);
        break;
      case kTypeError:
        _handleError(envelope);
        break;
    }
  }

  Future<void> _handleDeliver(Envelope envelope) async {
    final mid = envelope.msgId;
    if (mid == null || mid.isEmpty) return;
    final qid = envelope.queueId ?? peerQid;
    if (qid == null || qid.isEmpty) return;

    if (!_keysReady) {
      _pendingDelivers.add(envelope);
      return;
    }

    if (_seenMids.contains(mid)) {
      _ack(qid, mid);
      return;
    }
    _seenMids.add(mid);
    _trimSeen();

    try {
      final body = await _decryptChat(qid, mid, envelope.payload);
      _peerSeen();

      if (body.kind == 'file') {
        _ack(qid, mid);
        _addSystem('对方发来一个文件，当前版本暂不支持');
        return;
      }
      if (body.kind.isNotEmpty) {
        _ack(qid, mid);
        _addSystem('收到暂不支持的消息类型：${body.kind}');
        return;
      }

      final message = ChatMessage(
        text: body.text,
        isMine: false,
        time: _timeFromTs(body.ts),
        mid: mid,
        status: MessageStatus.sent,
      );
      final isNew = !messages.any((m) => m.mid == mid);
      if (isNew) {
        // 先落库再 ACK：ACK 之后服务器就不再有这条消息了。
        await _saveHistory(message);
      }
      _ack(qid, mid);

      if (isNew && !messages.any((m) => m.mid == mid)) {
        messages.add(message);
        if (phase != SessionPhase.chatting) {
          _setPhase(SessionPhase.chatting);
        }
        _notify();
        if (_chatVisible) notifyRead();
      }
    } on DecryptException catch (e) {
      // 解密失败也必须 ACK，否则服务器会无限重投坏密文。
      _ack(qid, mid);
      debugPrint('[knock] decrypt failed ($mid): ${e.message}');
      _addSystem('收到一条无法解密的消息：${e.message}');
    } catch (e) {
      _ack(qid, mid);
      debugPrint('[knock] deliver failed ($mid): $e');
    }
  }

  Future<void> _handleSignal(Envelope envelope) async {
    final mid = envelope.msgId ?? '';
    final qid = envelope.queueId ?? peerQid;
    if (qid == null || qid.isEmpty || mid.isEmpty) return;
    try {
      final signal = await _decryptSignal(qid, mid, envelope.payload);
      _peerSeen();
      switch (signal.kind) {
        case 'typing':
          _peerTyping = signal.state == 'start';
          _resetTypingClearTimer();
          _notify();
          break;
        case 'thinking':
          _peerActivity = signal.state == 'start' ? '对方正在处理…' : null;
          _notify();
          break;
        case 'read':
          if (signal.state == 'start') _markMineRead(signal.ts);
          break;
      }
    } catch (_) {
      // 信号是瞬时且不可靠的，解不开就静默忽略。
    }
  }

  void _handleAck(Envelope envelope) {
    final mid = envelope.msgId ?? AckPayload.fromMap(envelope.payload).mid;
    if (mid.isEmpty) return;
    final outgoing = _outgoing.remove(mid);
    outgoing?.timer?.cancel();
    _updateStatus(mid, MessageStatus.sent);
  }

  void _handleError(Envelope envelope) {
    final error = ErrorPayload.fromMap(envelope.payload);
    debugPrint('[knock] server error ${error.code}: ${error.message}');

    switch (error.code) {
      case kCodeQueueNotFound:
        if (envelope.queueId == myQid) {
          unawaited(_recoverStaleIdentity());
        } else {
          errorMessage = '对方队列不存在，链接可能已失效';
          _markLastMineFailed();
        }
        break;
      case kCodeForbidden:
        errorMessage = '身份校验失败：${error.message}';
        _markLastMineFailed();
        break;
      case kCodeTooManyRequests:
        errorMessage = '请求过于频繁，请稍后再试';
        break;
      case kCodeServerError:
        errorMessage = '服务器存储错误，请稍后重试';
        _markLastMineFailed();
        break;
      default:
        errorMessage = _errorText(error);
        _markLastMineFailed();
    }
    _notify();
  }

  Future<void> _recoverStaleIdentity() async {
    _state.setOutbox(advHost, advPort, null);
    _state.myQid = null;
    myQid = null;
    await _store.saveState(_state);
    _markLastMineFailed();
    try {
      await _ensureIdentity(advHost, advPort);
      errorMessage = '原队列已失效，已自动重建（旧链接作废，请重新分享）';
    } catch (e) {
      errorMessage = '身份恢复失败：${_humanError(e)}';
    }
    _notify();
  }

  Future<void> _flushPendingDelivers() async {
    if (_pendingDelivers.isEmpty) return;
    final pending = List<Envelope>.from(_pendingDelivers);
    _pendingDelivers.clear();
    for (final envelope in pending) {
      await _handleDeliver(envelope);
    }
  }

  // ====================================================================
  // 发送辅助
  // ====================================================================

  void _send(Envelope envelope) {
    final channel = _channel;
    if (channel == null) {
      debugPrint('[knock] send skipped, socket not open: ${envelope.type}');
      if (envelope.type == kTypeSend && envelope.msgId != null) {
        _updateStatus(envelope.msgId!, MessageStatus.failed);
      }
      return;
    }
    try {
      channel.sink.add(envelope.encode());
    } catch (e) {
      debugPrint('[knock] send failed: $e');
      if (envelope.type == kTypeSend && envelope.msgId != null) {
        _updateStatus(envelope.msgId!, MessageStatus.failed);
      }
    }
  }

  void _ack(String qid, String mid) {
    _send(Envelope(
      type: kTypeAck,
      queueId: qid,
      msgId: mid,
      payload: AckPayload(mid: mid).toMap(),
    ));
  }

  Future<void> _sendSignal(String kind, String state) async {
    if (!_keysReady || myQid == null) return;
    final mid = generateId();
    try {
      final encrypted = await _seal(
        myQid!,
        mid,
        SignalMessage(
          kind: kind,
          state: state,
          ts: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ).toMap(),
      );
      _send(Envelope(
        type: kTypeSignal,
        queueId: myQid,
        msgId: mid,
        payload: encrypted.toMap(),
      ));
    } catch (e) {
      debugPrint('[knock] signal failed: $e');
    }
  }

  Future<Envelope> _request(
    Envelope envelope, {
    Duration timeout = _requestTimeout,
  }) {
    final completer = Completer<Envelope>();
    _pendingRequest = completer;
    _pendingExpected = _expectedResponse(envelope.type);
    _send(envelope);
    return completer.future.timeout(timeout, onTimeout: () {
      _pendingRequest = null;
      _pendingExpected = null;
      throw Exception('等待 ${envelope.type} 响应超时');
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

  // ====================================================================
  // 消息状态
  // ====================================================================

  void _addSystem(String text) {
    messages.add(ChatMessage(
      text: text,
      isMine: false,
      time: DateTime.now(),
      isSystem: true,
    ));
    _notify();
  }

  DateTime _timeFromTs(int ts) {
    if (ts <= 0) return DateTime.now();
    final time = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final now = DateTime.now();
    if (time.year < 2000 || time.isAfter(now.add(const Duration(days: 1)))) {
      return now;
    }
    return time;
  }

  void _updateStatus(String mid, MessageStatus status) {
    final index = messages.indexWhere((m) => m.isMine && m.mid == mid);
    if (index < 0) return;
    final current = messages[index];
    if (current.status == status) return;
    if (status == MessageStatus.sent && current.status == MessageStatus.read) {
      return;
    }
    final updated = current.copyWith(status: status);
    messages[index] = updated;
    _persistMessages([updated]);
    _notify();
  }

  void _markLastMineFailed() {
    for (var i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (message.isMine &&
          (message.status == MessageStatus.sending ||
              message.status == MessageStatus.sent)) {
        final updated = message.copyWith(status: MessageStatus.failed);
        messages[i] = updated;
        _persistMessages([updated]);
        break;
      }
    }
  }

  void _markMineRead(int ts) {
    final now = DateTime.now();
    final cutoff =
        ts > 0 ? DateTime.fromMillisecondsSinceEpoch(ts * 1000) : now;
    // 对端时钟可能偏快；不能把"未来才发出"的消息提前标成已读。
    final effective = cutoff.isAfter(now) ? now : cutoff;
    final limit = effective.add(const Duration(seconds: 1));
    final changedMessages = <ChatMessage>[];
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      if (!message.isMine || message.isSystem) continue;
      if (message.status == MessageStatus.failed) continue;
      if (message.time.isAfter(limit)) continue;
      if (message.status != MessageStatus.read) {
        final updated = message.copyWith(status: MessageStatus.read);
        messages[i] = updated;
        changedMessages.add(updated);
      }
    }
    if (changedMessages.isNotEmpty) {
      _persistMessages(changedMessages);
      _notify();
    }
  }

  void _retryOrFail(String mid) {
    final outgoing = _outgoing[mid];
    if (outgoing == null) return;
    if (outgoing.attempts < 1) {
      outgoing.attempts++;
      _send(outgoing.envelope);
      outgoing.timer = Timer(_ackTimeout, () => _retryOrFail(mid));
    } else {
      outgoing.timer = null;
      _updateStatus(mid, MessageStatus.failed);
    }
  }

  void _trimSeen() {
    while (_seenMids.length > _seenLimit) {
      _seenMids.remove(_seenMids.first);
    }
  }

  void _peerSeen() {
    if (peerStatus != PeerStatus.online) {
      peerStatus = PeerStatus.online;
    }
    _notify();
  }

  void _resetTypingClearTimer() {
    _typingClearTimer?.cancel();
    if (!_peerTyping) return;
    _typingClearTimer = Timer(const Duration(seconds: 5), () {
      _peerTyping = false;
      _notify();
    });
  }

  // ====================================================================
  // 断线重连
  // ====================================================================

  void _onSocketError(Object error, int generation) {
    if (generation != _generation) return;
    debugPrint('[knock] socket error: $error');
    _pingTimer?.cancel();
    _channel = null;
    if (_intentionalClose) return;
    errorMessage = '连接异常：$error';
    peerStatus = PeerStatus.offline;
    _scheduleReconnect();
  }

  void _onSocketDone(int generation) {
    if (generation != _generation) return;
    debugPrint('[knock] socket closed');
    _pingTimer?.cancel();
    _channel = null;
    peerStatus = PeerStatus.offline;
    if (_intentionalClose) {
      _setPhase(SessionPhase.closed);
      return;
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_intentionalClose || _reconnectTimer != null || _disposed) return;
    if (advHost.isEmpty) return;
    final seconds = min(30, 1 << _reconnectAttempt.clamp(0, 5));
    _reconnectAttempt++;
    _setPhase(SessionPhase.reconnecting);
    _reconnectTimer = Timer(Duration(seconds: seconds), () async {
      _reconnectTimer = null;
      if (_intentionalClose || _disposed) return;
      try {
        final connected = await _ensureConnected(advHost, advPort);
        if (!connected) {
          throw Exception(errorMessage ?? '连接失败');
        }
        if (peerQid != null && _keysReady) {
          final resp = await _request(
            Envelope(type: kTypeSub, queueId: peerQid),
          );
          if (resp.type == kTypeError) {
            throw Exception(ErrorPayload.fromMap(resp.payload).message);
          }
          _setPhase(SessionPhase.chatting);
        } else {
          _setPhase(SessionPhase.waitingForPeer);
        }
        _reconnectAttempt = 0;
        errorMessage = null;
        unawaited(_flushPendingDelivers());
      } catch (e) {
        debugPrint('[knock] reconnect failed: $e');
        _scheduleReconnect();
      }
    });
  }

  // ====================================================================
  // 重置
  // ====================================================================

  Future<void> resetIdentity() async {
    _intentionalClose = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _teardownSocket();

    for (final outgoing in _outgoing.values) {
      outgoing.timer?.cancel();
    }
    _outgoing.clear();
    _pendingDelivers.clear();
    _seenMids.clear();
    messages.clear();

    peerQid = null;
    peerStatus = PeerStatus.unknown;
    _peerTyping = false;
    _peerActivity = null;
    _keysReady = false;
    _peerBoxPub = null;
    _peerFP = null;
    _peerAlias = null;
    _sas = null;
    _peerVerified = false;
    errorMessage = null;
    myQid = null;

    await _ensureStateLoaded();
    _state.myQid = null;
    _state.outboxes.clear();
    _state.lastPeerLink = null;
    await _store.saveState(_state);

    _setPhase(SessionPhase.idle);
  }

  void _clearConversation() {
    for (final outgoing in _outgoing.values) {
      outgoing.timer?.cancel();
    }
    _outgoing.clear();
    _pendingDelivers.clear();
    _seenMids.clear();
    messages.clear();
    peerQid = null;
    _keysReady = false;
    _peerBoxPub = null;
    _peerFP = null;
    _peerAlias = null;
    _sas = null;
    _peerVerified = false;
    _peerTyping = false;
    _peerActivity = null;
    _notify();
  }

  // ====================================================================
  // 工具
  // ====================================================================

  void _setPhase(SessionPhase value) {
    phase = value;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  String _errorText(ErrorPayload error) {
    switch (error.code) {
      case kCodeBadRequest:
        return '请求不合法：${error.message}';
      case kCodeForbidden:
        return '身份校验失败：${error.message}';
      case kCodeQueueNotFound:
        return '队列不存在：${error.message}';
      case kCodeTooManyRequests:
        return '请求过于频繁，请稍后再试';
      case kCodeServerError:
        return '服务器错误：${error.message}';
      default:
        return error.message.isEmpty ? '未知错误（${error.code}）' : error.message;
    }
  }

  String _humanError(Object error) {
    final text = error.toString();
    return text.startsWith('Exception: ')
        ? text.substring('Exception: '.length)
        : text;
  }
}

class DecryptException implements Exception {
  final String message;

  const DecryptException(this.message);

  @override
  String toString() => message;
}
