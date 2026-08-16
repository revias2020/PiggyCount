import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../styles/tokens.dart';

/// 报表页 AI 浮动球：可拖动、位置按屏占比持久化；轻点进入 AI 账单助手。
///
/// 必须作为 [Stack] 的直接子节点（内部用 [Positioned.fill]，空白区不拦截手势）。
class AiFab extends StatefulWidget {
  const AiFab({super.key, required this.onPressed});

  final VoidCallback onPressed;

  static const double size = 56;
  static const _prefsX = 'ai_fab_x_ratio';
  static const _prefsY = 'ai_fab_y_ratio';

  /// 累计位移超过该阈值才视为拖动，否则松手触发点击。
  static const _dragSlop = 8.0;

  @override
  State<AiFab> createState() => _AiFabState();
}

class _AiFabState extends State<AiFab> {
  bool _pressed = false;
  bool _dragging = false;

  Offset? _dragStartTopLeft;
  Offset _dragDelta = Offset.zero;

  /// 相对可用区的左上角比例；未加载前用右下角默认位。
  double? _xRatio;
  double? _yRatio;

  /// 拖动过程中的临时左上角（未提交比例）。
  Offset? _liveTopLeft;

  @override
  void initState() {
    super.initState();
    _loadPosition();
  }

  Future<void> _loadPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final x = prefs.getDouble(AiFab._prefsX);
    final y = prefs.getDouble(AiFab._prefsY);
    if (!mounted) return;
    if (x != null && y != null) {
      setState(() {
        _xRatio = x.clamp(0.0, 1.0);
        _yRatio = y.clamp(0.0, 1.0);
      });
    }
  }

  Future<void> _savePosition(double xRatio, double yRatio) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(AiFab._prefsX, xRatio);
    await prefs.setDouble(AiFab._prefsY, yRatio);
  }

  Offset _defaultTopLeft(Size area) {
    return Offset(
      area.width - AiFab.size - PigTokens.spaceLg,
      area.height - AiFab.size - PigTokens.spaceLg,
    );
  }

  Offset _clamp(Size area, Offset topLeft) {
    final maxX = (area.width - AiFab.size).clamp(0.0, double.infinity);
    final maxY = (area.height - AiFab.size).clamp(0.0, double.infinity);
    return Offset(
      topLeft.dx.clamp(0.0, maxX),
      topLeft.dy.clamp(0.0, maxY),
    );
  }

  Offset _resolvedTopLeft(Size area) {
    if (_liveTopLeft != null) return _clamp(area, _liveTopLeft!);
    final maxX = (area.width - AiFab.size).clamp(0.0, double.infinity);
    final maxY = (area.height - AiFab.size).clamp(0.0, double.infinity);
    if (_xRatio == null || _yRatio == null) {
      return _defaultTopLeft(area);
    }
    return Offset(
      (_xRatio! * maxX).clamp(0.0, maxX),
      (_yRatio! * maxY).clamp(0.0, maxY),
    );
  }

  void _commitPosition(Offset topLeft, Size area) {
    final clamped = _clamp(area, topLeft);
    final maxX = (area.width - AiFab.size).clamp(0.0, double.infinity);
    final maxY = (area.height - AiFab.size).clamp(0.0, double.infinity);
    final xRatio = maxX <= 0 ? 1.0 : clamped.dx / maxX;
    final yRatio = maxY <= 0 ? 1.0 : clamped.dy / maxY;
    setState(() {
      _xRatio = xRatio;
      _yRatio = yRatio;
      _liveTopLeft = null;
    });
    _savePosition(xRatio, yRatio);
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final area = Size(constraints.maxWidth, constraints.maxHeight);
          final pos = _resolvedTopLeft(area);

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: pos.dx,
                top: pos.dy,
                child: GestureDetector(
                  onPanStart: (_) {
                    _dragStartTopLeft = pos;
                    _dragDelta = Offset.zero;
                    _dragging = false;
                    setState(() => _pressed = true);
                  },
                  onPanUpdate: (details) {
                    final start = _dragStartTopLeft;
                    if (start == null) return;
                    _dragDelta += details.delta;
                    if (!_dragging &&
                        _dragDelta.distance > AiFab._dragSlop) {
                      _dragging = true;
                    }
                    if (!_dragging) return;
                    setState(() {
                      _liveTopLeft = _clamp(area, start + _dragDelta);
                    });
                  },
                  onPanEnd: (_) {
                    setState(() => _pressed = false);
                    if (_dragging) {
                      _commitPosition(_liveTopLeft ?? pos, area);
                    } else {
                      widget.onPressed();
                    }
                    _dragging = false;
                    _dragStartTopLeft = null;
                    _dragDelta = Offset.zero;
                  },
                  onPanCancel: () {
                    setState(() {
                      _pressed = false;
                      _liveTopLeft = null;
                    });
                    _dragging = false;
                    _dragStartTopLeft = null;
                    _dragDelta = Offset.zero;
                  },
                  child: AnimatedScale(
                    scale: _pressed ? 0.92 : 1,
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOut,
                    child: Material(
                      elevation: _pressed ? 2 : 4,
                      shadowColor: Colors.black26,
                      shape: const CircleBorder(),
                      child: Ink(
                        width: AiFab.size,
                        height: AiFab.size,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              PigTokens.aiGradientStart,
                              PigTokens.aiGradientEnd,
                            ],
                          ),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.smart_toy_outlined,
                              color: PigTokens.textOnPrimary,
                              size: 22,
                            ),
                            Text(
                              'AI',
                              style: TextStyle(
                                color: PigTokens.textOnPrimary,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
