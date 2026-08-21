import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/transaction_repository.dart';
import '../../providers/pending_review_providers.dart';
import '../../providers/transaction_providers.dart';
import '../../services/automation/pending_review_store.dart';
import '../../styles/tokens.dart';
import '../../utils/app_permissions.dart';
import '../../utils/money_format.dart';
import '../../widgets/details/details_header.dart';
import '../../widgets/details/pending_review_sheet.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/page_status.dart';
import '../../widgets/record_fab.dart';
import '../../widgets/transaction/transaction_row_tile.dart';
import '../calendar/calendar_page.dart';
import '../transaction/image_billing_sheet.dart';
import '../transaction/record_editor_sheet.dart';
import '../transaction/search_page.dart';
import '../transaction/voice_billing_sheet.dart';

/// 「明细」：一体顶栏 + 月度汇总条 + 按日分组列表 + 记一笔。
class DetailsPage extends ConsumerStatefulWidget {
  const DetailsPage({super.key});

  @override
  ConsumerState<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends ConsumerState<DetailsPage> {
  final _scrollController = ScrollController();
  final _rowKeys = <String, GlobalKey>{};

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(String syncId) =>
      _rowKeys.putIfAbsent(syncId, GlobalKey.new);

  Future<void> _handleJump(String syncId) async {
    final entries = ref.read(pendingReviewProvider).entries;
    PendingReviewEntry? entry;
    for (final e in entries) {
      if (e.syncId == syncId) {
        entry = e;
        break;
      }
    }
    final happenedAt = entry?.happenedAt;
    if (happenedAt != null) {
      final targetMonth = DateTime(happenedAt.year, happenedAt.month);
      final current = ref.read(detailsMonthProvider);
      if (current.year != targetMonth.year ||
          current.month != targetMonth.month) {
        ref.read(detailsMonthProvider.notifier).state = targetMonth;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      for (var i = 0; i < 12; i++) {
        final ctx = _rowKeys[syncId]?.currentContext;
        if (ctx != null && ctx.mounted) {
          await Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            alignment: 0.2,
          );
          if (!mounted) return;
          ref.read(pendingReviewProvider.notifier).consumeJump();
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 40));
        if (!mounted) return;
      }
      if (!mounted) return;
      ref.read(pendingReviewProvider.notifier).consumeJump();
    });
  }

  @override
  Widget build(BuildContext context) {
    final month = ref.watch(detailsMonthProvider);
    final asyncLedger = ref.watch(monthLedgerProvider);
    final pending = ref.watch(pendingReviewProvider);

    ref.listen<String?>(
      pendingReviewProvider.select((s) => s.jumpToSyncId),
      (prev, next) {
        if (next != null && next != prev) {
          _handleJump(next);
        }
      },
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DetailsTopBar(
              onOpenCalendar: () {
                final detailsMonth = ref.read(detailsMonthProvider);
                ref.read(calendarMonthProvider.notifier).state = DateTime(
                  detailsMonth.year,
                  detailsMonth.month,
                );
                final now = DateTime.now();
                final sameMonth = detailsMonth.year == now.year &&
                    detailsMonth.month == now.month;
                ref.read(calendarSelectedDayProvider.notifier).state = sameMonth
                    ? DateTime(now.year, now.month, now.day)
                    : null;
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CalendarPage(),
                  ),
                );
              },
              onOpenSearch: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SearchPage(),
                  ),
                );
              },
              onOpenPendingReview: () => showPendingReviewSheet(context),
            ),
            MonthSummaryBar(
              month: month,
              income: asyncLedger.valueOrNull?.monthIncome ?? 0,
              expense: asyncLedger.valueOrNull?.monthExpense ?? 0,
              onMonthChanged: (m) {
                ref.read(detailsMonthProvider.notifier).state =
                    DateTime(m.year, m.month);
              },
            ),
            const Divider(height: 1),
            Expanded(
              child: asyncLedger.when(
                loading: () => const AppLoading(message: '加载账单…'),
                error: (e, _) => AppErrorState(
                  message: '加载失败，请稍后重试',
                  onRetry: () => ref.invalidate(monthTransactionsProvider),
                ),
                data: (ledger) {
                  if (ledger.isEmpty) {
                    return const EmptyState(
                      icon: Icons.receipt_long_outlined,
                      message: '暂无数据',
                      detail: '点击右下角「记一笔」开始记账',
                    );
                  }
                  return _GroupedTransactionList(
                    days: ledger.days,
                    scrollController: _scrollController,
                    highlightSyncIds: pending.highlightSyncIds,
                    rowKeyFor: _keyFor,
                    onOpenRow: (item) async {
                      final highlighted = ref
                          .read(pendingReviewProvider)
                          .isHighlighted(item.tx.syncId);
                      if (highlighted) {
                        await ref
                            .read(pendingReviewProvider.notifier)
                            .markRead(item.tx.syncId);
                        return;
                      }
                      if (!context.mounted) return;
                      await showRecordEditorSheet(
                        context,
                        transactionId: item.tx.id,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
        Positioned(
          right: PigTokens.spaceLg,
          bottom: 36,
          child: RecordFab(
            onPressed: () => showRecordEditorSheet(context),
            onAction: (action) async {
              switch (action) {
                case RecordFabAction.camera:
                  final cam = await AppPermissions.requestCamera();
                  if (!context.mounted) return;
                  if (!cam.granted) {
                    AppPermissions.showDenied(context, cam);
                    return;
                  }
                  await takePhotoForBilling(context);
                case RecordFabAction.voice:
                  await showVoiceBillingSheet(context);
                case RecordFabAction.gallery:
                  final photos = await AppPermissions.requestPhotos();
                  if (!context.mounted) return;
                  if (!photos.granted) {
                    AppPermissions.showDenied(context, photos);
                    return;
                  }
                  await pickImageForBilling(context, source: 'screenshot');
              }
            },
          ),
        ),
      ],
    );
  }
}

class _GroupedTransactionList extends StatelessWidget {
  const _GroupedTransactionList({
    required this.days,
    required this.scrollController,
    required this.highlightSyncIds,
    required this.rowKeyFor,
    required this.onOpenRow,
  });

  final List<DayTransactionGroup> days;
  final ScrollController scrollController;
  final Set<String> highlightSyncIds;
  final GlobalKey Function(String syncId) rowKeyFor;
  final Future<void> Function(TransactionListItem item) onOpenRow;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(
        PigTokens.spaceLg,
        PigTokens.spaceXs,
        PigTokens.spaceLg,
        88,
      ),
      itemCount: days.length,
      itemBuilder: (context, index) {
        final group = days[index];
        return _DaySection(
          group: group,
          highlightSyncIds: highlightSyncIds,
          rowKeyFor: rowKeyFor,
          onOpenRow: onOpenRow,
        );
      },
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({
    required this.group,
    required this.highlightSyncIds,
    required this.rowKeyFor,
    required this.onOpenRow,
  });

  final DayTransactionGroup group;
  final Set<String> highlightSyncIds;
  final GlobalKey Function(String syncId) rowKeyFor;
  final Future<void> Function(TransactionListItem item) onOpenRow;

  @override
  Widget build(BuildContext context) {
    final day = group.day;
    final weekday = DateFormat('EEEE', 'zh_CN').format(day);
    final today = DateTime.now();
    final isToday = day.year == today.year &&
        day.month == today.month &&
        day.day == today.day;
    final title = isToday
        ? '${DateFormat('M月d日').format(day)} · 今天'
        : '${DateFormat('M月d日').format(day)} · $weekday';

    return Padding(
      padding: const EdgeInsets.only(bottom: PigTokens.spaceMd),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PigTokens.spaceXs,
              PigTokens.spaceSm,
              PigTokens.spaceXs,
              PigTokens.spaceSm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: PigTokens.textSecondary,
                    ),
                  ),
                ),
                Text(
                  '支 ¥${formatMoney(group.expense)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: PigTokens.textTertiary,
                  ),
                ),
                const SizedBox(width: PigTokens.spaceSm),
                Text(
                  '收 ¥${formatMoney(group.income)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: PigTokens.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: PigTokens.surface,
            borderRadius: BorderRadius.circular(PigTokens.radiusCard),
            clipBehavior: Clip.none,
            child: Column(
              children: [
                for (var i = 0; i < group.items.length; i++) ...[
                  KeyedSubtree(
                    key: rowKeyFor(group.items[i].tx.syncId),
                    child: TransactionRowTile(
                      item: group.items[i],
                      enableLongPressDelete: true,
                      pendingHighlight: highlightSyncIds
                          .contains(group.items[i].tx.syncId),
                      onTap: () => onOpenRow(group.items[i]),
                    ),
                  ),
                  if (i != group.items.length - 1)
                    const Divider(height: 1, indent: 60),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
