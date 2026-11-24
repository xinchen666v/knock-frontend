import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../contacts/contact.dart';
import '../platform/app_env.dart';
import '../session/chat_message.dart';
import 'history_store_base.dart';

HistoryStore createPlatformHistoryStore(AppEnv env) => SqliteHistoryStore(env);

/// 明文 SQLite 历史，只保留最近 30 天。
///
/// 文件位置：
/// - 调试模式：identity.json 同目录的 history.db，A/B 实例天然隔离；
/// - 普通模式：系统应用数据目录下的 history.db。
class SqliteHistoryStore implements HistoryStore {
  static const Duration retention = Duration(days: 30);
  static const Duration _pruneInterval = Duration(hours: 1);

  final AppEnv env;

  Database? _db;
  Future<Database>? _opening;
  DateTime? _lastPrune;

  SqliteHistoryStore(this.env);

  @override
  Future<void> open() async {
    await _ensureOpen();
  }

  Future<Database> _ensureOpen() {
    final db = _db;
    if (db != null) return Future.value(db);
    return _opening ??= _open().whenComplete(() => _opening = null);
  }

  Future<Database> _open() async {
    final path = await _resolvePath();
    await File(path).parent.create(recursive: true);

    final db = sqlite3.open(path);
    try {
      db.execute('PRAGMA journal_mode = WAL');
      db.execute('PRAGMA synchronous = NORMAL');
      db.execute('''
        CREATE TABLE IF NOT EXISTS messages (
          peer_fp TEXT NOT NULL,
          mid TEXT NOT NULL,
          is_mine INTEGER NOT NULL,
          text TEXT NOT NULL,
          ts INTEGER NOT NULL,
          status TEXT NOT NULL,
          PRIMARY KEY (peer_fp, mid)
        )
      ''');
      db.execute('''
        CREATE INDEX IF NOT EXISTS idx_messages_peer_ts
        ON messages (peer_fp, ts)
      ''');
      db.execute('''
        CREATE TABLE IF NOT EXISTS contacts (
          fingerprint TEXT NOT NULL PRIMARY KEY,
          invite_link TEXT NOT NULL,
          alias TEXT,
          last_seen INTEGER NOT NULL
        )
      ''');
      db.execute('''
        CREATE INDEX IF NOT EXISTS idx_messages_ts
        ON messages (ts)
      ''');
      if (db.userVersion < 2) db.userVersion = 2;
      _prune(db);
    } catch (_) {
      db.close();
      rethrow;
    }

    _db = db;
    debugPrint('[knock] history db: $path');
    return db;
  }

  Future<String> _resolvePath() async {
    final identityPath = env.identityPath;
    final dir = (identityPath != null && identityPath.isNotEmpty)
        ? File(identityPath).absolute.parent.path
        : (await getApplicationSupportDirectory()).path;
    return '$dir${Platform.pathSeparator}history.db';
  }

  @override
  Future<List<ChatMessage>> load(String peerFingerprint) async {
    final db = await _ensureOpen();
    _maybePrune(db);
    final rows = db.select(
      '''
      SELECT mid, is_mine, text, ts, status
      FROM messages
      WHERE peer_fp = ? AND status IN ('sent', 'read')
      ORDER BY ts ASC, rowid ASC
      ''',
      [peerFingerprint],
    );
    return [
      for (final row in rows)
        ChatMessage(
          text: row['text'] as String,
          isMine: (row['is_mine'] as int) != 0,
          time: DateTime.fromMillisecondsSinceEpoch(row['ts'] as int),
          mid: row['mid'] as String,
          status: _statusFrom(row['status'] as String?),
        ),
    ];
  }

  @override
  Future<void> save(String peerFingerprint, ChatMessage message) =>
      saveAll(peerFingerprint, [message]);

