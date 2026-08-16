import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_database.dart';
import '../data/repositories/ledger_repository.dart';
import 'database_provider.dart';

/// 账本列表项（UI 层）；[id] 对应数据库主键。
class LedgerItem {
  const LedgerItem({required this.id, required this.name});

  final int id;
  final String name;
}

/// 当前会话：全部账本 + 当前选中 id。
class LedgerSession {
  const LedgerSession({
    required this.ledgers,
    required this.currentId,
  });

  final List<LedgerItem> ledgers;
  final int currentId;

  LedgerItem get current => ledgers.firstWhere(
        (e) => e.id == currentId,
        orElse: () => ledgers.first,
      );
}

/// 持久化账本会话：监听 DB 变化，并记住当前账本 id。
class LedgerSessionNotifier extends StateNotifier<AsyncValue<LedgerSession>> {
  LedgerSessionNotifier(this._ref) : super(const AsyncValue.loading()) {
    _bind();
  }

  final Ref _ref;
  StreamSubscription<List<Ledger>>? _sub;

  LedgerRepository get _repo => _ref.read(ledgerRepositoryProvider);

  void _bind() {
    _sub?.cancel();
    _sub = _repo.watchAll().listen((rows) async {
      if (rows.isEmpty) {
        state = AsyncValue.error(StateError('无账本'), StackTrace.current);
        return;
      }
      final saved = await _repo.readCurrentLedgerId();
      final currentId = rows.any((e) => e.id == saved)
          ? saved!
          : rows.first.id;
      if (saved != currentId) {
        await _repo.setCurrentLedgerId(currentId);
      }
      state = AsyncValue.data(
        LedgerSession(
          ledgers: [
            for (final e in rows) LedgerItem(id: e.id, name: e.name),
          ],
          currentId: currentId,
        ),
      );
    }, onError: (Object e, StackTrace st) {
      state = AsyncValue.error(e, st);
    });
  }

  Future<void> select(int id) async {
    await _repo.setCurrentLedgerId(id);
    // 当前账本写在 app_settings，不会触发 ledgers.watch；需同步刷新会话态。
    final current = state.valueOrNull;
    if (current == null) return;
    if (!current.ledgers.any((e) => e.id == id)) return;
    state = AsyncValue.data(
      LedgerSession(ledgers: current.ledgers, currentId: id),
    );
  }

  Future<void> create(String name) => _repo.create(name);

  Future<void> rename(int id, String name) => _repo.rename(id, name);

  /// 返回 false 表示拒绝删除（仅剩一本）。
  Future<bool> delete(int id) => _repo.delete(id);

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final ledgerSessionProvider =
    StateNotifierProvider<LedgerSessionNotifier, AsyncValue<LedgerSession>>(
  (ref) => LedgerSessionNotifier(ref),
);

/// 当前账本 id；未就绪时为 null。
final currentLedgerIdProvider = Provider<int?>((ref) {
  return ref.watch(ledgerSessionProvider).valueOrNull?.currentId;
});
