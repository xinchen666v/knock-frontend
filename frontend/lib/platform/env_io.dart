import 'dart:io';

import 'app_env.dart';

/// 同机 A/B 调试：两个进程各自指定 KNOCK_IDENTITY，
/// 身份与 qid 状态都落在该文件旁，互不覆盖。
AppEnv loadAppEnv() {
  final values = Platform.environment;

  String? read(String key) {
    final value = values[key]?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  final identityPath = read('KNOCK_IDENTITY');
  var profile = read('KNOCK_PROFILE');
  if (profile == null && identityPath != null) {
    final parts = File(identityPath)
        .parent
        .path
        .split(Platform.pathSeparator)
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isNotEmpty) profile = parts.last;
  }

  return AppEnv(
    identityPath: identityPath,
    server: read('KNOCK_SERVER'),
    profile: profile,
  );
}
