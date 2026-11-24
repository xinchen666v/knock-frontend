import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:knock/platform/app_env.dart';
import 'package:knock/session/session.dart';

void main() {
  test('连接被拒绝时给出可操作提示，而不是裸异常', () async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();

    final dir = await Directory.systemTemp.createTemp('knock-conn-');
    final session = Session(
      env: AppEnv(
        identityPath: '${dir.path}/identity.json',
        server: '127.0.0.1:$port',
      ),
    );
    addTearDown(() async {
      session.dispose();
      await dir.delete(recursive: true);
    });

    expect(await session.createSession(), isFalse);
    expect(session.errorMessage, contains('ws://127.0.0.1:$port/ws'));
    expect(session.errorMessage, contains('拒绝连接'));
  });
}