import '../platform/app_env.dart';
import 'history_store_base.dart';
import 'history_store_stub.dart'
    if (dart.library.io) 'history_store_sqlite.dart';

export 'history_store_base.dart';

HistoryStore createHistoryStore(AppEnv env) => createPlatformHistoryStore(env);