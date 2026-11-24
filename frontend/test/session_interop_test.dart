import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:knock/platform/app_env.dart';
import 'package:knock/session/session.dart';

/// 真实服务端互通测试。
///
/// 默认跳过；先构建 Go 服务端，再用环境变量启动：
///   go build -o frontend/.tmp/knock-server.exe ./server
///   KNOCK_SERVER_BIN=<绝对路径> flutter test test/session_interop_test.dart
void main() {
  final serverBin = Platform.environment['KNOCK_SERVER_BIN'];
  final skipReason = serverBin == null
      ? '设置 KNOCK_SERVER_BIN 指向 Go 服务端二进制后运行'
      : null;

  test(
    '双向消息、已读、输入中、SAS 与离线补投',
    () async {
      final root = await Directory.systemTemp.createTemp('knock-interop-');
      final sessions = <Session>[];
      Process? server;

      Session make(String name) {
        final session = Session(
          env: AppEnv(
            identityPath: '${root.path}/$name/identity.json',
            server: _serverAddr!,
          ),
        );
        sessions.add(session);
        return session;
      }

      Future<void> retire(Session session) async {
        sessions.remove(session);
        await session.close();
        session.dispose();
      }

      try {
        await Directory('${root.path}/serverdb/database')
            .create(recursive: true);
        final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final port = probe.port;
        await probe.close();
        _serverAddr = '127.0.0.1:$port';

        server = await Process.start(
          serverBin!,
          ['-addr', _serverAddr!],
          workingDirectory: '${root.path}/serverdb',
        );
        unawaited(server.stdout.drain<void>());
        unawaited(server.stderr.drain<void>());
        await _waitForPort(port);

        // 1. A 建房；关闭后重启，链接必须保持不变
        final a1 = make('A');
        expect(await a1.createSession(), isTrue, reason: a1.errorMessage);
        final linkA = a1.myInviteLink;
        expect(linkA, contains('/v2/'));
        await retire(a1);

        final a = make('A');
        expect(await a.createSession(), isTrue, reason: a.errorMessage);
        expect(a.myInviteLink, linkA, reason: '同一身份必须复用同一个门');

        // 2. B 订阅 A，A 再订阅 B，形成双向通道
        final b = make('B');
        expect(await b.subscribeToPeer(a.myInviteLink), isTrue,
            reason: b.errorMessage);
        expect(b.myQid, isNotNull);
        final qidB = b.myQid;

        expect(await a.subscribeToPeer(b.myInviteLink), isTrue,
            reason: a.errorMessage);
        a.setChatVisible(true);
        b.setChatVisible(true);

        // 3. 两端算出的指纹与 SAS 必须一致
        expect(a.sasCode, isNotNull);
        expect(a.sasCode, b.sasCode);
        expect(a.peerFingerprint, b.myFingerprint);
        expect(a.myFingerprint, b.peerFingerprint);
        expect(a.myFingerprint, isNot(b.myFingerprint));

        // 4. A → B，送达与已读
        await a.sendMessage('hello from A');
        await _waitFor(() => b.messages.any((m) => m.text == 'hello from A'));
        final incoming = b.messages.firstWhere((m) => m.text == 'hello from A');
        expect(incoming.isMine, isFalse);
        await _waitFor(() => _statusOf(a, 'hello from A') == MessageStatus.read);

        // 5. B → A，同样要能读到
        await b.sendMessage('reply from B');
        await _waitFor(() => a.messages.any((m) => m.text == 'reply from B'));
        await _waitFor(() => _statusOf(b, 'reply from B') == MessageStatus.read);

        // 6. 输入中信号
        b.notifyTyping();
        await _waitFor(() => a.peerTyping);
        b.stopTyping();
        await _waitFor(() => !a.peerTyping);

        // 7. B 离线；A 发一条，服务器落库；B 重启并复用 qid 后补投
        await retire(b);
        await a.sendMessage('while B was offline');
        await _waitFor(
          () => _statusOf(a, 'while B was offline') == MessageStatus.sent,
          reason: '离线消息应被服务器接收并 ACK',
        );

        final b2 = make('B');
        expect(await b2.subscribeToPeer(a.myInviteLink), isTrue,
            reason: b2.errorMessage);
        expect(b2.myQid, qidB, reason: '同一身份必须复用同一个门');
        b2.setChatVisible(true);

        // 重启后历史恢复，已读状态也保留
        expect(
          b2.messages.any((m) => m.text == 'hello from A'),
          isTrue,
          reason: '重启后应能读到之前收到的消息',
        );
        final ownHistory =
            b2.messages.firstWhere((m) => m.text == 'reply from B');
        expect(ownHistory.isMine, isTrue);
        expect(ownHistory.status, MessageStatus.read);

        final contacts = await b2.loadContacts();
        final aContact = contacts.firstWhere(
          (c) => c.fingerprint == a.myFingerprint,
          orElse: () => throw StateError('重启后应自动恢复联系人'),
        );
        expect(aContact.alias, isNull);
        expect(aContact.lastMessage?.text, 'reply from B');
        expect(aContact.lastMessage?.isMine, isTrue);
        expect(aContact.verified, isFalse);

        await _waitFor(
          () => b2.messages.any((m) => m.text == 'while B was offline'),
          timeout: const Duration(seconds: 15),
        );

        // 8. 补投之后密钥仍可用
        await b2.sendMessage('back online');
        await _waitFor(() => a.messages.any((m) => m.text == 'back online'));
      } finally {
        for (final session in sessions) {
          await session.close();
          session.dispose();
        }
        server?.kill();
        await server?.exitCode.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            server?.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: skipReason,
  );
}

String? _serverAddr;

MessageStatus _statusOf(Session session, String text) => session.messages
    .firstWhere((m) => m.isMine && m.text == text)
    .status;

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
  throw TimeoutException(reason ?? '等待条件超时');
}

Future<void> _waitForPort(int port) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(deadline)) {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 300),
      );
      socket.destroy();
      return;
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
  }
  throw TimeoutException('服务端未在 127.0.0.1:$port 启动');
}