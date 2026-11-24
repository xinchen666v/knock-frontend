import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:knock/platform/app_env.dart';
import 'package:knock/session/session.dart';

/// Go CLI ↔ Flutter 客户端的跨语言互通测试。
///
/// 需要两个环境变量：KNOCK_SERVER_BIN（服务端二进制）与
/// KNOCK_CLI_BIN（knock chat 客户端二进制）。在 Go 仓库根目录：
///   go build -o <frontend>/.tmp/knock-server.exe ./server
///   go build -o <frontend>/.tmp/knock-cli.exe ./client
void main() {
  final serverBin = Platform.environment['KNOCK_SERVER_BIN'];
  final cliBin = Platform.environment['KNOCK_CLI_BIN'];
  final skipReason = (serverBin == null || cliBin == null)
      ? '设置 KNOCK_SERVER_BIN 与 KNOCK_CLI_BIN 后运行'
      : null;

  test(
    'Go CLI 与 Flutter 双向收发、SAS、输入中、已读信号',
    () async {
      final root = await Directory.systemTemp.createTemp('knock-cli-');
      final sessions = <Session>[];
      Process? server;
      Process? goCli;
      final goLines = <String>[];
      final goOutput = StringBuffer();

      Future<void> waitGoLine(String needle,
          {Duration timeout = const Duration(seconds: 15)}) async {
        final deadline = DateTime.now().add(timeout);
        while (DateTime.now().isBefore(deadline)) {
          if (goLines.any((line) => line.contains(needle))) return;
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
        throw TimeoutException('Go CLI 输出中未出现「$needle」\n$goOutput');
      }

      try {
        await Directory('${root.path}/serverdb/database')
            .create(recursive: true);
        final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final port = probe.port;
        await probe.close();
        final addr = '127.0.0.1:$port';

        server = await Process.start(
          serverBin!,
          ['-addr', addr],
          workingDirectory: '${root.path}/serverdb',
        );
        unawaited(server.stdout.drain<void>());
        unawaited(server.stderr.drain<void>());
        await _waitForPort(port);

        // Dart 先建房，把链接交给 Go CLI 作为订阅目标
        final session = Session(
          env: AppEnv(
            identityPath: '${root.path}/dart/identity.json',
            server: addr,
          ),
        );
        sessions.add(session);
        expect(await session.createSession(), isTrue,
            reason: session.errorMessage);
        final dartLink = session.myInviteLink;
        expect(dartLink, contains('/v2/'));

        goCli = await Process.start(
          cliBin!,
          ['chat', '-server', addr, dartLink],
          environment: {
            ...Platform.environment,
            'KNOCK_IDENTITY': '${root.path}/go/identity.json',
          },
        );
        goCli.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          goLines.add(line);
          goOutput.writeln(line);
        });
        goCli.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) => goOutput.writeln('[stderr] $line'));

        // Go 打印自己的邀请链接；Dart 订阅它
        await waitGoLine('knock://');
        final goLink = RegExp(r'knock://\S+')
            .firstMatch(goOutput.toString())!
            .group(0)!;
        expect(await session.subscribeToPeer(goLink), isTrue,
            reason: session.errorMessage);
        session.setChatVisible(true);
        await waitGoLine('已连接');
        await waitGoLine('短码');

        // 两端独立算出的 SAS 必须一致（Go 已把它打印出来）
        expect(session.sasCode, isNotNull);
        expect(goOutput.toString(), contains(session.sasCode!));

        // Go → Flutter
        goCli.stdin.writeln('hello from go');
        await goCli.stdin.flush();
        await _waitFor(
          () => session.messages.any((m) => m.text == 'hello from go'),
          reason: 'Flutter 未收到 Go 的消息；Dart 消息='
              '${session.messages.map((m) => '${m.isMine ? "me" : "peer"}:${m.isSystem ? "sys:" : ""}${m.text}').toList()}\n'
              'Go 输出=\n$goOutput',
        );

        // Flutter → Go
        await session.sendMessage('hello from dart');
        await waitGoLine('hello from dart');

        // Flutter 已读信号 → Go 终端提示
        await waitGoLine('对方正在阅读中');

        // Flutter 输入中 → Go 终端提示
        session.notifyTyping();
        await waitGoLine('对方正在输入');

        // Go 的 read 信号 → Flutter 把自己的消息标为已读
        goCli.stdin.writeln('/signal read');
        await goCli.stdin.flush();
        await _waitFor(
          () => session.messages
              .firstWhere((m) => m.text == 'hello from dart')
              .status ==
              MessageStatus.read,
          reason: 'Flutter 未把 /signal read 理解为已读；'
              '消息状态=${session.messages.where((m) => m.isMine).map((m) => '${m.text}:${m.status}').toList()}',
        );
      } finally {
        try {
          goCli?.stdin.writeln('/quit');
          await goCli?.stdin.flush();
        } catch (_) {}
        await goCli?.exitCode.timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            goCli?.kill();
            return -1;
          },
        );
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