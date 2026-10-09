import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'pages/welcome_page.dart';
import 'session/session.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const KnockApp());
}

class KnockApp extends StatelessWidget {
  const KnockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => Session(),
      child: MaterialApp(
        title: 'knock',
        debugShowCheckedModeBanner: false,
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        home: const WelcomePage(),
      ),
    );
  }
}