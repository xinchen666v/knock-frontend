import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../crypto/knock_crypto.dart';
import 'identity_models.dart';

IdentityStore createFileIdentityStore(String path) => FileIdentityStore(path);

class FileIdentityStore implements IdentityStore {
  final String identityPath;
  String? _stateSuffix;

  FileIdentityStore(this.identityPath);

  File get _identityFile => File(identityPath);

  /// 与 Go CLI 的 state-<指纹前 8 位>.json 同样的隔离思路：
  /// 同一个目录里放多个 identity 也不会共用状态文件。
  File? get _stateFile {
    final suffix = _stateSuffix;
    if (suffix == null) return null;
    return File(
      '${_identityFile.parent.path}${Platform.pathSeparator}state-$suffix.json',
    );
  }

  @override
  Future<Identity> loadOrCreateIdentity() async {
    if (!await _identityFile.exists()) {
      final privateKey = KnockCrypto.randomBytes(KnockCrypto.keyLength);
      await _identityFile.parent.create(recursive: true);
      // 与 Go CLI 的 identity.json 兼容：只写 v1_box_priv 也能被 LoadIdentity 读取。
      await _writeJson(_identityFile, {
        'v1_box_priv': base64.encode(privateKey),
      });
      return _identityFor(privateKey);
    }

    Map<String, dynamic> json;
    try {
      json = jsonDecode(await _identityFile.readAsString())
          as Map<String, dynamic>;
    } catch (_) {
      throw const IdentityStoreException('身份文件不是合法 JSON，拒绝覆盖');
    }
    final encoded = json['v1_box_priv'] as String?;
    if (encoded == null || encoded.isEmpty) {
      throw const IdentityStoreException('身份文件缺少 v1_box_priv，拒绝覆盖');
    }
    Uint8List privateKey;
    try {
      privateKey = base64.decode(encoded);
    } catch (_) {
      throw const IdentityStoreException('身份文件里的 v1_box_priv 不是合法 base64');
    }
    if (privateKey.length != KnockCrypto.keyLength) {
      throw const IdentityStoreException('身份文件里的私钥长度不正确');
    }
    return _identityFor(privateKey);
  }

  Future<Identity> _identityFor(Uint8List privateKey) async {
    final identity = await identityFromPrivateKey(privateKey);
    _stateSuffix = identity.fingerprint.substring(0, 8).toLowerCase();
    return identity;
  }

  @override
  Future<SessionState> loadState() async {
    final file = await _ensureStateFile();
    if (!await file.exists()) return SessionState();
    try {
      final json = jsonDecode(await file.readAsString());
      return SessionState.fromJson(json as Map<String, dynamic>);
    } catch (_) {
      return SessionState();
    }
  }

  @override
  Future<void> saveState(SessionState state) async {
    final file = await _ensureStateFile();
    await file.parent.create(recursive: true);
    await _writeJson(file, state.toJson());
  }

  Future<File> _ensureStateFile() async {
    if (_stateSuffix == null) {
      await loadOrCreateIdentity();
    }
    return _stateFile!;
  }

  Future<void> _writeJson(File file, Map<String, dynamic> data) async {
    final content = const JsonEncoder.withIndent('  ').convert(data);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(content, flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }
}
