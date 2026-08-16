import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/transaction_repository.dart';
import '../../providers/database_provider.dart';
import '../../providers/transaction_providers.dart';
import '../../styles/tokens.dart';
import '../../utils/app_permissions.dart';
import '../../widgets/category_icon_view.dart';
import '../../widgets/details/details_header.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/page_status.dart';
import '../../widgets/record_fab.dart';
import '../calendar/calendar_page.dart';
import '../transaction/image_billing_sheet.dart';
import '../transaction/record_editor_sheet.dart';
import '../transaction/search_page.dart';
import '../transaction/voice_billing_sheet.dart';

/// 「明细」：一体顶栏 + 月度汇总条 + 按日分组列表 + 记一笔。
class DetailsPage extends ConsumerWidget {
  const DetailsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(detailsMonthProvider);
    final asyncLedger = ref.watch(monthLedgerProvider);

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
                  return _GroupedTransactionList(days: ledger.days);
                },
              ),
            ),
          ],
        ),
        Positioned(
          right: PigTokens.spaceLg,
          bottom: PigTokens.spaceLg,
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

class _GroupedTransactionList extends ConsumerWidget {
  const _GroupedTransactionList({required this.days});

  final List<DayTransactionGroup> days;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        PigTokens.spaceLg,
        PigTokens.spaceXs,
        PigTokens.spaceLg,
        88,
      ),
      itemCount: days.length,
      itemBuilder: (context, index) {
        final group = days[index];
        return _DaySection(group: group);
      },
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({required this.group});

  final DayTransactionGroup group;

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
                  '支 ¥${group.expense.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: PigTokens.textTertiary,
                  ),
                ),
                const SizedBox(width: PigTokens.spaceSm),
                Text(
                  '收 ¥${group.income.toStringAsFixed(2)}',
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
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < group.items.length; i++) ...[
                  _TxTile(item: group.items[i]),
                  if (i != group.items.length - 1)
                    const Divider(height: 1, indent: 64),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TxTile extends ConsumerWidget {
  const _TxTile({required this.item});

  final TransactionListItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tx = item.tx;
    final isExpense = tx.type == 'expense';
    final amountText =
        '${isExpense ? '-' : '+'}${tx.amount.toStringAsFixed(2)}';

    return Dismissible(
      key: ValueKey('tx-${tx.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: PigTokens.danger,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: PigTokens.spaceXl),
        child: const Icon(Icons.delete, color: PigTokens.textOnPrimary),
      ),
      confirmDismiss: (_) async {
        final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('删除账单'),
                content: const Text('确定删除这条账单？'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('删除'),
                  ),
                ],
              ),
            ) ??
            false;
        if (!confirmed) return false;
        await ref.read(transactionRepositoryProvider).delete(tx.id);
        return true;
      },
      onDismissed: (_) {},
      child: ListTile(
        onTap: () => showRecordEditorSheet(context, transactionId: tx.id),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: PigTokens.spaceLg,
          vertical: PigTokens.spaceXs,
        ),
        leading: CircleAvatar(
          backgroundColor: PigTokens.primarySoft,
          child: CategoryIconView(
            name: item.categoryName ?? '未分类',
            icon: item.categoryIcon,
            iconType: item.categoryIconType,
            customIconPath: item.categoryCustomIconPath,
            color: PigTokens.primary,
            size: 20,
          ),
        ),
        title: Text(
          item.categoryName ?? '未分类',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          [
            DateFormat('HH:mm').format(tx.happenedAt),
            if (tx.note != null && tx.note!.isNotEmpty) tx.note!,
            if (item.tagNames.isNotEmpty) item.tagNames.join(' · '),
          ].join('  '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: PigTokens.textTertiary),
        ),
        trailing: Text(
          amountText,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: isExpense ? PigTokens.expense : PigTokens.income,
          ),
        ),
      ),
    );
  }
}
