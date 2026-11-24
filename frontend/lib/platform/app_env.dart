class AppEnv {
  final String? identityPath;
  final String? server;
  final String? profile;

  const AppEnv({this.identityPath, this.server, this.profile});

  bool get isDebug => identityPath != null && identityPath!.isNotEmpty;

  String get debugLabel =>
      (profile == null || profile!.isEmpty) ? 'debug' : profile!;
}
