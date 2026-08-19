import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../styles/tokens.dart';
import '../../utils/report_period.dart';

/// 报表「选择月」：年导航 + 3×4 月网格，点月即返回该月 1 号（ADR-016）。
Future<DateTime?> showReportMonthPicker(
  BuildContext context, {
  required DateTime initialMonth,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: PigTokens.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(PigTokens.radiusSheet),
      ),
    ),
    builder: (_) => _ReportMonthPickerSheet(initialMonth: initialMonth),
  );
}

/// 报表「选择年」：可翻页年份网格，点年即返回该年 1 月 1 日。
Future<DateTime?> showReportYearPicker(
  BuildContext context, {
  required DateTime initialYear,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: PigTokens.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(PigTokens.radiusSheet),
      ),
    ),
    builder: (_) => _ReportYearPickerSheet(initialYear: initialYear),
  );
}

/// 报表「选择周」：先选月，再列该月各周；返回该周内任一天（通常周一）。
Future<DateTime?> showReportWeekPicker(
  BuildContext context, {
  required DateTime initialAnchor,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: PigTokens.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(PigTokens.radiusSheet),
      ),
    ),
    builder: (_) => _ReportWeekPickerSheet(initialAnchor: initialAnchor),
  );
}

/// 与某自然月有交集的 ISO 周（周一起点）。
List<ReportPeriod> weeksOverlappingMonth(int year, int month) {
  final first = DateTime(year, month, 1);
  final nextMonth = DateTime(year, month + 1);
  var monday = first.subtract(Duration(days: first.weekday - 1));
  final weeks = <ReportPeriod>[];
  while (monday.isBefore(nextMonth)) {
    final period = ReportPeriod.fromScope(ReportScope.week, monday);
    if (period.end.isAfter(first) && period.start.isBefore(nextMonth)) {
      weeks.add(period);
    }
    monday = monday.add(const Duration(days: 7));
  }
  return weeks;
}

class _SheetChrome extends StatelessWidget {
  const _SheetChrome({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: PigTokens.spaceLg,
        right: PigTokens.spaceLg,
        top: PigTokens.spaceMd,
        bottom: MediaQuery.paddingOf(context).bottom + PigTokens.spaceLg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: PigTokens.textPrimary,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 22),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: PigTokens.spaceMd),
          child,
        ],
      ),
    );
  }
}

class _YearNavRow extends StatelessWidget {
  const _YearNavRow({
    required this.year,
    required this.onPrev,
    required this.onNext,
  });

  final int year;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _RoundChevron(icon: Icons.chevron_left, onTap: onPrev),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: PigTokens.spaceLg),
          child: Text(
            '$year年',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: PigTokens.textPrimary,
            ),
          ),
        ),
        _RoundChevron(icon: Icons.chevron_right, onTap: onNext),
      ],
    );
  }
}

