import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/bill_info.dart';
import '../../providers/ai_providers.dart';
import '../../providers/ledger_session_provider.dart';
import '../../styles/tokens.dart';
import '../../widgets/ai/bill_confirm_card.dart';
import 'ai_settings_page.dart';

/// AI 账单助手（fig5）：空态 + 快捷 Chip + 对话/确认记账 + 语音输入。
class AiChatPage extends ConsumerStatefulWidget {
  const AiChatPage({super.key});

  @override
  ConsumerState<AiChatPage> createState() => _AiChatPageState();
}

class _ChatItem {
  _ChatItem.text({required this.isUser, required this.text})
      : bills = null,
        id = UniqueKey();

  _ChatItem.bills(this.bills)
      : isUser = false,
        text = null,
        id = UniqueKey();

  final Key id;
  final bool isUser;
  final String? text;
  final List<BillInfo>? bills;
}

class _AiChatPageState extends ConsumerState<AiChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_ChatItem>[];
  bool _sending = false;
  bool _listening = false;
  final _confirming = <Key>{};

  static const _primaryChips = [
    ('今日建议', Icons.lightbulb_outline, true),
    ('周账单分析', Icons.confirmation_number_outlined, true),
    ('月账单分析', Icons.calendar_month_outlined, true),
  ];

  static const _secondaryChips = [
    '花费与结余分析',
    '近期大额支出',
    '省钱建议',
    '异常支出检测',
    '年度回顾',
    '月最大支出类别',
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(
    String raw, {
    bool forceAnalysis = false,
  }) async {
    final text = raw.trim();
    if (text.isEmpty || _sending) return;

    final cfg = await ref.read(aiConfigStoreProvider).load();
    if (!cfg.isConfigured) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先配置 AI API Key'),
          action: SnackBarAction(
            label: '去配置',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AiSettingsPage()),
              );
            },
          ),
        ),
      );
      return;
    }

    final ledgerId = ref.read(currentLedgerIdProvider);
    if (ledgerId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择账本')),
      );
      return;
    }

    setState(() {
      _sending = true;
      _messages.add(_ChatItem.text(isUser: true, text: text));
      _input.clear();
    });
    _scrollToEnd();

    final reply = await ref.read(aiChatServiceProvider).processMessage(
          text,
          ledgerId: ledgerId,
          forceAnalysis: forceAnalysis,
        );

    if (!mounted) return;
    setState(() {
      _sending = false;
      if (reply.isBills) {
        _messages.add(_ChatItem.bills(reply.pendingBills));
      } else {
        _messages.add(_ChatItem.text(isUser: false, text: reply.text ?? ''));
      }
    });
    _scrollToEnd();
  }

  Future<void> _confirmBill(_ChatItem item, BillInfo bill) async {
    final ledgerId = ref.read(currentLedgerIdProvider);
    if (ledgerId == null) return;
    setState(() => _confirming.add(item.id));
    try {
      final ids = await ref.read(aiBookkeeperProvider).saveBills(
            bills: [bill],
            ledgerId: ledgerId,
            source: 'ai_chat',
          );
      if (!mounted) return;
      setState(() {
        _confirming.remove(item.id);
        _messages.removeWhere((m) => m.id == item.id);
        _messages.add(
          _ChatItem.text(
            isUser: false,
            text: ids.isEmpty ? '保存失败，请重试' : '已记账 ${ids.length} 笔',
          ),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _confirming.remove(item.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
      );
    }
  }

  Future<void> _toggleVoice() async {
    final asr = ref.read(speechAsrServiceProvider);
    if (_listening) {
      final text = await asr.stop();
      setState(() => _listening = false);
      if (text.trim().isNotEmpty) {
        _input.text = text.trim();
        await _send(text);
      }
      return;
    }
    try {
      setState(() => _listening = true);
      await asr.start(
        onPartial: (t) {
          if (!mounted) return;
          setState(() => _input.text = t);
        },
      );
    } catch (e) {
      setState(() => _listening = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final empty = _messages.isEmpty;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              PigTokens.aiCanvasTop,
              PigTokens.aiCanvasMid,
              PigTokens.scaffoldBackground,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _Header(
                onBack: () => Navigator.of(context).pop(),
                onSettings: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AiSettingsPage(),
                    ),
                  );
                },
              ),
              Expanded(
                child: empty
                    ? _EmptyBody(
                        onPrimaryChip: (label) =>
                            _send(label, forceAnalysis: true),
                        onSecondaryChip: (label) =>
                            _send(label, forceAnalysis: true),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(
                          PigTokens.spaceLg,
                          PigTokens.spaceSm,
                          PigTokens.spaceLg,
                          PigTokens.spaceLg,
                        ),
                        itemCount: _messages.length + (_sending ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (_sending && i == _messages.length) {
                            return const _ThinkingBubble();
                          }
                          final m = _messages[i];
                          if (m.bills != null) {
                            return Column(
                              children: [
                                for (final b in m.bills!)
                                  BillConfirmCard(
                                    bill: b,
                                    busy: _confirming.contains(m.id),
                                    onConfirm: () => _confirmBill(m, b),
                                    onDiscard: () {
                                      setState(() {
                                        _messages.removeWhere(
                                          (x) => x.id == m.id,
                                        );
                                      });
                                    },
                                  ),
                              ],
                            );
                          }
                          return _Bubble(isUser: m.isUser, text: m.text ?? '');
                        },
                      ),
              ),
              _InputBar(
                controller: _input,
                listening: _listening,
                sending: _sending,
                onSend: () => _send(_input.text),
                onMic: _toggleVoice,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack, required this.onSettings});

  final VoidCallback onBack;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: PigTokens.spaceXs,
        vertical: PigTokens.spaceXs,
      ),
      child: Row(
        children: [
          IconButton(onPressed: onBack, icon: const Icon(Icons.chevron_left)),
          const Expanded(
            child: Text(
              'AI 账单助手',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            onPressed: onSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody({
    required this.onPrimaryChip,
    required this.onSecondaryChip,
  });

  final ValueChanged<String> onPrimaryChip;
  final ValueChanged<String> onSecondaryChip;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        PigTokens.spaceXl,
        PigTokens.spaceMd,
        PigTokens.spaceXl,
        PigTokens.spaceXl,
      ),
      children: [
        const SizedBox(height: PigTokens.spaceXl),
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [PigTokens.aiGradientStart, PigTokens.aiGradientEnd],
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0x336B5CFF),
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              Icons.smart_toy_outlined,
              color: PigTokens.textOnPrimary,
              size: 36,
            ),
          ),
        ),
        const SizedBox(height: PigTokens.spaceLg),
        const Text(
          '嗨！我是你的AI账单助手',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: PigTokens.spaceSm),
        const Text(
          '我能帮你分析账单、提供消费建议。也可以直接说「午餐花了 35」来记账。',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            color: PigTokens.textSecondary,
          ),
        ),
        const SizedBox(height: PigTokens.spaceXl + 4),
        Wrap(
          spacing: PigTokens.spaceSm,
          runSpacing: PigTokens.spaceSm,
          alignment: WrapAlignment.center,
          children: [
            for (final c in _AiChatPageState._primaryChips)
              OutlinedButton.icon(
                onPressed: () => onPrimaryChip(c.$1),
                icon: Icon(c.$2, size: 18),
                label: Text(c.$1),
                style: OutlinedButton.styleFrom(
                  foregroundColor: PigTokens.primary,
                  side: const BorderSide(color: PigTokens.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(PigTokens.radiusCard),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: PigTokens.spaceMd),
        Wrap(
          spacing: PigTokens.spaceSm,
          runSpacing: PigTokens.spaceSm,
          alignment: WrapAlignment.center,
          children: [
            for (final label in _AiChatPageState._secondaryChips)
              ActionChip(
                avatar: const Icon(
                  Icons.tag,
                  size: 16,
                  color: PigTokens.aiGradientStart,
                ),
                label: Text(label),
                backgroundColor: PigTokens.aiChipSoft,
                side: BorderSide.none,
                onPressed: () => onSecondaryChip(label),
              ),
          ],
        ),
      ],
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: PigTokens.spaceSm),
        padding: const EdgeInsets.symmetric(
          horizontal: PigTokens.spaceLg,
          vertical: PigTokens.spaceMd,
        ),
        decoration: BoxDecoration(
          color: PigTokens.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: PigTokens.spaceSm),
            Text(
              '思考中…',
              style: TextStyle(color: PigTokens.textTertiary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.isUser, required this.text});

  final bool isUser;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: PigTokens.spaceSm),
        padding: const EdgeInsets.symmetric(
          horizontal: PigTokens.spaceLg - 2,
          vertical: 10,
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isUser ? PigTokens.primary : PigTokens.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isUser ? PigTokens.textOnPrimary : PigTokens.textPrimary,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.listening,
    required this.sending,
    required this.onSend,
    required this.onMic,
  });

  final TextEditingController controller;
  final bool listening;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onMic;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          PigTokens.spaceMd,
          PigTokens.spaceSm,
          PigTokens.spaceMd,
          PigTokens.spaceMd,
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: sending ? null : onMic,
              icon: Icon(
                listening ? Icons.stop_circle_outlined : Icons.mic_none,
                color: listening ? PigTokens.danger : PigTokens.primary,
              ),
            ),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(
                  horizontal: PigTokens.spaceLg - 2,
                ),
                decoration: BoxDecoration(
                  color: PigTokens.surface,
                  borderRadius: BorderRadius.circular(PigTokens.radiusPill),
                  border: Border.all(
                    color: listening
                        ? PigTokens.primary.withValues(alpha: 0.35)
                        : Colors.transparent,
                  ),
                ),
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  decoration: InputDecoration(
                    hintText: listening ? '正在听…' : '输入你想了解的，或直接记账~',
                    border: InputBorder.none,
                    hintStyle: const TextStyle(color: PigTokens.textTertiary),
                  ),
                ),
              ),
            ),
            const SizedBox(width: PigTokens.spaceSm),
            Opacity(
              opacity: sending ? 0.5 : 1,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: sending ? null : onSend,
                  child: Ink(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          PigTokens.aiGradientStart,
                          PigTokens.aiGradientEnd,
                        ],
                      ),
                    ),
                    child: const Icon(
                      Icons.send_rounded,
                      color: PigTokens.textOnPrimary,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
