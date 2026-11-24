import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:knock/pages/chat_page.dart';
import 'package:knock/platform/app_env.dart';
import 'package:knock/session/session.dart';
import 'package:knock/theme/app_theme.dart';

void main() {
  Session seededSession() {
    final session = Session(
      env: const AppEnv(
        identityPath: 'C:/tmp/knock-preview/identity.json',
        server: '127.0.0.1:7801',
        profile: 'B',
      ),
    );
    final now = DateTime.now();
    session
      ..phase = SessionPhase.chatting
      ..peerStatus = PeerStatus.online
      ..messages.addAll([
        ChatMessage(
          text: 'test1',
          isMine: true,
          time: now.subtract(const Duration(minutes: 2)),
          mid: 'm1',
          status: MessageStatus.read,
        ),
        ChatMessage(
          text: 'test2',
          isMine: true,
          time: now.subtract(const Duration(minutes: 1)),
          mid: 'm2',
          status: MessageStatus.sent,
        ),
        ChatMessage(
          text: 'reply from peer',
          isMine: false,
          time: now,
        ),
      ]);
    return session;
  }

  Future<void> pumpChat(
    WidgetTester tester,
    Session session,
    Size size,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      ChangeNotifierProvider<Session>.value(
        value: session,
        child: MaterialApp(
          theme: buildDarkTheme(),
          home: const ChatPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('聊天页在宽窗口下正常渲染调试条与状态', (tester) async {
    final session = seededSession();
    addTearDown(session.dispose);
    await pumpChat(tester, session, const Size(1280, 720));

    expect(tester.takeException(), isNull);
    expect(find.text('加密对话'), findsOneWidget);
    expect(find.text('在线 · 端到端加密'), findsOneWidget);
    expect(find.text('调试 · B'), findsOneWidget);
    expect(find.text('reply from peer'), findsOneWidget);
    expect(find.byIcon(Icons.done_all), findsOneWidget);
  });

  testWidgets('窄窗口下聊天页与安全码弹窗不溢出', (tester) async {
    final session = seededSession();
    addTearDown(session.dispose);
    await pumpChat(tester, session, const Size(420, 720));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('核对安全码'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('核对安全码'), findsOneWidget);
    expect(find.text('稍后再说'), findsOneWidget);
    expect(find.text('数字一致，标记为可信'), findsOneWidget);
  });
}