class _RoundChevron extends StatelessWidget {
  const _RoundChevron({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PigTokens.surfaceSecondary,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 22, color: PigTokens.textSecondary),
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.selectedMonth,
    required this.onPick,
  });

  final int? selectedMonth;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 12,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: PigTokens.spaceSm,
        crossAxisSpacing: PigTokens.spaceSm,
        childAspectRatio: 2.2,
      ),
      itemBuilder: (context, index) {
        final m = index + 1;
        final selected = selectedMonth == m;
        return Material(
          color: selected ? PigTokens.primarySoft : Colors.transparent,
          borderRadius: BorderRadius.circular(PigTokens.radiusPill),
          child: InkWell(
            borderRadius: BorderRadius.circular(PigTokens.radiusPill),
            onTap: () => onPick(m),
            child: Center(
              child: Text(
                '$m月',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? PigTokens.primary : PigTokens.textPrimary,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ReportMonthPickerSheet extends StatefulWidget {
  const _ReportMonthPickerSheet({required this.initialMonth});

  final DateTime initialMonth;

  @override
  State<_ReportMonthPickerSheet> createState() =>
      _ReportMonthPickerSheetState();
}

class _ReportMonthPickerSheetState extends State<_ReportMonthPickerSheet> {
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    _year = widget.initialMonth.year;
    _month = widget.initialMonth.month;
  }

  @override
  Widget build(BuildContext context) {
    return _SheetChrome(
      title: '选择月',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _YearNavRow(
            year: _year,
            onPrev: () => setState(() => _year--),
            onNext: () => setState(() => _year++),
          ),
          const SizedBox(height: PigTokens.spaceLg),
          _MonthGrid(
            selectedMonth: _month,
            onPick: (m) => Navigator.pop(context, DateTime(_year, m)),
          ),
        ],
      ),
    );
  }
}

class _ReportYearPickerSheet extends StatefulWidget {
  const _ReportYearPickerSheet({required this.initialYear});

  final DateTime initialYear;

  @override
  State<_ReportYearPickerSheet> createState() => _ReportYearPickerSheetState();
}

class _ReportYearPickerSheetState extends State<_ReportYearPickerSheet> {
  static const _pageSize = 12;
  late int _pageStart;
  late int _selectedYear;

  @override
  void initState() {
    super.initState();
    _selectedYear = widget.initialYear.year;
    // 让当前年落在页内偏后位置，便于看前后年。
    _pageStart = _selectedYear - (_selectedYear % _pageSize);
  }

  @override
  Widget build(BuildContext context) {
    final years = [for (var i = 0; i < _pageSize; i++) _pageStart + i];
    return _SheetChrome(
      title: '选择年',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _RoundChevron(
                icon: Icons.chevron_left,
                onTap: () => setState(() => _pageStart -= _pageSize),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: PigTokens.spaceLg,
                ),
                child: Text(
                  '${years.first}–${years.last}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: PigTokens.textPrimary,
                  ),
                ),
              ),
              _RoundChevron(
                icon: Icons.chevron_right,
                onTap: () => setState(() => _pageStart += _pageSize),
              ),
            ],
          ),
          const SizedBox(height: PigTokens.spaceLg),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: years.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: PigTokens.spaceSm,
              crossAxisSpacing: PigTokens.spaceSm,
              childAspectRatio: 2.2,
            ),
            itemBuilder: (context, index) {
              final y = years[index];
              final selected = y == _selectedYear;
              return Material(
                color: selected ? PigTokens.primarySoft : Colors.transparent,
                borderRadius: BorderRadius.circular(PigTokens.radiusPill),
                child: InkWell(
                  borderRadius: BorderRadius.circular(PigTokens.radiusPill),
                  onTap: () => Navigator.pop(context, DateTime(y)),
                  child: Center(
                    child: Text(
                      '$y',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected
                            ? PigTokens.primary
                            : PigTokens.textPrimary,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ReportWeekPickerSheet extends StatefulWidget {
  const _ReportWeekPickerSheet({required this.initialAnchor});

  final DateTime initialAnchor;

  @override
  State<_ReportWeekPickerSheet> createState() => _ReportWeekPickerSheetState();
}

class _ReportWeekPickerSheetState extends State<_ReportWeekPickerSheet> {
  late int _year;
  late int _month;
  /// false = 选月；true = 选周。
  bool _pickingWeek = false;

  @override
  void initState() {
    super.initState();
    _year = widget.initialAnchor.year;
    _month = widget.initialAnchor.month;
  }

  @override
  Widget build(BuildContext context) {
    if (!_pickingWeek) {
      return _SheetChrome(
        title: '选择周',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _YearNavRow(
              year: _year,
              onPrev: () => setState(() => _year--),
              onNext: () => setState(() => _year++),
            ),
            const SizedBox(height: PigTokens.spaceLg),
            _MonthGrid(
              selectedMonth: _month,
              onPick: (m) => setState(() {
                _month = m;
                _pickingWeek = true;
              }),
            ),
          ],
        ),
      );
    }

    final weeks = weeksOverlappingMonth(_year, _month);
    final current = ReportPeriod.fromScope(
      ReportScope.week,
      widget.initialAnchor,
    );
    final fmt = DateFormat('M/d');

    return _SheetChrome(
      title: '选择周',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _pickingWeek = false),
                icon: const Icon(Icons.chevron_left, size: 20),
                label: Text('$_year年$_month月'),
              ),
            ],
          ),
          const SizedBox(height: PigTokens.spaceSm),
          for (final w in weeks)
            Builder(
              builder: (context) {
                final endInclusive = w.end.subtract(const Duration(days: 1));
                final selected = w.start == current.start;
                final label =
                    '${fmt.format(w.start)}–${fmt.format(endInclusive)}';
                return Padding(
                  padding: const EdgeInsets.only(bottom: PigTokens.spaceSm),
                  child: Material(
                    color: selected
                        ? PigTokens.primarySoft
                        : PigTokens.surfaceSecondary,
                    borderRadius:
                        BorderRadius.circular(PigTokens.radiusCard),
                    child: InkWell(
                      borderRadius:
                          BorderRadius.circular(PigTokens.radiusCard),
                      onTap: () => Navigator.pop(context, w.anchor),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: PigTokens.spaceMd,
                          vertical: PigTokens.spaceMd,
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w500,
                            color: selected
                                ? PigTokens.primary
                                : PigTokens.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
