import 'identity_models.dart';

IdentityStore createFileIdentityStore(String path) =>
    throw const IdentityStoreException('当前平台不支持文件身份存储');
