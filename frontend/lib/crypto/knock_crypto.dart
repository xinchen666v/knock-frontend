import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

/// knock v2 密码学原语。
///
/// 与 Go 端 crypto 包逐字节兼容：所有 base64 都是标准带填充，
/// key 派生顺序是先 SS 后 ES，AAD 由调用方传入。
class KnockCrypto {
  static final X25519 _x25519 = X25519();
  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final Xchacha20 _aead = Xchacha20.poly1305Aead();
  static final Ed25519 _ed25519 = Ed25519();

  static const int keyLength = 32;
  static const int nonceLength = 24;
  static const int macLength = 16;

  static final Random _random = Random.secure();

  static Uint8List randomBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }

  static Future<Uint8List> publicKeyFromPrivate(Uint8List privateKey) async {
    final keyPair = await _x25519.newKeyPairFromSeed(privateKey);
    final publicKey = await keyPair.extractPublicKey();
    return Uint8List.fromList(publicKey.bytes);
  }

  static Future<Uint8List> sharedSecret(
    Uint8List myPrivateKey,
    Uint8List peerPublicKey,
  ) async {
    final keyPair = await _x25519.newKeyPairFromSeed(myPrivateKey);
    final secret = await _x25519.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: SimplePublicKey(peerPublicKey, type: KeyPairType.x25519),
    );
    return Uint8List.fromList(await secret.extractBytes());
  }

  /// 发送方前向保密派生：SS ‖ ECDH(ephPriv, peerStaticPub)。
  static Future<Uint8List> deriveSendKey({
    required Uint8List myStaticPrivateKey,
    required Uint8List peerStaticPublicKey,
    required Uint8List ephemeralPrivateKey,
    required bool iamA,
  }) async {
    final ss = await sharedSecret(myStaticPrivateKey, peerStaticPublicKey);
    final es = await sharedSecret(ephemeralPrivateKey, peerStaticPublicKey);
    return _hkdfKey(ss, es, 'knock-m3-v2:${iamA ? 'a2b' : 'b2a'}');
  }

  /// 接收方派生：SS ‖ ECDH(myStaticPriv, peerEphPub)。
  static Future<Uint8List> deriveRecvKey({
    required Uint8List myStaticPrivateKey,
    required Uint8List peerStaticPublicKey,
    required Uint8List peerEphemeralPublicKey,
    required bool iamA,
  }) async {
    final ss = await sharedSecret(myStaticPrivateKey, peerStaticPublicKey);
    final es = await sharedSecret(myStaticPrivateKey, peerEphemeralPublicKey);
    return _hkdfKey(ss, es, 'knock-m3-v2:${iamA ? 'a2b' : 'b2a'}');
  }

  /// v1 静态-静态派生，仅用于跑通历史测试向量。
  static Future<Uint8List> deriveStaticKey({
    required Uint8List myStaticPrivateKey,
    required Uint8List peerStaticPublicKey,
    required bool iamA,
  }) async {
    final ss = await sharedSecret(myStaticPrivateKey, peerStaticPublicKey);
    return _hkdfKey(ss, Uint8List(0), 'knock-m3-v1:${iamA ? 'a2b' : 'b2a'}');
  }

  static Future<Uint8List> _hkdfKey(
    Uint8List ss,
    Uint8List es,
    String info,
  ) async {
    // 顺序是协议契约：先 SS 后 ES，反了两端算出的 key 不同。
    final ikm = Uint8List(ss.length + es.length)
      ..setRange(0, ss.length, ss)
      ..setRange(ss.length, ss.length + es.length, es);
    final data = await _hkdf.deriveKey(
      secretKey: SecretKey(ikm),
      nonce: const [],
      info: utf8.encode(info),
    );
    return Uint8List.fromList(data.bytes);
  }

  /// 返回 ciphertext ‖ tag（16 字节），与 Go 的 Seal 输出一致。
  static Future<Uint8List> encrypt({
    required Uint8List key,
    required Uint8List plaintext,
    required Uint8List aad,
    Uint8List? nonce,
  }) async {
    final actualNonce = nonce ?? randomBytes(nonceLength);
    final box = await _aead.encrypt(
      plaintext,
      secretKey: SecretKey(key),
      nonce: actualNonce,
      aad: aad,
    );
    final mac = box.mac.bytes;
    final out = Uint8List(box.cipherText.length + mac.length)
      ..setRange(0, box.cipherText.length, box.cipherText)
      ..setRange(
          box.cipherText.length, box.cipherText.length + mac.length, mac);
    return out;
  }

  static Future<Uint8List> decrypt({
    required Uint8List key,
    required Uint8List ciphertextAndTag,
    required Uint8List nonce,
    required Uint8List aad,
  }) async {
    if (ciphertextAndTag.length < macLength) {
      throw const FormatException('密文长度不足');
    }
    final split = ciphertextAndTag.length - macLength;
    final box = SecretBox(
      ciphertextAndTag.sublist(0, split),
      nonce: nonce,
      mac: Mac(ciphertextAndTag.sublist(split)),
    );
    final plaintext = await _aead.decrypt(
      box,
      secretKey: SecretKey(key),
      aad: aad,
    );
    return Uint8List.fromList(plaintext);
  }

  /// 16 位大写 hex，无空格。协议里 from 字段用的就是这个形态。
  static String fingerprint(Uint8List publicKey) {
    final digest = crypto.sha256.convert(publicKey).bytes;
    return digest
        .sublist(0, 8)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
  }

  /// 两两分组，带空格：DC 10 62 58 FC 31 03 FC。
  static String formatFingerprint(String fingerprint) {
    final buffer = StringBuffer();
    for (var i = 0; i < fingerprint.length; i += 2) {
      if (i > 0) buffer.write(' ');
      buffer.write(fingerprint.substring(i, min(i + 2, fingerprint.length)));
    }
    return buffer.toString();
  }

  /// 四字符分组，给 UI 用：DC10 6258 FC31 03FC。
  static String groupFingerprint(String fingerprint) {
    final buffer = StringBuffer();
    for (var i = 0; i < fingerprint.length; i += 4) {
      if (i > 0) buffer.write(' ');
      buffer.write(fingerprint.substring(i, min(i + 4, fingerprint.length)));
    }
    return buffer.toString();
  }

  /// SAS 短认证串，形如 482-913。
  static String sasCode(Uint8List publicA, Uint8List publicB) {
    final low = _compareBytes(publicA, publicB) <= 0 ? publicA : publicB;
    final high = identical(low, publicA) ? publicB : publicA;
    final digest = crypto.sha256
        .convert(<int>[...utf8.encode('knock-sas-v1'), ...low, ...high]).bytes;
    final value =
        ((digest[0] << 24) | (digest[1] << 16) | (digest[2] << 8) | digest[3]) %
            1000000;
    return '${(value ~/ 1000).toString().padLeft(3, '0')}-'
        '${(value % 1000).toString().padLeft(3, '0')}';
  }

  static int _compareBytes(List<int> a, List<int> b) {
    final length = min(a.length, b.length);
    for (var i = 0; i < length; i++) {
      if (a[i] != b[i]) return a[i] - b[i];
    }
    return a.length - b.length;
  }

  /// 仅用于验证历史测试向量；客户端协议不依赖 Ed25519。
  static Future<Uint8List> signWithEd25519(
    Uint8List privateKey64,
    Uint8List message,
  ) async {
    final seed = privateKey64.sublist(0, 32);
    final keyPair = await _ed25519.newKeyPairFromSeed(seed);
    final signature = await _ed25519.sign(message, keyPair: keyPair);
    return Uint8List.fromList(signature.bytes);
  }
}
