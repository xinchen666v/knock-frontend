import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:knock/history/history_store.dart';
import 'package:knock/identity/identity_store.dart';
import 'package:knock/platform/app_env.dart';
import 'package:knock/session/session.dart';

const _peer = 'AAAAAAAABBBBBBBB';

void main() {
  late Directory dir;
  late AppEnv env;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('knock-contacts-');
    env = AppEnv(identityPath: '${dir.path}/identity.json');

    final identities = createIdentityStore(env);
    await identities.loadOrCreateIdentity();
    final state = await identities.loadState();
    state.verifiedFingerprints.add(_peer);
    await identities.saveState(state);

    final store = createHistoryStore(env);
    await store.open();
    await store.upsertContact(
      fingerprint: _peer,
      inviteLink: 'knock://example:7801/v2/placeholder',
      lastSeen: DateTime.now(),
    );
    await store.save(
      _peer,
      ChatMessage(
        text: 'hello',
        isMine: false,
        time: DateTime.now(),
        mid: 'm1',
      ),
    );
    await store.close();
  });

  test('重命名联系人后重新加载能看到新名字', () async {
    final testDir = dir;
    final session = Session(env: env);
    addTearDown(() async {
      session.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      try {
        await testDir.delete(recursive: true);
      } catch (_) {}
    });

    var contacts = await session.loadContacts();
    expect(contacts.single.alias, isNull);

    await session.renameContact(_peer, '小明');
    contacts = await session.loadContacts();
    expect(contacts.single.alias, '小明');
  });

  test('删除联系人会同时清除历史和已核实标记', () async {
    final testDir = dir;
    final session = Session(env: env);
    addTearDown(() async {
      session.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      try {
        await testDir.delete(recursive: true);
      } catch (_) {}
    });

    final contact = (await session.loadContacts()).single;
    expect(contact.verified, isTrue);

    await session.deleteContact(contact);

    expect(await session.loadContacts(), isEmpty);

    final state = await createIdentityStore(env).loadState();
    expect(state.verifiedFingerprints.contains(_peer), isFalse);

    final store = createHistoryStore(env);
    await store.open();
    addTearDown(store.close);
    expect(await store.load(_peer), isEmpty);
  });
}