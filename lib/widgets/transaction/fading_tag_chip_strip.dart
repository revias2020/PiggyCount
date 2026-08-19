import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 标签 chip 横滑槽：溢出时左右边缘淡出；槽内横滑独立于外层横向手势（ADR-036）。
class FadingTagChipStrip extends StatefulWidget {
  const FadingTagChipStrip({
    super.key,
    required this.children,
    required this.fadeColor,
    this.height = 18,
    this.spacing = 4,
  });

  final List<Widget> children;
  final Color fadeColor;
  final double height;
  final double spacing;

  @override
  State<FadingTagChipStrip> createState() => _FadingTagChipStripState();
}

class _FadingTagChipStripState extends State<FadingTagChipStrip> {
  final _controller = ScrollController();
  var _showLeft = false;
  var _showRight = false;

  static const _fadeWidth = 14.0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncFades);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFades());
  }

  @override
  void didUpdateWidget(covariant FadingTagChipStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFades());
  }

  @override
  void dispose() {
    _controller.removeListener(_syncFades);
    _controller.dispose();
    super.dispose();
  }

  void _syncFades() {
    if (!mounted || !_controller.hasClients) return;
    final pos = _controller.position;
    final overflow = pos.maxScrollExtent > 0.5;
    final left = overflow && pos.pixels > 0.5;
    final right = overflow && pos.pixels < pos.maxScrollExtent - 0.5;
    if (left == _showLeft && right == _showRight) return;
    setState(() {
      _showLeft = left;
      _showRight = right;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_controller.hasClients) return;
    final next = (_controller.offset - details.delta.dx)
        .clamp(0.0, _controller.position.maxScrollExtent);
    if (next != _controller.offset) {
      _controller.jumpTo(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: <Type, GestureRecognizerFactory>{
              _EagerHorizontalDragGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                      _EagerHorizontalDragGestureRecognizer>(
                () => _EagerHorizontalDragGestureRecognizer(),
                (instance) {
                  instance.onUpdate = _onDragUpdate;
                },
              ),
            },
            child: SingleChildScrollView(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Row(
                children: [
                  for (var i = 0; i < widget.children.length; i++) ...[
                    if (i > 0) SizedBox(width: widget.spacing),
                    widget.children[i],
                  ],
                ],
              ),
            ),
          ),
          if (_showLeft)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: _fadeWidth,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        widget.fadeColor,
                        widget.fadeColor.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_showRight)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: _fadeWidth,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        widget.fadeColor.withValues(alpha: 0),
                        widget.fadeColor,
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 在手势竞技场中抢赢外层横向拖拽，保证标签槽横滑优先。
class _EagerHorizontalDragGestureRecognizer
    extends HorizontalDragGestureRecognizer {
  @override
  void rejectGesture(int pointer) {
    acceptGesture(pointer);
  }
}
