import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knock/protocol/invite.dart';

void main() {
  const qid = 'b7f3e2a1c9d84f02a6b3c8d7e5f10293';
  final zeroKey = Uint8List(32);
  final realKey = base64.decode('Pry2khSTRNxU5YFgz5C+2e6h3RToHI6R3lV699ev2RU=');

  test('v2 链接往返，校验和与 Go 端一致', () {
    final invite = Invite(
      host: '192.168.1.5',
      port: 8080,
      queueId: qid,
      boxPub: zeroKey,
    );
    final link = invite.toLink();
    expect(
      link,
      'knock://192.168.1.5:8080/v2/$qid'
      '?k=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&c=b19d1cfa',
    );

    final parsed = Invite.parse(link);
    expect(parsed.host, '192.168.1.5');
    expect(parsed.port, 8080);
    expect(parsed.queueId, qid);
    expect(parsed.boxPub, zeroKey);
  });

  test('真实公钥的 base64url 与校验和', () {
    final invite = Invite(
      host: '47.254.238.173',
      port: 7801,
      queueId: qid,
      boxPub: realKey,
    );
    final link = invite.toLink();
    expect(
        link.contains('k=Pry2khSTRNxU5YFgz5C-2e6h3RToHI6R3lV699ev2RU'), isTrue);
    expect(link.endsWith('c=04f37cce'), isTrue);
    expect(Invite.parse(link).fingerprint, isNotEmpty);
  });

  test('隧道模式端口 0 归一化为 443 并走 wss', () {
    final invite = Invite(
      host: 'abc.trycloudflare.com',
      port: 0,
      queueId: qid,
      boxPub: zeroKey,
    );
    expect(invite.toLink().contains(':0/'), isFalse);
    expect(invite.toLink().contains(':443/'), isTrue);
    expect(invite.toWsUrl(), 'wss://abc.trycloudflare.com/ws');
    expect(Invite.parse(invite.toLink()).port, 443);
  });

  test('旧版链接被明确拒绝', () {
    expect(
      () => Invite.parse('knock://example.com/$qid'),
      throwsA(
        isA<InviteException>().having(
          (e) => e.message,
          'message',
          contains('旧版邀请链接'),
        ),
      ),
    );
  });

  test('缺端口、缺 k、校验和错误都被拒绝', () {
    expect(
      () => Invite.parse(
          'knock://example.com/v2/$qid?k=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&c=b19d1cfa'),
      throwsA(isA<InviteException>()),
    );
    expect(
      () => Invite.parse('knock://example.com:8080/v2/$qid?c=b19d1cfa'),
      throwsA(isA<InviteException>()),
    );
    expect(
      () => Invite.parse(
          'knock://example.com:8080/v2/$qid?k=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&c=deadbeef'),
      throwsA(isA<InviteException>()),
    );
  });
}
