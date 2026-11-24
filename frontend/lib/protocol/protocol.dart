import 'dart:convert';
import 'dart:math';

/// 信封版本，与 Go 端 protocol.Version 一致。
/// 注意：它不是加密版本；加密载荷用 EncryptedMessage.v。
const int kProtocolVersion = 1;

/// 加密载荷版本，与 Go 端 protocol.EncVersion 一致。
const int kEncVersion = 2;

// === 客户端 → 服务端 ===
const String kTypeNew = 'NEW';
const String kTypeSub = 'SUB';
const String kTypeSend = 'SEND';
const String kTypeAck = 'ACK';
const String kTypePing = 'PING';
const String kTypeSignal = 'SIGNAL';

// === 服务端 → 客户端 ===
const String kTypeNewOk = 'NEW_OK';
const String kTypeSubOk = 'SUB_OK';
const String kTypeDeliver = 'DELIVER';
const String kTypePong = 'PONG';
const String kTypeError = 'ERROR';

// === 错误码（与 Go 端 protocol.Code* 一致）===
const int kCodeBadRequest = 400;
const int kCodeForbidden = 403;
const int kCodeQueueNotFound = 404;
const int kCodeTooManyRequests = 429;
const int kCodeServerError = 500;

/// 信封：与 Go 端 protocol.Envelope 一一对应。
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
    final map = <String, dynamic>{
      'v': version,
      'type': type,
      'ts': ts,
      'payload': payload,
    };
    if (queueId != null && queueId!.isNotEmpty) map['qid'] = queueId;
    if (msgId != null && msgId!.isNotEmpty) map['mid'] = msgId;
    return map;
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

// === Payload ===

class ErrorPayload {
  final int code;
  final String message;

  const ErrorPayload({required this.code, required this.message});

  factory ErrorPayload.fromMap(Map<String, dynamic> map) => ErrorPayload(
        code: map['code'] as int? ?? 0,
        message: map['message'] as String? ?? '',
      );
}

class NewOkPayload {
  final String queueId;

  const NewOkPayload({required this.queueId});

  factory NewOkPayload.fromMap(Map<String, dynamic> map) =>
      NewOkPayload(queueId: map['qid'] as String? ?? '');
}

class AckPayload {
  final String mid;

  const AckPayload({required this.mid});

  Map<String, dynamic> toMap() => {'mid': mid};

  factory AckPayload.fromMap(Map<String, dynamic> map) =>
      AckPayload(mid: map['mid'] as String? ?? '');
}

/// SEND / SIGNAL 的线上形态。全部字段是标准 base64（带填充）。
class EncryptedMessage {
  final int version;
  final String nonce;
  final String ciphertext;
  final String ephemeralPublicKey;

  const EncryptedMessage({
    this.version = kEncVersion,
    required this.nonce,
    required this.ciphertext,
    required this.ephemeralPublicKey,
  });

  Map<String, dynamic> toMap() => {
        'v': version,
        'n': nonce,
        'c': ciphertext,
        'e': ephemeralPublicKey,
      };

  factory EncryptedMessage.fromMap(Map<String, dynamic> map) =>
      EncryptedMessage(
        version: map['v'] as int? ?? 0,
        nonce: map['n'] as String? ?? '',
        ciphertext: map['c'] as String? ?? '',
        ephemeralPublicKey: map['e'] as String? ?? '',
      );
}

/// 加密前的聊天明文。kind 为空表示文本；文件分块暂不实现，
/// 但接收端必须识别 kind 并 ACK，否则服务器会无限重投。
class ChatBody {
  final String kind;
  final String text;
  final String from;
  final int ts;

  const ChatBody({
    this.kind = '',
    this.text = '',
    required this.from,
    required this.ts,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{'from': from, 'ts': ts};
    if (kind.isNotEmpty) map['kind'] = kind;
    if (text.isNotEmpty) map['text'] = text;
    return map;
  }

  factory ChatBody.fromMap(Map<String, dynamic> map) => ChatBody(
        kind: map['kind'] as String? ?? '',
        text: map['text'] as String? ?? '',
        from: map['from'] as String? ?? '',
        ts: map['ts'] as int? ?? 0,
      );
}

class SignalMessage {
  final String kind;
  final String state;
  final int ts;

  const SignalMessage({
    required this.kind,
    required this.state,
    required this.ts,
  });

  Map<String, dynamic> toMap() => {'kind': kind, 'state': state, 'ts': ts};

  factory SignalMessage.fromMap(Map<String, dynamic> map) => SignalMessage(
        kind: map['kind'] as String? ?? '',
        state: map['state'] as String? ?? '',
        ts: map['ts'] as int? ?? 0,
      );
}

/// 生成 32 位小写十六进制 ID（与 Go 端 protocol.NewID 一致）。
String generateId() {
  final rand = Random.secure();
  final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// 校验 qid：32 位小写 hex。
bool validQueueId(String qid) {
  if (qid.length != 32) return false;
  return RegExp(r'^[0-9a-f]{32}$').hasMatch(qid);
}
