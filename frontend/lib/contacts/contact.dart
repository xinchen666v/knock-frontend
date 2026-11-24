class ContactPreview {
  final String text;
  final DateTime time;
  final bool isMine;

  const ContactPreview({
    required this.text,
    required this.time,
    required this.isMine,
  });
}

class Contact {
  final String fingerprint;
  final String inviteLink;
  final String? alias;
  final bool verified;
  final DateTime? lastSeen;
  final ContactPreview? lastMessage;

  const Contact({
    required this.fingerprint,
    required this.inviteLink,
    this.alias,
    this.verified = false,
    this.lastSeen,
    this.lastMessage,
  });

  String get displayName => contactDisplayName(fingerprint, alias);

  DateTime? get lastActivity => lastMessage?.time ?? lastSeen;

  String get previewText {
    final message = lastMessage;
    if (message == null) return '还没有消息';
    final text = message.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return message.isMine ? '你：…' : '…';
    return message.isMine ? '你：$text' : text;
  }
}

String contactDisplayName(String fingerprint, String? alias) {
  final trimmed = alias?.trim();
  if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  return '联系人 ${shortFingerprint(fingerprint)}';
}

String shortFingerprint(String fingerprint) {
  final chars = fingerprint.length > 8 ? fingerprint.substring(0, 8) : fingerprint;
  if (chars.length <= 4) return chars;
  return '${chars.substring(0, 4)} ${chars.substring(4)}';
}

String groupFingerprint(String fingerprint) {
  final buffer = StringBuffer();
  for (var i = 0; i < fingerprint.length; i += 4) {
    if (i > 0) buffer.write(' ');
    buffer.write(
      fingerprint.substring(i, (i + 4).clamp(0, fingerprint.length)),
    );
  }
  return buffer.toString();
}