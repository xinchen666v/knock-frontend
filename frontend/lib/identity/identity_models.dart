import 'dart:typed_data';

import '../crypto/knock_crypto.dart';

class IdentityStoreException implements Exception {
  final String message;

  const IdentityStoreException(this.message);

  @override
  String toString() => message;
}

class Identity {
  final Uint8List boxPriv;
  final Uint8List boxPub;
  final String fingerprint;

  const Identity({
    required this.boxPriv,
    required this.boxPub,
    required this.fingerprint,
  });
}

/// 可持久化的会话状态。普通模式落在 SharedPreferences，
/// 调试模式落在身份文件旁边，两个实例互不干扰。
///
/// outboxes 按服务器保存自己的队列 ID：换服务器不应该让旧链接失效，
/// 回到原服务器时仍能复用同一个门。
class SessionState {
  String? host;
  int? port;
  String? myQid;
  String? lastPeerLink;
  String? server;
  final Map<String, String> outboxes;
  final Set<String> verifiedFingerprints;

  SessionState({
    this.host,
    this.port,
    this.myQid,
    this.lastPeerLink,
    this.server,
    Map<String, String>? outboxes,
    Set<String>? verifiedFingerprints,
  })  : outboxes = outboxes ?? <String, String>{},
        verifiedFingerprints = verifiedFingerprints ?? <String>{} {
    if (this.outboxes.isEmpty && host != null && myQid != null) {
      this.outboxes[serverKey(host!, port ?? 0)] = myQid!;
    }
  }

  factory SessionState.fromJson(Map<String, dynamic> json) => SessionState(
        host: json['host'] as String?,
        port: (json['port'] as num?)?.toInt(),
        myQid: json['my_qid'] as String?,
        lastPeerLink: json['last_peer_link'] as String?,
        server: json['server'] as String?,
        outboxes: ((json['outboxes'] as Map?) ?? const {})
            .map((key, value) => MapEntry(key.toString(), value.toString())),
        verifiedFingerprints: ((json['verified_fps'] as List?) ?? const [])
            .cast<String>()
            .toSet(),
      );

  Map<String, dynamic> toJson() => {
        if (host != null) 'host': host,
        if (port != null) 'port': port,
        if (myQid != null) 'my_qid': myQid,
        if (lastPeerLink != null) 'last_peer_link': lastPeerLink,
        if (server != null) 'server': server,
        'outboxes': outboxes,
        'verified_fps': verifiedFingerprints.toList()..sort(),
      };

  String? outboxFor(String host, int port) => outboxes[serverKey(host, port)];

  void setOutbox(String host, int port, String? qid) {
    if (qid == null || qid.isEmpty) {
      outboxes.remove(serverKey(host, port));
    } else {
      outboxes[serverKey(host, port)] = qid;
    }
  }

  static String serverKey(String host, int port) =>
      '$host:${port == 0 ? 443 : port}';
}

abstract class IdentityStore {
  Future<Identity> loadOrCreateIdentity();

  Future<SessionState> loadState();

  Future<void> saveState(SessionState state);
}

Future<Identity> identityFromPrivateKey(Uint8List privateKey) async {
  final publicKey = await KnockCrypto.publicKeyFromPrivate(privateKey);
  return Identity(
    boxPriv: privateKey,
    boxPub: publicKey,
    fingerprint: KnockCrypto.fingerprint(publicKey),
  );
}
