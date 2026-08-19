import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../ai/ai_provider_config.dart';
import '../../ai/bill_info.dart';
import '../../providers/ai_providers.dart';
import '../../providers/ledger_session_provider.dart';
import '../../services/system/logger_service.dart';
import '../../styles/tokens.dart';
import '../../widgets/ai/ai_setup_helpers.dart';
import '../../widgets/ai/bill_select_tile.dart';

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

class _Entry {
  _Entry(this.bill);

  final BillInfo bill;
  bool selected = true;
}

class _ImageBillingSheetState extends ConsumerState<_ImageBillingSheet> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<_Entry> _entries = const [];

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
    String? notReady;
    try {
      await ref
          .read(aiProviderStoreProvider)
          .resolve(AiCapabilityKind.vision);
    } on AiCapabilityNotReadyException catch (e) {
      notReady = e.message;
      logger.warning('ImageBilling', '能力未就绪: ${e.message}');
    }
    if (notReady != null) {
      setState(() {
        _loading = false;
        _error = notReady;
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
        _entries = [for (final b in bills) _Entry(b)];
        if (bills.isEmpty) {
          _error = '未识别到账单，请换一张支付截图';
          logger.warning('ImageBilling', '未识别到账单 source=${widget.source}');
        }
      });
    } catch (e, st) {
      logger.error('ImageBilling', '识别失败 source=${widget.source}', e, st);
      setState(() {
        _loading = false;
        _error = '识别失败：$e';
      });
    }
  }

  int get _selectedCount => _entries.where((e) => e.selected).length;

  void _selectAll() {
    setState(() {
      for (final e in _entries) {
        e.selected = true;
      }
    });
  }

  void _invertSelection() {
    setState(() {
      for (final e in _entries) {
        e.selected = !e.selected;
      }
    });
  }

  Future<void> _confirmSelected() async {
    final ledgerId = ref.read(currentLedgerIdProvider);
    if (ledgerId == null || _saving) return;
    final selected = [
      for (var i = 0; i < _entries.length; i++)
        if (_entries[i].selected) i,
    ];
    if (selected.isEmpty) return;

    setState(() => _saving = true);
    var saved = 0;
    String? failMsg;
    final remove = <int>{};

    for (final i in selected) {
      try {
        final ids = await ref.read(aiBookkeeperProvider).saveBills(
              bills: [_entries[i].bill],
              ledgerId: ledgerId,
              source: widget.source,
            );
        if (ids.isEmpty) {
          failMsg ??= '部分账单无法保存';
          continue;
        }
        saved++;
        remove.add(i);
      } catch (e, st) {
        logger.error('ImageBilling', '保存失败', e, st);
        failMsg = '$e';
        break;
      }
    }

    if (!mounted) return;
    setState(() {
      _saving = false;
      if (remove.isNotEmpty) {
        _entries = [
          for (var i = 0; i < _entries.length; i++)
            if (!remove.contains(i)) _entries[i],
        ];
      }
    });

    if (_entries.isEmpty) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已记账')),
      );
      return;
    }

    if (failMsg != null) {
      final text = saved > 0
          ? '已记账 $saved 条，其余失败：$failMsg'
          : '保存失败：$failMsg';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final selectedCount = _selectedCount;
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
              ?aiSetupTextButton(context, _error),
            ],
            if (_entries.isNotEmpty) ...[
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _entries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final e = _entries[i];
                    return BillSelectTile(
                      bill: e.bill,
                      selected: e.selected,
                      onChanged: _saving
                          ? null
                          : (v) {
                              setState(() => e.selected = v ?? false);
                            },
                    );
                  },
                ),
              ),
              const SizedBox(height: PigTokens.spaceSm),
              Row(
                children: [
                  TextButton(
                    onPressed: _saving ? null : _selectAll,
                    child: const Text('全选'),
                  ),
                  TextButton(
                    onPressed: _saving ? null : _invertSelection,
                    child: const Text('反选'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _saving || selectedCount == 0
                        ? null
                        : _confirmSelected,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text('确认记账（$selectedCount）'),
                  ),
                ],
              ),
            ],
            TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ],
      ),
    );
  }
}
