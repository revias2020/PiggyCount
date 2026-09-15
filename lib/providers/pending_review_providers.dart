import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_database.dart';
import '../services/automation/pending_review_store.dart';
import 'ledger_session_provider.dart';

final pendingReviewStoreProvider = Provider((_) => PendingReviewStore());

class PendingReviewState {
  const PendingReviewState({
    this.entries = const [],
    this.highlightSyncIds = const {},
    this.jumpToSyncId,
    this.jumpSeq = 0,
    this.loaded = false,
  });

  final List<PendingReviewEntry> entries;
  /// 本次前台高亮；进后台清空。
  final Set<String> highlightSyncIds;
  /// 信封未读点击请求滚到的 syncId；明细消费后清空。
  final String? jumpToSyncId;
  /// 每次 [PendingReviewNotifier.requestJump] 递增；同 syncId 也能再次触发滚动。
  final int jumpSeq;
  final bool loaded;

  PendingReviewState copyWith({
    List<PendingReviewEntry>? entries,
    Set<String>? highlightSyncIds,
    String? jumpToSyncId,
    int? jumpSeq,
    bool clearJump = false,
    bool? loaded,
  }) {
    return PendingReviewState(
      entries: entries ?? this.entries,
      highlightSyncIds: highlightSyncIds ?? this.highlightSyncIds,
      jumpToSyncId: clearJump ? null : (jumpToSyncId ?? this.jumpToSyncId),
      jumpSeq: jumpSeq ?? this.jumpSeq,
      loaded: loaded ?? this.loaded,
    );
  }

  List<PendingReviewEntry> forLedger(int ledgerId) {
    final list = entries.where((e) => e.ledgerId == ledgerId).toList()
      ..sort((a, b) => b.happenedAt.compareTo(a.happenedAt));
    return list;
  }

  bool hasPendingForLedger(int ledgerId) =>
      entries.any((e) => e.ledgerId == ledgerId);

  bool isPending(String syncId) => entries.any((e) => e.syncId == syncId);

  bool isHighlighted(String syncId) => highlightSyncIds.contains(syncId);
}

class PendingReviewNotifier extends StateNotifier<PendingReviewState> {
  PendingReviewNotifier(this._store) : super(const PendingReviewState()) {
    _load();
  }

  final PendingReviewStore _store;

  Future<void> _load() async {
    final entries = await _store.load();
    if (!mounted) return;
    state = state.copyWith(
      entries: entries,
      highlightSyncIds: {for (final e in entries) e.syncId},
      loaded: true,
    );
  }

  Future<void> _persist() => _store.save(state.entries);

  Future<void> addFromTransaction(Transaction tx) async {
    if (tx.source != 'screenshot' && tx.source != 'share') return;
    if (state.entries.any((e) => e.syncId == tx.syncId)) {
      // 已在集合：确保高亮
      state = state.copyWith(
        highlightSyncIds: {...state.highlightSyncIds, tx.syncId},
      );
      return;
    }
    final next = [
      ...state.entries,
      PendingReviewEntry(
        syncId: tx.syncId,
        ledgerId: tx.ledgerId,
        happenedAt: tx.happenedAt,
      ),
    ];
    state = state.copyWith(
      entries: next,
      highlightSyncIds: {...state.highlightSyncIds, tx.syncId},
    );
    await _persist();
  }

  Future<void> addFromTransactions(Iterable<Transaction> txs) async {
    for (final tx in txs) {
      await addFromTransaction(tx);
    }
  }

  Future<void> markRead(String syncId) async {
    if (!state.isPending(syncId)) {
      if (state.highlightSyncIds.contains(syncId)) {
        final h = {...state.highlightSyncIds}..remove(syncId);
        state = state.copyWith(highlightSyncIds: h);
      }
      return;
    }
    final next = state.entries.where((e) => e.syncId != syncId).toList();
    final h = {...state.highlightSyncIds}..remove(syncId);
    state = state.copyWith(entries: next, highlightSyncIds: h);
    await _persist();
  }

  Future<void> markAllReadForLedger(int ledgerId) async {
    final removed = state.entries
        .where((e) => e.ledgerId == ledgerId)
        .map((e) => e.syncId)
        .toSet();
    if (removed.isEmpty) return;
    final next = state.entries.where((e) => e.ledgerId != ledgerId).toList();
    final h = {...state.highlightSyncIds}..removeAll(removed);
    state = state.copyWith(entries: next, highlightSyncIds: h);
    await _persist();
  }

  /// App 进后台：清高亮，保留持久待核对。
  void clearHighlights() {
    if (state.highlightSyncIds.isEmpty) return;
    state = state.copyWith(highlightSyncIds: {});
  }

  /// 回前台：按仍待核对重打高亮。
  void reapplyHighlights() {
    state = state.copyWith(
      highlightSyncIds: {for (final e in state.entries) e.syncId},
    );
  }

  void requestJump(String syncId) {
    // 即使 syncId 相同也递增 jumpSeq，否则同笔再点一次不会触发滚动。
    state = state.copyWith(
      jumpToSyncId: syncId,
      jumpSeq: state.jumpSeq + 1,
    );
  }

  /// [seq] 非空时仅消费对应一代跳转，避免旧跳转超时清掉新的 requestJump。
  void consumeJump({int? seq}) {
    if (state.jumpToSyncId == null) return;
    if (seq != null && state.jumpSeq != seq) return;
    state = state.copyWith(clearJump: true);
  }

  /// 账单已删：从待核对去掉。
  Future<void> removeIfPresent(String syncId) async {
    if (!state.isPending(syncId)) return;
    await markRead(syncId);
  }
}

final pendingReviewProvider =
    StateNotifierProvider<PendingReviewNotifier, PendingReviewState>(
  (ref) => PendingReviewNotifier(ref.watch(pendingReviewStoreProvider)),
);

/// 当前账本是否有待核对（红点）。
final pendingReviewHasUnreadProvider = Provider<bool>((ref) {
  final ledgerId = ref.watch(currentLedgerIdProvider);
  if (ledgerId == null) return false;
  return ref.watch(pendingReviewProvider).hasPendingForLedger(ledgerId);
});
