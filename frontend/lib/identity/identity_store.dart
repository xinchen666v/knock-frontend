import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../crypto/knock_crypto.dart';
import '../platform/app_env.dart';
import 'identity_models.dart';

import 'fs_store_stub.dart' if (dart.library.io) 'fs_store_io.dart';

IdentityStore createIdentityStore(AppEnv env) {
  final path = env.identityPath;
  if (path != null && path.isNotEmpty) return createFileIdentityStore(path);
  return PrefsIdentityStore();
}

class PrefsIdentityStore implements IdentityStore {
  static const _kIdentity = 'identity_box_priv';
  static const _kHost = 'adv_host';
  static const _kPort = 'adv_port';
  static const _kQid = 'my_qid';
  static const _kLastPeer = 'last_peer_link';
  static const _kServer = 'server';
  static const _kVerified = 'verified_fps';
  static const _kOutboxes = 'outboxes';

  @override
  Future<Identity> loadOrCreateIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_kIdentity);
    Uint8List privateKey;
    if (encoded != null && encoded.isNotEmpty) {
      try {
        privateKey = base64.decode(encoded);
      } catch (_) {
        throw const IdentityStoreException('本机身份密钥已损坏，无法解析');
      }
      if (privateKey.length != KnockCrypto.keyLength) {
        throw const IdentityStoreException('本机身份密钥长度不正确');
      }
    } else {
      privateKey = KnockCrypto.randomBytes(KnockCrypto.keyLength);
      await prefs.setString(_kIdentity, base64.encode(privateKey));
    }
    return identityFromPrivateKey(privateKey);
  }

  @override
  Future<SessionState> loadState() async {
    final prefs = await SharedPreferences.getInstance();
    return SessionState(
      host: prefs.getString(_kHost),
      port: prefs.getInt(_kPort),
      myQid: prefs.getString(_kQid),
      lastPeerLink: prefs.getString(_kLastPeer),
      server: prefs.getString(_kServer),
      outboxes: _readOutboxes(prefs.getString(_kOutboxes)),
      verifiedFingerprints:
          (prefs.getStringList(_kVerified) ?? const []).toSet(),
    );
  }

  @override
  Future<void> saveState(SessionState state) async {
    final prefs = await SharedPreferences.getInstance();
    await _writeString(prefs, _kHost, state.host);
    await _writeInt(prefs, _kPort, state.port);
    await _writeString(prefs, _kQid, state.myQid);
    await _writeString(prefs, _kLastPeer, state.lastPeerLink);
    await _writeString(prefs, _kServer, state.server);
    await _writeString(prefs, _kOutboxes, jsonEncode(state.outboxes));
    await prefs.setStringList(_kVerified, state.verifiedFingerprints.toList());
  }

  Map<String, String> _readOutboxes(String? raw) {
    if (raw == null || raw.isEmpty) return <String, String>{};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (key, value) => MapEntry(key, value.toString()),
      );
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> _writeString(
    SharedPreferences prefs,
    String key,
    String? value,
  ) async {
    if (value == null || value.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }

  Future<void> _writeInt(
    SharedPreferences prefs,
    String key,
    int? value,
  ) async {
    if (value == null) {
      await prefs.remove(key);
    } else {
      await prefs.setInt(key, value);
    }
  }
}
