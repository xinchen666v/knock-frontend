import '../contacts/contact.dart';
import '../session/chat_message.dart';

/// 本地聊天记录与联系人。故意独立于网络层：
/// 只有“已送达/已读”的消息会落库，发送中和失败的消息不持久化。
abstract class HistoryStore {
  Future<void> open();

  Future<List<ChatMessage>> load(String peerFingerprint);

  Future<void> save(String peerFingerprint, ChatMessage message);

  Future<void> saveAll(String peerFingerprint, Iterable<ChatMessage> messages);

  Future<void> remove(String peerFingerprint, String mid);

  Future<void> clearPeer(String peerFingerprint);

  Future<List<Contact>> loadContacts({
    required Set<String> verifiedFingerprints,
  });

  Future<void> upsertContact({
    required String fingerprint,
    required String inviteLink,
    required DateTime lastSeen,
  });

  Future<String?> contactAlias(String fingerprint);

  Future<void> renameContact(String fingerprint, String? alias);

  Future<void> deleteContact(String fingerprint);

  Future<void> close();
}