  @override
  Future<void> saveAll(
    String peerFingerprint,
    Iterable<ChatMessage> messages,
  ) async {
    final rows = messages
        .where((message) =>
            !message.isSystem &&
            message.mid != null &&
            message.mid!.isNotEmpty &&
            (message.status == MessageStatus.sent ||
                message.status == MessageStatus.read))
        .toList(growable: false);
    if (rows.isEmpty) return;

    final db = await _ensureOpen();
    _maybePrune(db);
    final statement = db.prepare('''
      INSERT INTO messages (peer_fp, mid, is_mine, text, ts, status)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(peer_fp, mid) DO UPDATE SET
        is_mine = excluded.is_mine,
        text = excluded.text,
        ts = excluded.ts,
        status = excluded.status
    ''');
    db.execute('BEGIN IMMEDIATE');
    try {
      for (final message in rows) {
        statement.execute([
          peerFingerprint,
          message.mid!,
          message.isMine ? 1 : 0,
          message.text,
          message.time.millisecondsSinceEpoch,
          message.status.name,
        ]);
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    } finally {
      statement.close();
    }
  }

  @override
  Future<void> remove(String peerFingerprint, String mid) async {
    final db = await _ensureOpen();
    db.execute(
      'DELETE FROM messages WHERE peer_fp = ? AND mid = ?',
      [peerFingerprint, mid],
    );
  }

  @override
  Future<void> clearPeer(String peerFingerprint) async {
    final db = await _ensureOpen();
    db.execute('DELETE FROM messages WHERE peer_fp = ?', [peerFingerprint]);
  }

  @override
  Future<List<Contact>> loadContacts({
    required Set<String> verifiedFingerprints,
  }) async {
    final db = await _ensureOpen();
    final rows = db.select('''
      SELECT c.fingerprint, c.invite_link, c.alias, c.last_seen,
             m.text AS last_text, m.ts AS last_ts, m.is_mine AS last_mine
      FROM contacts c
      LEFT JOIN messages m ON m.rowid = (
        SELECT rowid FROM messages
        WHERE peer_fp = c.fingerprint AND status IN ('sent', 'read')
        ORDER BY ts DESC, rowid DESC
        LIMIT 1
      )
      ORDER BY COALESCE(m.ts, c.last_seen) DESC
    ''');
    return [
      for (final row in rows) _contactFromRow(row, verifiedFingerprints),
    ];
  }

  Contact _contactFromRow(Row row, Set<String> verifiedFingerprints) {
    final fingerprint = row['fingerprint'] as String;
    final lastText = row['last_text'] as String?;
    ContactPreview? preview;
    if (lastText != null) {
      preview = ContactPreview(
        text: lastText,
        time: DateTime.fromMillisecondsSinceEpoch(row['last_ts'] as int),
        isMine: (row['last_mine'] as int) != 0,
      );
    }
    return Contact(
      fingerprint: fingerprint,
      inviteLink: row['invite_link'] as String,
      alias: row['alias'] as String?,
      verified: verifiedFingerprints.contains(fingerprint),
      lastSeen: DateTime.fromMillisecondsSinceEpoch(
        row['last_seen'] as int,
      ),
      lastMessage: preview,
    );
  }

  @override
  Future<void> upsertContact({
    required String fingerprint,
    required String inviteLink,
    required DateTime lastSeen,
  }) async {
    final db = await _ensureOpen();
    db.execute(
      '''
      INSERT INTO contacts (fingerprint, invite_link, alias, last_seen)
      VALUES (?, ?, NULL, ?)
      ON CONFLICT(fingerprint) DO UPDATE SET
        invite_link = excluded.invite_link,
        last_seen = excluded.last_seen
      ''',
      [fingerprint, inviteLink, lastSeen.millisecondsSinceEpoch],
    );
  }

  @override
  Future<String?> contactAlias(String fingerprint) async {
    final db = await _ensureOpen();
    final rows = db.select(
      'SELECT alias FROM contacts WHERE fingerprint = ?',
      [fingerprint],
    );
    if (rows.isEmpty) return null;
    return rows.first['alias'] as String?;
  }

  @override
  Future<void> renameContact(String fingerprint, String? alias) async {
    final db = await _ensureOpen();
    final normalized =
        (alias == null || alias.trim().isEmpty) ? null : alias.trim();
    db.execute(
      'UPDATE contacts SET alias = ? WHERE fingerprint = ?',
      [normalized, fingerprint],
    );
  }

  @override
  Future<void> deleteContact(String fingerprint) async {
    final db = await _ensureOpen();
    db.execute('BEGIN IMMEDIATE');
    try {
      db.execute(
        'DELETE FROM messages WHERE peer_fp = ?',
        [fingerprint],
      );
      db.execute(
        'DELETE FROM contacts WHERE fingerprint = ?',
        [fingerprint],
      );
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    final opening = _opening;
    if (opening != null) {
      try {
        await opening;
      } catch (_) {}
    }
    _db?.close();
    _db = null;
  }

  void _maybePrune(Database db) {
    final last = _lastPrune;
    if (last != null &&
        DateTime.now().difference(last) < _pruneInterval) {
      return;
    }
    _prune(db);
  }

  void _prune(Database db) {
    final cutoff =
        DateTime.now().subtract(retention).millisecondsSinceEpoch;
    db.execute('DELETE FROM messages WHERE ts < ?', [cutoff]);
    _lastPrune = DateTime.now();
  }

  MessageStatus _statusFrom(String? raw) {
    for (final status in MessageStatus.values) {
      if (status.name == raw) return status;
    }
    return MessageStatus.sent;
  }
}