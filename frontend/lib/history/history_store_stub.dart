import '../contacts/contact.dart';
import '../platform/app_env.dart';
import '../session/chat_message.dart';
import 'history_store_base.dart';

HistoryStore createPlatformHistoryStore(AppEnv env) => const _NoopHistoryStore();

/// Web 等没有 SQLite 的平台上不保存历史，但功能本身照常工作。
class _NoopHistoryStore implements HistoryStore {
  const _NoopHistoryStore();

  @override
  Future<void> open() async {}

  @override
  Future<List<ChatMessage>> load(String peerFingerprint) async => const [];

  @override
  Future<void> save(String peerFingerprint, ChatMessage message) async {}

  @override
  Future<void> saveAll(
    String peerFingerprint,
    Iterable<ChatMessage> messages,
  ) async {}

  @override
  Future<void> remove(String peerFingerprint, String mid) async {}

  @override
  Future<void> clearPeer(String peerFingerprint) async {}

  @override
  Future<List<Contact>> loadContacts({
    required Set<String> verifiedFingerprints,
  }) async =>
      const [];

  @override
  Future<void> upsertContact({
    required String fingerprint,
    required String inviteLink,
    required DateTime lastSeen,
  }) async {}

  @override
  Future<String?> contactAlias(String fingerprint) async => null;

  @override
  Future<void> renameContact(String fingerprint, String? alias) async {}

  @override
  Future<void> deleteContact(String fingerprint) async {}

  @override
  Future<void> close() async {}
}