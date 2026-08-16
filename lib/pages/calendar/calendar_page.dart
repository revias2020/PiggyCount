import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../providers/transaction_providers.dart';
import '../../styles/tokens.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/page_status.dart';
import '../../widgets/transaction/transaction_row_tile.dart';
import '../transaction/record_editor_sheet.dart';

/// 日历页：月格每日收支摘要 + 选中日账单 + 在该日记账。
class CalendarPage extends ConsumerWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(calendarMonthProvider);
    final selected = ref.watch(calendarSelectedDayProvider);
    final totalsAsync = ref.watch(calendarDailyTotalsProvider);
    final dayAsync = ref.watch(calendarDayTransactionsProvider);

    return Scaffold(
      backgroundColor: PigTokens.scaffoldBackground,
      appBar: AppBar(
        title: const Text('日历'),
        actions: [
          TextButton(
            onPressed: () {
              final now = DateTime.now();
              ref.read(calendarMonthProvider.notifier).state =
                  DateTime(now.year, now.month);
              ref.read(calendarSelectedDayProvider.notifier).state =
                  DateTime(now.year, now.month, now.day);
            },
            child: const Text('今天'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          PigTokens.spaceLg,
          PigTokens.spaceSm,
          PigTokens.spaceLg,
          PigTokens.spaceXl,
        ),
        children: [
          Material(
            color: PigTokens.surface,
            borderRadius: BorderRadius.circular(PigTokens.radiusCard),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                PigTokens.spaceSm,
                PigTokens.spaceMd,
                PigTokens.spaceSm,
                PigTokens.spaceMd,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () {
                          final m = ref.read(calendarMonthProvider);
                          ref.read(calendarMonthProvider.notifier).state =
                              DateTime(m.year, m.month - 1);
                          ref.read(calendarSelectedDayProvider.notifier).state =
                              null;
                        },
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Text(
                          DateFormat('y年M月').format(month),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          final m = ref.read(calendarMonthProvider);
                          ref.read(calendarMonthProvider.notifier).state =
                              DateTime(m.year, m.month + 1);
                          ref.read(calendarSelectedDayProvider.notifier).state =
                              null;
                        },
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  const SizedBox(height: PigTokens.spaceSm),
                  totalsAsync.when(
                    loading: () => const SizedBox(
                      height: 240,
                      child: AppLoading(message: '加载日历…'),
                    ),
                    error: (e, _) => const SizedBox(
                      height: 120,
                      child: Center(child: Text('加载失败')),
                    ),
                    data: (totals) => _MonthGrid(
                      month: month,
                      selected: selected,
                      totals: totals,
                      onSelect: (day) {
                        ref.read(calendarSelectedDayProvider.notifier).state =
                            day;
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (selected != null) ...[
            const SizedBox(height: PigTokens.spaceLg),
            Row(
              children: [
                Expanded(
                  child: Text(
                    formatDayTitle(selected),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: PigTokens.textPrimary,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => showRecordEditorSheet(
                    context,
                    initialDate: selected,
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('在该日记账'),
                  style: FilledButton.styleFrom(
                    foregroundColor: PigTokens.primary,
                    backgroundColor: PigTokens.primarySoft,
                  ),
                ),
              ],
            ),
            const SizedBox(height: PigTokens.spaceSm),
            Material(
              color: PigTokens.surface,
              borderRadius: BorderRadius.circular(PigTokens.radiusCard),
              clipBehavior: Clip.antiAlias,
              child: dayAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(PigTokens.spaceXl),
                  child: AppLoading(),
                ),
                error: (e, _) => const Padding(
                  padding: EdgeInsets.all(PigTokens.spaceLg),
                  child: Text('加载失败'),
                ),
                data: (items) {
                  if (items.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: PigTokens.spaceXl),
                      child: EmptyState(
                        icon: Icons.event_busy_outlined,
                        message: '这一天还没有账单',
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        TransactionRowTile(item: items[i]),
                        if (i != items.length - 1)
                          const Divider(height: 1, indent: 72),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.totals,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime? selected;
  final Map<String, (double income, double expense)> totals;
  final ValueChanged<DateTime> onSelect;

  static const _weekLabels = ['一', '二', '三', '四', '五', '六', '日'];

  String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _compact(double v, {required bool expense}) {
    final prefix = expense ? '-' : '+';
    final abs = v.abs();
    if (abs >= 10000) {
      return '$prefix${(abs / 10000).toStringAsFixed(1)}w';
    }
    if (abs >= 1000) {
      return '$prefix${(abs / 1000).toStringAsFixed(1)}k';
    }
    return '$prefix${abs == abs.roundToDouble() ? abs.toInt() : abs.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    // Monday=1 … Sunday=7 → grid offset 0…6
    final startOffset = first.weekday - 1;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final cellCount = ((startOffset + daysInMonth + 6) ~/ 7) * 7;
    final today = DateTime.now();

    return Column(
      children: [
        Row(
          children: [
            for (final label in _weekLabels)
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: PigTokens.textTertiary,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: PigTokens.spaceXs),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cellCount,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: 64,
          ),
          itemBuilder: (context, index) {
            final dayNum = index - startOffset + 1;
            if (dayNum < 1 || dayNum > daysInMonth) {
              return const SizedBox.shrink();
            }
            final day = DateTime(month.year, month.month, dayNum);
            final isSelected = selected != null &&
                selected!.year == day.year &&
                selected!.month == day.month &&
                selected!.day == day.day;
            final isToday = today.year == day.year &&
                today.month == day.month &&
                today.day == day.day;
            final pair = totals[_key(day)];
            final income = pair?.$1 ?? 0;
            final expense = pair?.$2 ?? 0;

            return InkWell(
              onTap: () => onSelect(day),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? PigTokens.primary
                          : isToday
                              ? PigTokens.primarySoft
                              : null,
                    ),
                    child: Text(
                      '$dayNum',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? PigTokens.textOnPrimary
                            : PigTokens.textPrimary,
                      ),
                    ),
                  ),
                  if (expense > 0)
                    Text(
                      _compact(expense, expense: true),
                      style: const TextStyle(
                        fontSize: 9,
                        color: PigTokens.expense,
                        height: 1.1,
                      ),
                    ),
                  if (income > 0)
                    Text(
                      _compact(income, expense: false),
                      style: const TextStyle(
                        fontSize: 9,
                        color: PigTokens.income,
                        height: 1.1,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
