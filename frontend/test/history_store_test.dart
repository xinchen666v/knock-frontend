import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:knock/history/history_store.dart';
import 'package:knock/platform/app_env.dart';
import 'package:knock/session/session.dart';

void main() {
  late Directory dir;
  late HistoryStore store;

  HistoryStore makeStore() => createHistoryStore(
        AppEnv(identityPath: '${dir.path}/identity.json'),
      );

  ChatMessage message(
    String text, {
    bool mine = false,
    String? mid,
    DateTime? time,
    MessageStatus status = MessageStatus.sent,
  }) =>
      ChatMessage(
        text: text,
        isMine: mine,
        time: time ?? DateTime.now(),
        mid: mid,
        status: status,
      );

  List<String> texts(List<ChatMessage> messages) =>
      messages.map((m) => m.text).toList();

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('knock-history-');
    store = makeStore();
    await store.open();
  });

  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });

  test('按联系人归档，并按时间顺序读取', () async {
    final now = DateTime.now();
    await store.save(
      'PEER1',
      message('older', mid: 'm1', time: now.subtract(const Duration(minutes: 2))),
    );
    await store.save(
      'PEER1',
      message(
        'newer',
        mine: true,
        mid: 'm2',
        time: now.subtract(const Duration(minutes: 1)),
        status: MessageStatus.read,
      ),
    );
    await store.save('PEER2', message('other peer', mid: 'm3'));

    final peer1 = await store.load('PEER1');
    expect(texts(peer1), ['older', 'newer']);
    expect(peer1.last.isMine, isTrue);
    expect(peer1.last.status, MessageStatus.read);
    expect(peer1.first.mid, 'm1');

    final peer2 = await store.load('PEER2');
    expect(texts(peer2), ['other peer']);
  });

  test('同一 mid 的状态更新会覆盖旧状态', () async {
    final now = DateTime.now();
    await store.save('P', message('hi', mine: true, mid: 'm1', time: now));
    await store.save(
      'P',
      message('hi', mine: true, mid: 'm1', time: now, status: MessageStatus.read),
    );

    final rows = await store.load('P');
    expect(rows, hasLength(1));
    expect(rows.single.status, MessageStatus.read);
  });

  test('发送中和失败的消息不落库', () async {
    await store.saveAll('P', [
      message('sending', mid: 'a', status: MessageStatus.sending),
      message('failed', mid: 'b', status: MessageStatus.failed),
      message('sent', mid: 'c'),
    ]);
    expect(texts(await store.load('P')), ['sent']);
  });

  test('clearPeer 只清除指定联系人', () async {
    await store.save('A', message('from A', mid: 'a'));
    await store.save('B', message('from B', mid: 'b'));

    await store.clearPeer('A');
    expect(await store.load('A'), isEmpty);
    expect(texts(await store.load('B')), ['from B']);
  });

  test('重新打开会清理 30 天前的记录', () async {
    final now = DateTime.now();
    await store.save(
      'P',
      message(
        'expired',
        mid: 'old',
        time: now.subtract(const Duration(days: 31)),
      ),
    );
    await store.save('P', message('fresh', mid: 'new', time: now));
    expect(texts(await store.load('P')), ['expired', 'fresh']);

    await store.close();
    store = makeStore();
    await store.open();

    expect(texts(await store.load('P')), ['fresh']);
    expect(File('${dir.path}/history.db').existsSync(), isTrue);
  });

  test('联系人按最后活动排序并带出最后一条消息', () async {
    final now = DateTime.now();
    await store.upsertContact(
      fingerprint: 'AAAA',
      inviteLink: 'knock://a',
      lastSeen: now.subtract(const Duration(minutes: 10)),
    );
    await store.upsertContact(
      fingerprint: 'BBBB',
      inviteLink: 'knock://b',
      lastSeen: now.subtract(const Duration(minutes: 5)),
    );
    await store.save(
      'AAAA',
      message(
        'older',
        mid: 'a1',
        time: now.subtract(const Duration(minutes: 6)),
      ),
    );
    await store.save(
      'AAAA',
      message(
        'latest',
        mine: true,
        mid: 'a2',
        time: now.subtract(const Duration(minutes: 2)),
        status: MessageStatus.read,
      ),
    );

    final contacts = await store.loadContacts(
      verifiedFingerprints: {'AAAA'},
    );
    expect(contacts.map((c) => c.fingerprint).toList(), ['AAAA', 'BBBB']);
    expect(contacts[0].verified, isTrue);
    expect(contacts[0].lastMessage?.text, 'latest');
    expect(contacts[0].lastMessage?.isMine, isTrue);
    expect(contacts[0].previewText, '你：latest');
    expect(contacts[1].verified, isFalse);
    expect(contacts[1].lastMessage, isNull);
    expect(contacts[1].previewText, '还没有消息');
  });

  test('重新加入保留别名并更新链接，重命名与清空都生效', () async {
    final now = DateTime.now();
    await store.upsertContact(
      fingerprint: 'AAAA',
      inviteLink: 'old-link',
      lastSeen: now,
    );
    await store.renameContact('AAAA', '  Alice  ');
    await store.upsertContact(
      fingerprint: 'AAAA',
      inviteLink: 'new-link',
      lastSeen: now.add(const Duration(minutes: 1)),
    );

    var contacts = await store.loadContacts(
      verifiedFingerprints: const {},
    );
    expect(contacts.single.alias, 'Alice');
    expect(contacts.single.inviteLink, 'new-link');
    expect(await store.contactAlias('AAAA'), 'Alice');

    await store.renameContact('AAAA', '   ');
    contacts = await store.loadContacts(verifiedFingerprints: const {});
    expect(contacts.single.alias, isNull);
    expect(contacts.single.displayName, contains('AAAA'));
  });

  test('删除联系人会同时删除该联系人的历史', () async {
    final now = DateTime.now();
    await store.upsertContact(
      fingerprint: 'AAAA',
      inviteLink: 'link-a',
      lastSeen: now,
    );
    await store.save('AAAA', message('hi', mid: 'a1', time: now));
    await store.upsertContact(
      fingerprint: 'BBBB',
      inviteLink: 'link-b',
      lastSeen: now,
    );
    await store.save('BBBB', message('yo', mid: 'b1', time: now));

    await store.deleteContact('AAAA');

    expect(await store.load('AAAA'), isEmpty);
    expect(texts(await store.load('BBBB')), ['yo']);
    final contacts = await store.loadContacts(
      verifiedFingerprints: {'AAAA'},
    );
    expect(contacts.map((c) => c.fingerprint).toList(), ['BBBB']);
    expect(await store.contactAlias('AAAA'), isNull);
  });
}