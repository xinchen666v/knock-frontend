import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../crypto/knock_crypto.dart';
import 'protocol.dart';

class InviteException implements Exception {
  final String message;

  const InviteException(this.message);

  @override
  String toString() => message;
}

/// 邀请链接 v2：
/// knock://<host>:<port>/v2/<qid>?k=<b64url(BoxPub)>&c=<checksum>
class Invite {
  final String host;
  final int port;
  final String queueId;
  final Uint8List boxPub;

  const Invite({
    required this.host,
    required this.port,
    required this.queueId,
    required this.boxPub,
  });

  String get fingerprint => KnockCrypto.fingerprint(boxPub);

  String toLink() {
    final normalizedPort = port == 0 ? 443 : port;
    final key = base64Url.encode(boxPub).replaceAll('=', '');
    final checksum = _checksum(host, normalizedPort, queueId, key);
    final hostPart = host.contains(':') ? '[$host]' : host;
    return 'knock://$hostPart:$normalizedPort/v2/$queueId?k=$key&c=$checksum';
  }

  String toWsUrl() {
    final hostPart = host.contains(':') ? '[$host]' : host;
    if (port == 0 || port == 443) return 'wss://$hostPart/ws';
    return 'ws://$hostPart:$port/ws';
  }

  static Invite? tryParse(String link) {
    try {
      return parse(link);
    } on InviteException {
      return null;
    }
  }

  static Invite parse(String link) {
    final trimmed = link.trim();
    Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (_) {
      throw const InviteException('邀请链接格式不正确');
    }
    if (uri.scheme != 'knock') {
      throw const InviteException('不是 knock 邀请链接');
    }
    final host = _stripBrackets(uri.host);
    if (host.isEmpty) {
      throw const InviteException('邀请链接缺少服务器地址');
    }

    final segments = uri.pathSegments;
    if (segments.length == 1 && validQueueId(segments.first)) {
      throw const InviteException(
        '旧版邀请链接（不含密钥），请对方更新 knock 后重新生成',
      );
    }
    if (segments.length != 2 || segments[0] != 'v2') {
      throw const InviteException('邀请链接版本不支持，需要 v2 链接');
    }
    final qid = segments[1];
    if (!validQueueId(qid)) {
      throw const InviteException('邀请链接里的队列 ID 不合法');
    }

    final port = uri.port;
    if (port < 1 || port > 65535) {
      throw const InviteException('v2 链接必须携带合法端口');
    }

    final keyRaw = uri.queryParameters['k'];
    if (keyRaw == null || keyRaw.isEmpty) {
      throw const InviteException('邀请链接缺少公钥参数 k');
    }
    final Uint8List boxPub;
    try {
      boxPub = _decodeBase64Url(keyRaw);
    } catch (_) {
      throw const InviteException('邀请链接的公钥不是合法 base64url');
    }
    if (boxPub.length != 32) {
      throw const InviteException('邀请链接的公钥长度必须是 32 字节');
    }

    final checksum = uri.queryParameters['c'];
    if (checksum == null || checksum.isEmpty) {
      throw const InviteException('邀请链接缺少校验和参数 c');
    }
    if (checksum != _checksum(host, port, qid, keyRaw)) {
      throw const InviteException('校验和不符——链接可能抄错或被截断');
    }

    return Invite(host: host, port: port, queueId: qid, boxPub: boxPub);
  }

  static String _checksum(String host, int port, String qid, String key) {
    final canonical = 'knock|$host|$port|$qid|$key';
    final digest = sha256.convert(utf8.encode(canonical)).bytes;
    return digest
        .sublist(0, 4)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static Uint8List _decodeBase64Url(String value) {
    final padded = value.padRight((value.length + 3) ~/ 4 * 4, '=');
    return base64Url.decode(padded);
  }

  static String _stripBrackets(String host) {
    if (host.startsWith('[') && host.endsWith(']')) {
      return host.substring(1, host.length - 1);
    }
    return host;
  }

  @override
  String toString() => toLink();
}
