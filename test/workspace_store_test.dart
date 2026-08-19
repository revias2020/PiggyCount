import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:piggy_count/data/app_database.dart';
import 'package:piggy_count/data/repositories/ledger_repository.dart';
import 'package:piggy_count/data/seed_service.dart';
import 'package:piggy_count/sync/workspace_codec.dart';
import 'package:piggy_count/sync/workspace_merge.dart';
import 'package:piggy_count/sync/workspace_store.dart';

void main() {
  test('工作区 JSON 往返保留账本与分类', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await SeedService(db).ensureSeeded();
    final snap = await WorkspaceStore(db).capture();
    expect(snap.categories, isNotEmpty);
    final json = jsonDecode(jsonEncode(WorkspaceCodec.encode(snap))) as Map;
    final back = WorkspaceCodec.decode(Map<String, Object?>.from(json));
    expect(back.categories.length, snap.categories.length);
    expect(back.tagGroups.length, snap.tagGroups.length);
    expect(
      back.ledgers.map((e) => e.syncId).toSet(),
      snap.ledgers.map((e) => e.syncId).toSet(),
    );
  });

  test('两台同名默认账本折合后本机只留一本', () async {
    final local = AppDatabase.memory();
    final remote = AppDatabase.memory();
    addTearDown(local.close);
    addTearDown(remote.close);
    await SeedService(local).ensureSeeded();
    await SeedService(remote).ensureSeeded();

    final store = WorkspaceStore(local);
    final merged = WorkspaceMerge.merge(
      local: await store.capture(),
      remote: await WorkspaceStore(remote).capture(),
    );
    await store.apply(merged.merged);

    final live = await LedgerRepository(local).getAll();
    expect(live, hasLength(1));
    expect(live.single.name, '日常账本');
  });
}
