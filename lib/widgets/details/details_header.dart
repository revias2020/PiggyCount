import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../providers/ledger_session_provider.dart';
import '../../services/sync/cloud_sync_actions.dart';
import '../../services/sync/cloud_sync_providers.dart';
import '../../styles/tokens.dart';
import '../../utils/money_format.dart';
import '../ledger_list_sheet.dart';
import 'year_month_grid_sheet.dart';

/// 明细一体顶栏：品牌图标 + 账本 + 日历 + 同步 + 搜索。
class DetailsTopBar extends ConsumerWidget {
  const DetailsTopBar({
    super.key,
    required this.onOpenCalendar,
    required this.onOpenSearch,
  });

  final VoidCallback onOpenCalendar;
  final VoidCallback onOpenSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(ledgerSessionProvider);
    final name = session.valueOrNull?.current.name ?? '加载中…';

    return Material(
      color: PigTokens.surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            PigTokens.spaceLg,
            PigTokens.spaceSm,
            PigTokens.spaceSm,
            PigTokens.spaceSm,
          ),
          child: Row(
            children: [
              Image.asset(
                'assets/brand/piggyCount.png',
                width: 34,
                height: 34,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.savings_outlined,
                  color: PigTokens.primary,
                  size: 34,
                ),
              ),
              const SizedBox(width: PigTokens.spaceMd),
              Flexible(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(PigTokens.radiusPill),
                    onTap: () => showLedgerListSheet(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: PigTokens.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 20,
                            color: PigTokens.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: '日历',
                onPressed: onOpenCalendar,
                icon: const Icon(Icons.calendar_month_outlined),
                color: PigTokens.textPrimary,
              ),
              _DetailsSyncButton(),
              IconButton(
                tooltip: '搜索',
                onPressed: onOpenSearch,
                icon: const Icon(Icons.search),
                color: PigTokens.textPrimary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailsSyncButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(cloudSyncConfigProvider).valueOrNull;
    final ready = cfg != null && cfg.isReadyForSync;
    return IconButton(
      tooltip: ready ? '同步' : '云服务不可用，请确认配置信息',
      onPressed: ready
          ? () => runWorkspaceSync(context: context, ref: ref)
          : null,
      icon: const Icon(Icons.sync_outlined),
      color: ready ? PigTokens.textPrimary : PigTokens.textTertiary,
    );
  }
}

/// 月份点选 + 收入｜支出｜结余。
class MonthSummaryBar extends StatelessWidget {
  const MonthSummaryBar({
    super.key,
    required this.month,
    required this.income,
    required this.expense,
    required this.onMonthChanged,
  });

  final DateTime month;
  final double income;
  final double expense;
  final ValueChanged<DateTime> onMonthChanged;

  double get _balance => income - expense;

  Future<void> _pickMonth(BuildContext context) async {
    final picked = await showYearMonthGridSheet(
      context,
      initialMonth: month,
    );
    if (picked != null) onMonthChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final yearLabel = DateFormat('y年').format(month);
    final monthLabel = DateFormat('MM月').format(month);

    return Material(
      color: PigTokens.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          PigTokens.spaceLg,
          PigTokens.spaceXs,
          PigTokens.spaceLg,
          PigTokens.spaceMd,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            InkWell(
              onTap: () => _pickMonth(context),
              borderRadius: BorderRadius.circular(PigTokens.radiusCard),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: PigTokens.spaceXs,
                  vertical: PigTokens.spaceXs,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          yearLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            color: PigTokens.textTertiary,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              monthLabel,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: PigTokens.textPrimary,
                                height: 1.1,
                              ),
                            ),
                            const Icon(
                              Icons.arrow_drop_down,
                              color: PigTokens.textSecondary,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: 1,
              height: 36,
              margin: const EdgeInsets.symmetric(horizontal: PigTokens.spaceMd),
              color: PigTokens.surfaceInput,
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _Metric(label: '收入', value: income),
                  ),
                  Expanded(
                    child: _Metric(label: '支出', value: expense),
                  ),
                  Expanded(
                    child: _Metric(label: '结余', value: _balance),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final text = value < 0
        ? (value.abs() >= 100
            ? value.toStringAsFixed(0)
            : value.toStringAsFixed(2))
        : formatMoneyCompact(value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: PigTokens.textTertiary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: PigTokens.textPrimary,
          ),
        ),
      ],
    );
  }
}
