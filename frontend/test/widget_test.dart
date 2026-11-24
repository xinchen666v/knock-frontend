import 'package:flutter_test/flutter_test.dart';

import 'package:knock/main.dart';
import 'package:knock/platform/app_env.dart';

void main() {
  testWidgets('欢迎页展示应用名与入口', (WidgetTester tester) async {
    await tester.pumpWidget(const KnockApp(env: AppEnv()));
    await tester.pump();

    expect(find.text('knock'), findsOneWidget);
    expect(find.text('创建一扇门'), findsOneWidget);
    expect(find.text('我有邀请链接'), findsOneWidget);
  });
}
