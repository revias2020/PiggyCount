import 'package:flutter/material.dart';

import '../../styles/tokens.dart';

/// 记一笔自定义数字键盘。
///
/// 支持小数点、退格，以及 `+` / `-` 拼接表达式（保存时由外部求值）。
/// 底部左侧「再记一笔」、右侧「保存」由回调区分。
class AmountKeypad extends StatelessWidget {
  const AmountKeypad({
    super.key,
    required this.onKey,
    required this.onBackspace,
    required this.onSave,
    required this.onSaveAndContinue,
  });

  /// 按下数字 / `.` / `+` / `-` 时回调原始字符。
  final ValueChanged<String> onKey;
  final VoidCallback onBackspace;
  final VoidCallback onSave;
  final VoidCallback onSaveAndContinue;

  static const _keyRadius = 10.0;
  /// 压矮后的键高（原 48）。
  static const _keyHeight = 42.0;
  static const _keyPad = 3.0;

  @override
  Widget build(BuildContext context) {
    Widget key(String label, {VoidCallback? onTap, Color? color}) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(_keyPad),
          child: Material(
            color: PigTokens.surfaceSecondary,
            borderRadius: BorderRadius.circular(_keyRadius),
            child: InkWell(
              borderRadius: BorderRadius.circular(_keyRadius),
              onTap: onTap ?? () => onKey(label),
              child: SizedBox(
                height: _keyHeight,
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: color ?? PigTokens.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget iconKey(IconData icon, VoidCallback onTap) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(_keyPad),
          child: Material(
            color: PigTokens.surfaceSecondary,
            borderRadius: BorderRadius.circular(_keyRadius),
            child: InkWell(
              borderRadius: BorderRadius.circular(_keyRadius),
              onTap: onTap,
              child: SizedBox(
                height: _keyHeight,
                child: Icon(icon, color: PigTokens.textPrimary),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(children: [
          key('1'),
          key('2'),
          key('3'),
          iconKey(Icons.backspace_outlined, onBackspace),
        ]),
        Row(children: [
          key('4'),
          key('5'),
          key('6'),
          key('-', color: PigTokens.primary),
        ]),
        Row(children: [
          key('7'),
          key('8'),
          key('9'),
          key('+', color: PigTokens.primary),
        ]),
        Row(
          children: [
            key('.'),
            key('0'),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(_keyPad),
                child: OutlinedButton(
                  onPressed: onSaveAndContinue,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: PigTokens.primary,
                    side: const BorderSide(color: PigTokens.primarySoft),
                    minimumSize: const Size.fromHeight(_keyHeight),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(_keyRadius),
                    ),
                  ),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '再记一笔',
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(_keyPad),
                child: FilledButton(
                  onPressed: onSave,
                  style: FilledButton.styleFrom(
                    backgroundColor: PigTokens.primary,
                    foregroundColor: PigTokens.textOnPrimary,
                    minimumSize: const Size.fromHeight(_keyHeight),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(_keyRadius),
                    ),
                  ),
                  child: const Text(
                    '保存',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
