import 'protocol.dart';

/// 邀请链接：对应 Go 端 protocol.Invite
/// 格式：knock://host[:port]/qid
/// port 为 0 表示隧道模式（wss），非 0 表示明文 ws
class Invite {
  final String host;
  final int port;
  final String queueId;

  const Invite({required this.host, required this.port, required this.queueId});

  String toInviteString() {
    if (port == 0) return 'knock://$host/$queueId';
    return 'knock://$host:$port/$queueId';
  }

  String toWsUrl() {
    if (port == 0) return 'wss://$host/ws';
    return 'ws://$host:$port/ws';
  }

  static Invite? tryParse(String link) {
    try {
      final uri = Uri.parse(link.trim());
      if (uri.scheme != 'knock') return null;
      if (uri.host.isEmpty) return null;

      var qid = uri.path;
      if (qid.startsWith('/')) qid = qid.substring(1);
      if (!validQueueId(qid)) return null;

      // Dart 的 Uri 对未知 scheme 未指定端口时返回 0
      final port = uri.port;
      return Invite(host: uri.host, port: port, queueId: qid);
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => toInviteString();
}