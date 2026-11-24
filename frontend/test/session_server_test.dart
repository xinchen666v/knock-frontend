import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:knock/platform/app_env.dart';
import 'package:knock/session/session.dart';

void main() {
  test('默认是云服务器，设置后按身份持久化', () async {
    final dir = await Directory.systemTemp.createTemp('knock-server-');
    final env = AppEnv(identityPath: '${dir.path}/identity.json');
    final first = Session(env: env);
    final second = Session(env: env);
    addTearDown(() async {
      first.dispose();
      second.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    expect(first.effectiveServer, Session.defaultServerAddress);
    expect(await first.setServer('127.0.0.1:7801'), isTrue);
    expect(first.effectiveServer, '127.0.0.1:7801');

    await second.loadContacts();
    expect(second.effectiveServer, '127.0.0.1:7801');
  });

  test('服务器地址校验', () {
    expect(Session.validateServerAddress(''), isNotNull);
    expect(Session.validateServerAddress('ws://1.2.3.4:7801'), isNotNull);
    expect(Session.validateServerAddress('1.2.3.4'), isNotNull);
    expect(Session.validateServerAddress('1.2.3.4:7801'), isNull);
    expect(Session.validateServerAddress('example.com'), isNull);
    expect(Session.validateServerAddress('example.com:99999'), isNotNull);
    expect(Session.validateServerAddress('host:abc'), isNotNull);
  });

  test('调试环境变量优先于界面设置', () async {
    final dir = await Directory.systemTemp.createTemp('knock-server-');
    final env = AppEnv(
      identityPath: '${dir.path}/identity.json',
      server: '10.0.0.1:9000',
    );
    final session = Session(env: env);
    addTearDown(() async {
      session.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    expect(session.effectiveServer, '10.0.0.1:9000');
    expect(await session.setServer('127.0.0.1:7801'), isTrue);
    expect(session.effectiveServer, '10.0.0.1:9000');
  });
}