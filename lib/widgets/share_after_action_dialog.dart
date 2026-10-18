import 'package:flutter/material.dart';

import '../services/automation/share_after_action.dart';
import '../styles/tokens.dart';

/// 运行时询问结果（不含 [ShareAfterAction.ask]）。
class ShareAfterPromptResult {
  const ShareAfterPromptResult({
    required this.action,
    required this.setAsDefault,
  });

  final ShareAfterAction action;
  final bool setAsDefault;
}

/// 分享入账后询问：留在本应用 / 返回上一应用。
Future<ShareAfterPromptResult?> showShareAfterActionAskDialog(
  BuildContext context,
) {
  return showDialog<ShareAfterPromptResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _ShareAfterAskDialog(),
  );
}

/// 「我的」里选择默认策略。
Future<ShareAfterAction?> showShareAfterActionSettingsDialog(
  BuildContext context, {
  required ShareAfterAction current,
}) {
  return showDialog<ShareAfterAction>(
    context: context,
    builder: (ctx) => _ShareAfterSettingsDialog(current: current),
  );
}

class _ShareAfterAskDialog extends StatefulWidget {
  const _ShareAfterAskDialog();

  @override
  State<_ShareAfterAskDialog> createState() => _ShareAfterAskDialogState();
}

class _ShareAfterAskDialogState extends State<_ShareAfterAskDialog> {
  var _setAsDefault = false;

  void _choose(ShareAfterAction action) {
    Navigator.of(context).pop(
      ShareAfterPromptResult(action: action, setAsDefault: _setAsDefault),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('分享入账'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('识别将在后台继续。接下来要去哪里？'),
          const SizedBox(height: PigTokens.spaceMd),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _setAsDefault,
            onChanged: (v) => setState(() => _setAsDefault = v ?? false),
            title: const Text('设为默认，不再询问'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => _choose(ShareAfterAction.stay),
          child: const Text('留在小猪记账'),
        ),
        TextButton(
          onPressed: () => _choose(ShareAfterAction.retreat),
          child: const Text('返回'),
        ),
      ],
    );
  }
}

class _ShareAfterSettingsDialog extends StatelessWidget {
  const _ShareAfterSettingsDialog({required this.current});

  final ShareAfterAction current;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('分享入账后'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final action in ShareAfterAction.values)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                action == current
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: action == current
                    ? PigTokens.primary
                    : PigTokens.textTertiary,
              ),
              title: Text(action.label),
              subtitle: Text(action.subtitle),
              onTap: () => Navigator.of(context).pop(action),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
