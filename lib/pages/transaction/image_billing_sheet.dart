import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../ai/ai_provider_config.dart';
import '../../ai/ai_vision_failure.dart';
import '../../ai/bill_info.dart';
import '../../providers/ai_providers.dart';
import '../../providers/ledger_session_provider.dart';
import '../../services/automation/billing_image_limits.dart';
import '../../services/system/logger_service.dart';
import '../../styles/tokens.dart';
import '../../widgets/ai/ai_setup_helpers.dart';
import '../../widgets/ai/bill_select_tile.dart';

/// 单张待识别图（前台多图确认流，ADR-058）。
class BillingImage {
  const BillingImage({
    required this.bytes,
    this.mimeType = 'image/jpeg',
  });

  final Uint8List bytes;
  final String mimeType;
}

/// 图片入账确认流（相册多选 / 拍照 / 单张共用）。
Future<void> showImageBillingSheet(
  BuildContext context, {
  required List<BillingImage> images,
  String source = 'share',
}) {
  if (images.isEmpty) return Future.value();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: PigTokens.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _ImageBillingSheet(
      images: images,
      source: source,
    ),
  );
}

String _mimeOf(XFile file) {
  final mime = file.mimeType;
  if (mime != null && mime.isNotEmpty) return mime;
  return file.path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
}

/// 从相册多选并走识别确认（ADR-058）。
Future<void> pickImageForBilling(
  BuildContext context, {
  String source = 'share',
}) async {
  final picker = ImagePicker();
  final files = await picker.pickMultiImage(limit: kMaxBillingImages);
  if (files.isEmpty || !context.mounted) return;

  var selected = files;
  var truncated = false;
  if (selected.length > kMaxBillingImages) {
    selected = selected.take(kMaxBillingImages).toList();
    truncated = true;
  }
  if (truncated && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('最多 9 张，$kBillingImagesTruncatedHint')),
    );
  }

  final images = <BillingImage>[];
  for (final file in selected) {
    images.add(
      BillingImage(
        bytes: await file.readAsBytes(),
        mimeType: _mimeOf(file),
      ),
    );
  }
  if (!context.mounted || images.isEmpty) return;
  await showImageBillingSheet(
    context,
    images: images,
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
  if (!context.mounted) return;
  await showImageBillingSheet(
    context,
    images: [BillingImage(bytes: bytes, mimeType: file.mimeType ?? 'image/jpeg')],
    source: source,
  );
}

class _ImageBillingSheet extends ConsumerStatefulWidget {
  const _ImageBillingSheet({
    required this.images,
    required this.source,
  });

  final List<BillingImage> images;
  final String source;

  @override
  ConsumerState<_ImageBillingSheet> createState() => _ImageBillingSheetState();
}

class _Entry {
  _Entry(this.bill);

  final BillInfo bill;
  bool selected = true;
}

class _ImageGroup {
  _ImageGroup({
    required this.bytes,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String mimeType;
  List<_Entry> entries = [];
  String? error;
  bool retrying = false;
}

class _ImageBillingSheetState extends ConsumerState<_ImageBillingSheet> {
  bool _loading = true;
  bool _cancelling = false;
  bool _cancelled = false;
  bool _saving = false;
  String? _statusMessage;
  String? _setupError;
  List<_ImageGroup> _groups = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runAll());
  }

