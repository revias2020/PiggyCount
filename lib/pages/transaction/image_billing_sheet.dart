import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../ai/bill_info.dart';
import '../../providers/ai_providers.dart';
import '../../providers/ledger_session_provider.dart';
import '../../styles/tokens.dart';
import '../../widgets/ai/bill_confirm_card.dart';
import '../ai/ai_settings_page.dart';

/// 图片入账确认流（相册选择 / 分享 / 截图识别共用）。
Future<void> showImageBillingSheet(
  BuildContext context, {
  Uint8List? imageBytes,
  String mimeType = 'image/jpeg',
  String source = 'share',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: PigTokens.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _ImageBillingSheet(
      initialBytes: imageBytes,
      mimeType: mimeType,
      source: source,
    ),
  );
}

/// 从相册选图并走识别确认。
Future<void> pickImageForBilling(BuildContext context, {String source = 'share'}) async {
  final picker = ImagePicker();
  final file = await picker.pickImage(source: ImageSource.gallery);
  if (file == null || !context.mounted) return;
  final bytes = await file.readAsBytes();
  final mime = file.mimeType ??
      (file.path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
  if (!context.mounted) return;
  await showImageBillingSheet(
    context,
    imageBytes: bytes,
    mimeType: mime,
    source: source,
  );
}

/// 拍照并走识别确认。
Future<void> takePhotoForBilling(
  BuildContext context, {
  String source = 'camera',
}) async {
  final picker = ImagePicker();
  final file = await picker.pickImage(source: ImageSource.camera);
  if (file == null || !context.mounted) return;
  final bytes = await file.readAsBytes();
  final mime = file.mimeType ?? 'image/jpeg';
  if (!context.mounted) return;
  await showImageBillingSheet(
    context,
    imageBytes: bytes,
    mimeType: mime,
    source: source,
  );
}

class _ImageBillingSheet extends ConsumerStatefulWidget {
  const _ImageBillingSheet({
    this.initialBytes,
    required this.mimeType,
    required this.source,
  });

  final Uint8List? initialBytes;
  final String mimeType;
  final String source;

  @override
  ConsumerState<_ImageBillingSheet> createState() => _ImageBillingSheetState();
}

class _ImageBillingSheetState extends ConsumerState<_ImageBillingSheet> {
  bool _loading = true;
  String? _error;
  List<BillInfo> _bills = const [];
  final _saving = <int>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final bytes = widget.initialBytes;
    if (bytes == null) {
      setState(() {
        _loading = false;
        _error = '没有图片数据';
      });
      return;
    }
    final cfg = await ref.read(aiConfigStoreProvider).load();
    if (!cfg.isConfigured) {
      setState(() {
        _loading = false;
        _error = '请先配置 AI API Key（需视觉模型）';
      });
      return;
    }
    try {
      final bills = await ref.read(aiBookkeeperProvider).fromImage(
            bytes,
            mimeType: widget.mimeType,
          );
      setState(() {
        _loading = false;
        _bills = bills;
        if (bills.isEmpty) {
          _error = '未识别到账单，请换一张支付截图';
        }
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '识别失败：$e';
      });
    }
  }

  Future<void> _confirm(BillInfo bill, int index) async {
    final ledgerId = ref.read(currentLedgerIdProvider);
    if (ledgerId == null) return;
    setState(() => _saving.add(index));
    try {
      await ref.read(aiBookkeeperProvider).saveBills(
            bills: [bill],
            ledgerId: ledgerId,
            source: widget.source,
          );
      if (!mounted) return;
      setState(() {
        _saving.remove(index);
        _bills = [..._bills]..removeAt(index);
      });
      if (_bills.isEmpty && mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已记账')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving.remove(index));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: PigTokens.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '图片识别记账',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: PigTokens.danger)),
              if (_error!.contains('API Key'))
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AiSettingsPage(),
                      ),
                    );
                  },
                  child: const Text('去配置'),
                ),
            ],
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.55,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (var i = 0; i < _bills.length; i++)
                    BillConfirmCard(
                      bill: _bills[i],
                      busy: _saving.contains(i),
                      onConfirm: () => _confirm(_bills[i], i),
                      onDiscard: () {
                        setState(() {
                          _bills = [..._bills]..removeAt(i);
                        });
                      },
                    ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ],
      ),
    );
  }
}
