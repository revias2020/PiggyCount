import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../styles/tokens.dart';

/// 记一笔扇形菜单动作。
enum RecordFabAction { camera, voice, gallery }

/// 明细页右下角「记一笔」扩展 FAB + Speed Dial。
///
/// - 单击：[onPressed] → 打开记一笔
/// - 长按：主钮收成小圆锚点；左上真扇形弹出拍照 / 语音 / 图片（含遮罩与短文案）
/// - **按住拖到目标松手**执行，未选中则取消
class RecordFab extends StatefulWidget {
  const RecordFab({
    super.key,
    required this.onPressed,
    required this.onAction,
  });

  final VoidCallback onPressed;
  final ValueChanged<RecordFabAction> onAction;

  @override
  State<RecordFab> createState() => _RecordFabState();
}

class _RecordFabState extends State<RecordFab>
    with SingleTickerProviderStateMixin {
  static const double _hubSize = 56;
  static const double _dialSize = 52;
  static const double _labelGap = 4;
  static const double _labelHeight = 16;
  /// 命中半径（含文案区略放大）
  static const double _hitSlop = 40;
  /// 扇形半径：圆心 → 圆钮中心
  static const double _radius = 114;

  /// 数学角（度，x 右、y 上、逆时针）：上偏左 → 左偏上，角距拉大
  static const _slots = <
      ({RecordFabAction action, IconData icon, String label, double deg})>[
    (
      action: RecordFabAction.gallery,
      icon: Icons.photo_library_outlined,
      label: '图片',
      deg: 92,
    ),
    (
      action: RecordFabAction.camera,
      icon: Icons.photo_camera_outlined,
      label: '拍照',
      deg: 135,
    ),
    (
      action: RecordFabAction.voice,
      icon: Icons.mic_none,
      label: '语音',
      deg: 178,
    ),
  ];

  late final AnimationController _anim;
  OverlayEntry? _overlay;
  bool _pressed = false;
  bool _dialOpen = false;
  RecordFabAction? _hovered;
  Offset? _pointerGlobal;
  final _hubKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(_syncOverlay);
  }

  @override
  void dispose() {
    _anim.removeListener(_syncOverlay);
    _removeOverlay();
    _anim.dispose();
    super.dispose();
  }

  Offset _slotOffset(double deg, double t) {
    final rad = deg * math.pi / 180;
    // 屏幕坐标 y 向下：数学角的 sin 取反
    return Offset(
      _radius * t * math.cos(rad),
      -_radius * t * math.sin(rad),
    );
  }

  Offset? _hubCenterGlobal() {
    final box = _hubKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  void _syncOverlay() {
    _overlay?.markNeedsBuild();
  }

  void _insertOverlay() {
    if (_overlay != null) return;
    final overlay = Overlay.of(context);
    _overlay = OverlayEntry(builder: _buildOverlay);
    overlay.insert(_overlay!);
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  void _openDial() {
    if (_dialOpen) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _dialOpen = true;
      _hovered = null;
    });
    _insertOverlay();
    _anim.forward(from: 0);
  }

  void _closeDial({RecordFabAction? selected}) {
    void reset() {
      if (!mounted) return;
      _removeOverlay();
      setState(() {
        _dialOpen = false;
        _hovered = null;
        _pointerGlobal = null;
        _pressed = false;
      });
    }

    if (!_dialOpen) {
      reset();
      return;
    }
    _anim.reverse().whenComplete(reset);
    if (selected != null) {
      HapticFeedback.selectionClick();
      widget.onAction(selected);
    }
  }

  RecordFabAction? _hitTest(Offset global) {
    final center = _hubCenterGlobal();
    if (center == null) return null;
    final t = Curves.easeOutBack.transform(_anim.value.clamp(0.0, 1.0));

    RecordFabAction? best;
    var bestDist = double.infinity;
    for (final slot in _slots) {
      final c = center + _slotOffset(slot.deg, t.clamp(0.0, 1.0));
      // 命中圆心略偏下，兼顾文案
      final hitCenter = c + const Offset(0, 10);
      final d = (global - hitCenter).distance;
      if (d <= _hitSlop && d < bestDist) {
        bestDist = d;
        best = slot.action;
      }
    }
    return best;
  }

  Widget _buildOverlay(BuildContext context) {
    final t = Curves.easeOutCubic.transform(_anim.value.clamp(0.0, 1.0));
    final hub = _hubCenterGlobal();

    return IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: Color.fromRGBO(17, 24, 39, 0.38 * t),
            ),
            if (hub != null)
              for (var i = 0; i < _slots.length; i++)
                _overlayDialButton(
                  slot: _slots[i],
                  hub: hub,
                  t: t,
                  index: i,
                ),
          ],
        ),
      ),
    );
  }

  Widget _overlayDialButton({
    required ({RecordFabAction action, IconData icon, String label, double deg})
        slot,
    required Offset hub,
    required double t,
    required int index,
  }) {
    final stagger = index * 0.05;
    final localT =
        ((t - stagger) / (1 - stagger).clamp(0.01, 1.0)).clamp(0.0, 1.0);
    final center = hub + _slotOffset(slot.deg, localT);
    final hovered = _hovered == slot.action;
    final totalH = _dialSize + _labelGap + _labelHeight;
    final left = center.dx - _dialSize / 2;
    final top = center.dy - _dialSize / 2;

    return Positioned(
      left: left,
      top: top,
      width: _dialSize,
      height: totalH,
      child: Opacity(
        opacity: localT,
        child: Transform.scale(
          alignment: Alignment.topCenter,
          scale: 0.6 + 0.4 * localT,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: _dialSize,
                height: _dialSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hovered ? PigTokens.primary : PigTokens.surface,
                  boxShadow: [
                    BoxShadow(
                      color:
                          Colors.black.withValues(alpha: hovered ? 0.2 : 0.12),
                      blurRadius: hovered ? 14 : 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(
                    color: hovered
                        ? PigTokens.primary
                        : PigTokens.primary.withValues(alpha: 0.22),
                    width: 1.2,
                  ),
                ),
                child: Icon(
                  slot.icon,
                  color: hovered ? PigTokens.textOnPrimary : PigTokens.primary,
                  size: 24,
                ),
              ),
              SizedBox(height: _labelGap),
              Text(
                slot.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: hovered
                      ? PigTokens.textOnPrimary
                      : PigTokens.textOnPrimary.withValues(alpha: 0.92),
                  shadows: const [
                    Shadow(
                      color: Color(0x88000000),
                      blurRadius: 6,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () {
        if (!_dialOpen) setState(() => _pressed = false);
      },
      onTap: () {
        if (_dialOpen) return;
        widget.onPressed();
      },
      onLongPressStart: (d) {
        _pointerGlobal = d.globalPosition;
        setState(() => _pressed = true);
        _openDial();
      },
      onLongPressMoveUpdate: (d) {
        _pointerGlobal = d.globalPosition;
        final hit = _hitTest(d.globalPosition);
        if (hit != _hovered) {
          setState(() => _hovered = hit);
          _syncOverlay();
          if (hit != null) HapticFeedback.selectionClick();
        }
      },
      onLongPressEnd: (_) {
        final selected =
            _pointerGlobal == null ? _hovered : _hitTest(_pointerGlobal!);
        _closeDial(selected: selected);
      },
      onLongPressCancel: () => _closeDial(),
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          key: _hubKey,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          width: _dialOpen ? _hubSize : null,
          height: _dialOpen ? _hubSize : null,
          decoration: BoxDecoration(
            color: (_pressed || _dialOpen)
                ? PigTokens.primary
                : PigTokens.surface,
            borderRadius: BorderRadius.circular(
              _dialOpen ? _hubSize / 2 : PigTokens.radiusPill,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: (_pressed || _dialOpen) ? 0.16 : 0.08,
                ),
                blurRadius: (_pressed || _dialOpen) ? 12 : 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: _dialOpen
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(
                  horizontal: PigTokens.spaceLg,
                  vertical: PigTokens.spaceMd,
                ),
          alignment: Alignment.center,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: _dialOpen
                ? const Icon(
                    key: ValueKey('hub'),
                    Icons.close,
                    color: PigTokens.textOnPrimary,
                    size: 22,
                  )
                : const Row(
                    key: ValueKey('pill'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.edit_square,
                        color: PigTokens.primary,
                        size: 20,
                      ),
                      SizedBox(width: PigTokens.spaceSm),
                      Text(
                        '记一笔',
                        style: TextStyle(
                          color: PigTokens.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
