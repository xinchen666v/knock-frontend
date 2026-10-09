import 'dart:convert';
import 'dart:math';

/// 协议版本，必须与 Go 端 protocol.Version 一致
const int kProtocolVersion = 1;

// === 客户端 → 服务端 ===
const String kTypeNew = 'NEW';
const String kTypeSub = 'SUB';
const String kTypeSend = 'SEND';
const String kTypeAck = 'ACK';
const String kTypePing = 'PING';

// === 服务端 → 客户端 ===
const String kTypeNewOk = 'NEW_OK';
const String kTypeSubOk = 'SUB_OK';
const String kTypeDeliver = 'DELIVER';
const String kTypePong = 'PONG';
const String kTypeError = 'ERROR';

// === 错误码（与 Go 端 protocol.Code* 一致）===
const int kCodeBadRequest = 400;
const int kCodeQueueNotFound = 404;
const int kCodeQueueFull = 429;
const int kCodeNoSubscriber = 503;

/// 信封：与 Go 端 protocol.Envelope 一一对应
class Envelope {
  final int version;
  final String type;
  final String? queueId;
  final String? msgId;
  final int ts;
  final Map<String, dynamic> payload;

  Envelope({
    this.version = kProtocolVersion,
    required this.type,
    this.queueId,
    this.msgId,
    int? ts,
    Map<String, dynamic>? payload,
  })  : ts = ts ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
        payload = payload ?? const {};

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{
      'v': version,
      'type': type,
      'ts': ts,
      'payload': payload,
    };
    if (queueId != null && queueId!.isNotEmpty) m['qid'] = queueId;
    if (msgId != null && msgId!.isNotEmpty) m['mid'] = msgId;
    return m;
  }

  String encode() => jsonEncode(toMap());

  factory Envelope.fromMap(Map<String, dynamic> map) => Envelope(
        version: map['v'] as int? ?? 0,
        type: map['type'] as String? ?? '',
        queueId: map['qid'] as String?,
        msgId: map['mid'] as String?,
        ts: map['ts'] as int? ?? 0,
        payload: (map['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
      );

  factory Envelope.decode(String data) =>
      Envelope.fromMap(jsonDecode(data) as Map<String, dynamic>);
}

// === Payload 解码辅助 ===

class ErrorPayload {
  final int code;
  final String message;
  const ErrorPayload({required this.code, required this.message});
  factory ErrorPayload.fromMap(Map<String, dynamic> m) => ErrorPayload(
        code: m['code'] as int? ?? 0,
        message: m['message'] as String? ?? '',
      );
}

class NewOkPayload {
  final String queueId;
  const NewOkPayload({required this.queueId});
  factory NewOkPayload.fromMap(Map<String, dynamic> m) =>
      NewOkPayload(queueId: m['qid'] as String? ?? '');
}

class ChatPayload {
  final String text;
  const ChatPayload({required this.text});
  Map<String, dynamic> toMap() => {'text': text};
  factory ChatPayload.fromMap(Map<String, dynamic> m) =>
      ChatPayload(text: m['text'] as String? ?? '');
}

/// 生成 32 位小写十六进制 ID（与 Go 端 protocol.NewID 一致）
String generateId() {
  final rand = Random.secure();
  final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// 校验 qid：32 位小写 hex
bool validQueueId(String qid) {
  if (qid.length != 32) return false;
  return RegExp(r'^[0-9a-f]{32}$').hasMatch(qid);
}