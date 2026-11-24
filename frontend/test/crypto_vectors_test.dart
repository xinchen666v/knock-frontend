import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knock/crypto/knock_crypto.dart';

Uint8List _b64(String value) => base64.decode(value);

void main() {
  final vectors = jsonDecode(
    File('test/fixtures/vectors.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final cases = (vectors['vectors'] as List).cast<Map<String, dynamic>>();

  test('9 条跨语言向量全部通过', () async {
    expect(cases.length, 9);

    for (final vector in cases) {
      final name = vector['name'] as String;
      final op = vector['op'] as String;
      final input = vector['input'] as Map<String, dynamic>;
      final output = vector['output'] as Map<String, dynamic>;

      switch (op) {
        case 'derive_send_fs':
          final key = await KnockCrypto.deriveSendKey(
            myStaticPrivateKey: _b64(input['my_box_priv'] as String),
            peerStaticPublicKey: _b64(input['peer_box_pub'] as String),
            ephemeralPrivateKey: _b64(input['eph_priv'] as String),
            iamA: input['direction'] == 'a2b',
          );
          expect(base64.encode(key), output['key'], reason: name);

        case 'derive_recv_fs':
          final key = await KnockCrypto.deriveRecvKey(
            myStaticPrivateKey: _b64(input['my_box_priv'] as String),
            peerStaticPublicKey: _b64(input['peer_box_pub'] as String),
            peerEphemeralPublicKey: _b64(input['peer_eph_pub'] as String),
            iamA: input['direction'] == 'a2b',
          );
          expect(base64.encode(key), output['key'], reason: name);

        case 'derive':
          final key = await KnockCrypto.deriveStaticKey(
            myStaticPrivateKey: _b64(input['my_box_priv'] as String),
            peerStaticPublicKey: _b64(input['peer_box_pub'] as String),
            iamA: input['direction'] == 'a2b',
          );
          expect(base64.encode(key), output['key'], reason: name);

        case 'encrypt':
          final ciphertext = await KnockCrypto.encrypt(
            key: _b64(input['key'] as String),
            plaintext: _b64(input['plaintext'] as String),
            aad: _b64(input['aad'] as String),
            nonce: _b64(input['nonce'] as String),
          );
          expect(base64.encode(ciphertext), output['ciphertext'], reason: name);

        case 'sas':
          final code = KnockCrypto.sasCode(
            _b64(input['box_pub_a'] as String),
            _b64(input['box_pub_b'] as String),
          );
          expect(code, output['code'], reason: name);

        case 'fingerprint':
          final fp = KnockCrypto.fingerprint(_b64(input['box_pub'] as String));
          expect(
            KnockCrypto.formatFingerprint(fp),
            output['fp'],
            reason: name,
          );

        case 'sign':
          final signature = await KnockCrypto.signWithEd25519(
            _b64(input['sign_priv'] as String),
            _b64(input['message'] as String),
          );
          expect(base64.encode(signature), output['signature'], reason: name);

        default:
          fail('未知向量类型：$op（$name）');
      }
    }
  });
}