  Future<void> _runAll() async {
    String? notReady;
    try {
      final providers = await ref
          .read(aiProviderStoreProvider)
          .listVisionFallbackProviders();
      if (providers.isEmpty) {
        notReady = '未绑定已测通的视觉服务商，请到「我的 → AI 设置」配置';
      }
    } on AiCapabilityNotReadyException catch (e) {
      notReady = e.message;
      logger.warning('ImageBilling', '能力未就绪: ${e.message}');
    }
    if (notReady != null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _setupError = notReady;
      });
      return;
    }

    final completed = <_ImageGroup>[];
    final total = widget.images.length;
    for (var i = 0; i < total; i++) {
      if (_cancelled) break;
      if (!mounted) return;
      setState(() {
        _statusMessage = total == 1
            ? '正在识别账单…'
            : '正在识别第 ${i + 1}/$total 张…';
      });
      final img = widget.images[i];
      final group = _ImageGroup(bytes: img.bytes, mimeType: img.mimeType);
      await _recognizeGroup(group);
      if (_cancelled) {
        // 丢弃 inflight（ADR-058）
        break;
      }
      completed.add(group);
    }

    if (!mounted) return;
    if (_cancelled && completed.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _loading = false;
      _cancelling = false;
      _statusMessage = null;
      _groups = completed;
    });
  }

  Future<void> _recognizeGroup(_ImageGroup group) async {
    try {
      final bills = await ref.read(aiBookkeeperProvider).fromImage(
            group.bytes,
            mimeType: group.mimeType,
            onSwitch: (event) {
              if (!mounted || _cancelled) return;
              setState(() => _statusMessage = event.userHint);
            },
          );
      group.entries = [for (final b in bills) _Entry(b)];
      group.error = bills.isEmpty ? '未识别到账单，请换一张支付截图' : null;
      if (bills.isEmpty) {
        logger.warning('ImageBilling', '未识别到账单 source=${widget.source}');
      }
    } on AiVisionExhaustedException catch (e, st) {
      logger.error('ImageBilling', '识别失败 source=${widget.source}', e, st);
      group.entries = [];
      group.error = '识别失败：${e.message}（已尝试 ${e.providersAttempted} 个服务商）';
    } catch (e, st) {
      logger.error('ImageBilling', '识别失败 source=${widget.source}', e, st);
      group.entries = [];
      group.error = '识别失败：$e';
    }
  }

  void _requestCancel() {
    if (!_loading || _cancelled) return;
    setState(() {
      _cancelled = true;
      _cancelling = true;
      _statusMessage = '正在取消…';
    });
  }

  Future<void> _retryGroup(_ImageGroup group) async {
    if (_saving || group.retrying) return;
    setState(() {
      group.retrying = true;
      group.error = null;
      group.entries = [];
    });
    await _recognizeGroup(group);
    if (!mounted) return;
    setState(() => group.retrying = false);
  }

  int get _selectedCount {
    var n = 0;
    for (final g in _groups) {
      for (final e in g.entries) {
        if (e.selected) n++;
      }
    }
    return n;
  }

  void _selectAll() {
    setState(() {
      for (final g in _groups) {
        for (final e in g.entries) {
          e.selected = true;
        }
      }
    });
  }

  void _invertSelection() {
    setState(() {
      for (final g in _groups) {
        for (final e in g.entries) {
          e.selected = !e.selected;
        }
      }
    });
  }

  Future<void> _confirmSelected() async {
    final ledgerId = ref.read(currentLedgerIdProvider);
    if (ledgerId == null || _saving) return;
    final selected = <({_ImageGroup group, int index})>[];
    for (final g in _groups) {
      for (var i = 0; i < g.entries.length; i++) {
        if (g.entries[i].selected) {
          selected.add((group: g, index: i));
        }
      }
    }
    if (selected.isEmpty) return;

    setState(() => _saving = true);
    var saved = 0;
    String? failMsg;
    final remove = <(_ImageGroup, int)>{};

    for (final item in selected) {
      try {
        final result = await ref.read(aiBookkeeperProvider).saveBills(
              bills: [item.group.entries[item.index].bill],
              ledgerId: ledgerId,
              source: widget.source,
            );
        if (result.ids.isEmpty) {
          failMsg ??= result.skipped > 0
              ? '已存在相同账本、金额与时间的账单'
              : '部分账单无法保存';
          continue;
        }
        saved++;
        remove.add((item.group, item.index));
      } catch (e, st) {
        logger.error('ImageBilling', '保存失败', e, st);
        failMsg = '$e';
        break;
      }
    }

    if (!mounted) return;
    setState(() {
      _saving = false;
      for (final g in _groups) {
        final drop = {
          for (final r in remove)
            if (identical(r.$1, g)) r.$2,
        };
        if (drop.isEmpty) continue;
        g.entries = [
          for (var i = 0; i < g.entries.length; i++)
            if (!drop.contains(i)) g.entries[i],
        ];
      }
      // 已无候选且无错误的组可收掉
      _groups = [
        for (final g in _groups)
          if (g.entries.isNotEmpty || g.error != null) g,
      ];
    });

    final remainingBills =
        _groups.fold<int>(0, (n, g) => n + g.entries.length);
    if (remainingBills == 0 &&
        _groups.every((g) => g.error == null)) {
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

  void _showOriginal(Uint8List bytes) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black87,
        pageBuilder: (ctx, animation, secondaryAnimation) {
          return GestureDetector(
            onTap: () => Navigator.pop(ctx),
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: SafeArea(
                child: Center(
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final selectedCount = _selectedCount;
    return PopScope(
      canPop: !_loading && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _loading) _requestCancel();
      },
      child: Padding(
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
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    if (_statusMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _statusMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          color: PigTokens.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _cancelling ? null : _requestCancel,
                      child: Text(_cancelling ? '正在取消…' : '取消'),
                    ),
                  ],
                ),
              )
            else ...[
              if (_setupError != null) ...[
                Text(
                  _setupError!,
                  style: const TextStyle(color: PigTokens.danger),
                ),
                ?aiSetupTextButton(context, _setupError),
              ],
              if (_groups.isNotEmpty) ...[
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _groups.length,
                    itemBuilder: (context, gi) {
                      final g = _groups[gi];
                      return _buildGroup(gi, g);
                    },
                  ),
                ),
                if (_selectedCount > 0 ||
                    _groups.any((g) => g.entries.isNotEmpty)) ...[
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
              ],
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGroup(int index, _ImageGroup g) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => _showOriginal(g.bytes),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    g.bytes,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '第 ${index + 1} 张',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (g.retrying)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (g.error != null)
                TextButton(
                  onPressed: _saving ? null : () => _retryGroup(g),
                  child: const Text('重试'),
                ),
            ],
          ),
          if (g.error != null) ...[
            const SizedBox(height: 6),
            Text(
              g.error!,
              style: const TextStyle(
                color: PigTokens.danger,
                fontSize: 13,
                height: 1.3,
              ),
            ),
            ?aiSetupTextButton(context, g.error),
          ],
          for (final e in g.entries)
            BillSelectTile(
              bill: e.bill,
              selected: e.selected,
              onChanged: _saving || g.retrying
                  ? null
                  : (v) {
                      setState(() => e.selected = v ?? false);
                    },
            ),
          if (index < _groups.length - 1)
            const Divider(height: 20),
        ],
      ),
    );
  }
}
