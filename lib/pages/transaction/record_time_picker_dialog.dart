import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../styles/tokens.dart';

/// 记一笔时间选择：居中 Dialog，双输入 + 小时/分钟快捷格（ADR-051）。
Future<TimeOfDay?> showRecordTimePicker(
  BuildContext context, {
  required TimeOfDay initialTime,
}) {
  return showDialog<TimeOfDay>(
    context: context,
    builder: (ctx) => _RecordTimePickerDialog(initialTime: initialTime),
  );
}

class _RecordTimePickerDialog extends StatefulWidget {
  const _RecordTimePickerDialog({required this.initialTime});

  final TimeOfDay initialTime;

  @override
  State<_RecordTimePickerDialog> createState() => _RecordTimePickerDialogState();
}

class _RecordTimePickerDialogState extends State<_RecordTimePickerDialog> {
  static final _hours = [
    for (var h = 0; h < 24; h++) h,
  ];
  static final _minutes = [
    for (var m = 0; m < 60; m += 5) m,
  ];

  late final TextEditingController _hourCtrl;
  late final TextEditingController _minuteCtrl;
  late final FocusNode _hourFocus;
  late final FocusNode _minuteFocus;
  String? _error;

  @override
  void initState() {
    super.initState();
    _hourCtrl = TextEditingController(
      text: _two(widget.initialTime.hour),
    );
    _minuteCtrl = TextEditingController(
      text: _two(widget.initialTime.minute),
    );
    _hourFocus = FocusNode()..addListener(_onFocusChange);
    _minuteFocus = FocusNode()..addListener(_onFocusChange);
    _hourCtrl.addListener(_onTextChanged);
    _minuteCtrl.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _hourFocus.removeListener(_onFocusChange);
    _minuteFocus.removeListener(_onFocusChange);
    _hourCtrl.removeListener(_onTextChanged);
    _minuteCtrl.removeListener(_onTextChanged);
    _hourFocus.dispose();
    _minuteFocus.dispose();
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    super.dispose();
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  void _onTextChanged() {
    if (_error != null) {
      setState(() => _error = null);
    } else {
      setState(() {});
    }
  }

  void _onFocusChange() {
    if (!_hourFocus.hasFocus) _padField(_hourCtrl);
    if (!_minuteFocus.hasFocus) _padField(_minuteCtrl);
    setState(() {});
  }

  void _padField(TextEditingController c) {
    final raw = c.text.trim();
    if (raw.isEmpty) return;
    final n = int.tryParse(raw);
    if (n == null) return;
    final padded = _two(n);
    if (c.text != padded) {
      c.value = TextEditingValue(
        text: padded,
        selection: TextSelection.collapsed(offset: padded.length),
      );
    }
  }

  int? get _parsedHour {
    final n = int.tryParse(_hourCtrl.text.trim());
    if (n == null || n < 0 || n > 23) return null;
    return n;
  }

  int? get _parsedMinute {
    final n = int.tryParse(_minuteCtrl.text.trim());
    if (n == null || n < 0 || n > 59) return null;
    return n;
  }

  void _setHour(int hour) {
    _hourCtrl.value = TextEditingValue(
      text: _two(hour),
      selection: TextSelection.collapsed(offset: 2),
    );
    _hourFocus.requestFocus();
  }

  void _setMinute(int minute) {
    _minuteCtrl.value = TextEditingValue(
      text: _two(minute),
      selection: TextSelection.collapsed(offset: 2),
    );
    _minuteFocus.requestFocus();
  }

  void _confirm() {
    final h = _parsedHour;
    final m = _parsedMinute;
    if (h == null || m == null) {
      setState(() {
        _error = '请输入合法时间（小时 0–23，分钟 0–59）';
      });
      return;
    }
    Navigator.pop(context, TimeOfDay(hour: h, minute: m));
  }

  @override
  Widget build(BuildContext context) {
    final hour = _parsedHour;
    final minute = _parsedMinute;

    return AlertDialog(
      backgroundColor: PigTokens.surface,
      title: const Text('选择时间'),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _DigitField(
                      controller: _hourCtrl,
                      focusNode: _hourFocus,
                      label: '时',
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: PigTokens.spaceSm),
                    child: Text(
                      ':',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        color: PigTokens.textPrimary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _DigitField(
                      controller: _minuteCtrl,
                      focusNode: _minuteFocus,
                      label: '分',
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: PigTokens.spaceSm),
                Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: PigTokens.danger,
                  ),
                ),
              ],
              const SizedBox(height: PigTokens.spaceLg),
              const Text(
                '小时',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: PigTokens.textSecondary,
                ),
              ),
              const SizedBox(height: PigTokens.spaceSm),
              _QuickGrid(
                values: _hours,
                selected: hour,
                crossAxisCount: 6,
                onSelect: _setHour,
              ),
              const SizedBox(height: PigTokens.spaceLg),
              const Text(
                '分钟',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: PigTokens.textSecondary,
                ),
              ),
              const SizedBox(height: PigTokens.spaceSm),
              _QuickGrid(
                values: _minutes,
                selected: minute,
                crossAxisCount: 6,
                onSelect: _setMinute,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _confirm,
          child: const Text('确定'),
        ),
      ],
    );
  }
}

class _DigitField extends StatelessWidget {
  const _DigitField({
    required this.controller,
    required this.focusNode,
    required this.label,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        color: PigTokens.textPrimary,
      ),
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(2),
      ],
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: PigTokens.surfaceInput,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PigTokens.radiusCard),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: PigTokens.spaceSm,
          vertical: PigTokens.spaceMd,
        ),
      ),
    );
  }
}

class _QuickGrid extends StatelessWidget {
  const _QuickGrid({
    required this.values,
    required this.selected,
    required this.crossAxisCount,
    required this.onSelect,
  });

  final List<int> values;
  final int? selected;
  final int crossAxisCount;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: values.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: PigTokens.spaceSm,
        crossAxisSpacing: PigTokens.spaceSm,
        childAspectRatio: 1.4,
      ),
      itemBuilder: (context, i) {
        final v = values[i];
        final isOn = selected == v;
        final label = v.toString().padLeft(2, '0');
        return Material(
          color: isOn ? PigTokens.primarySoft : PigTokens.surfaceSecondary,
          borderRadius: BorderRadius.circular(PigTokens.radiusCard),
          child: InkWell(
            onTap: () => onSelect(v),
            borderRadius: BorderRadius.circular(PigTokens.radiusCard),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isOn ? FontWeight.w600 : FontWeight.w500,
                  color: isOn ? PigTokens.primary : PigTokens.textPrimary,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
