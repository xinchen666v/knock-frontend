import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'pages/welcome_page.dart';
import 'platform/app_env.dart';
import 'platform/env_loader.dart';
import 'platform/route_observer.dart';
import 'session/session.dart';
import 'theme/app_theme.dart';

void main() {
  final env = loadAppEnv();
  runApp(KnockApp(env: env));
}

class KnockApp extends StatelessWidget {
  final AppEnv env;

  const KnockApp({super.key, required this.env});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => Session(env: env),
      child: MaterialApp(
        title: 'knock',
        debugShowCheckedModeBanner: false,
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        navigatorObservers: [appRouteObserver],
        home: const WelcomePage(),
      ),
    );
  }
}
