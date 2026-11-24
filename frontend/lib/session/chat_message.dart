enum MessageStatus { sending, sent, read, failed }

class ChatMessage {
  final String text;
  final bool isMine;
  final DateTime time;
  final String? mid;
  final MessageStatus status;
  final bool isSystem;

  const ChatMessage({
    required this.text,
    required this.isMine,
    required this.time,
    this.mid,
    this.status = MessageStatus.sent,
    this.isSystem = false,
  });

  bool get failed => status == MessageStatus.failed;

  ChatMessage copyWith({MessageStatus? status}) => ChatMessage(
        text: text,
        isMine: isMine,
        time: time,
        mid: mid,
        status: status ?? this.status,
        isSystem: isSystem,
      );
}