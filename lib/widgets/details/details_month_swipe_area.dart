import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 明细账单列表区：清晰横滑时切换浏览月（竖滚与 chip 槽横滑优先）。
class DetailsMonthSwipeArea extends StatefulWidget {
  const DetailsMonthSwipeArea({
    super.key,
    required this.child,
    required this.onMonthDelta,
  });

  final Widget child;

  /// −1 = 上一月，+1 = 下一月。
  final ValueChanged<int> onMonthDelta;

  @override
  State<DetailsMonthSwipeArea> createState() => _DetailsMonthSwipeAreaState();
}

class _DetailsMonthSwipeAreaState extends State<DetailsMonthSwipeArea> {
  var _dx = 0.0;

  static const _distanceThreshold = 56.0;
  static const _velocityThreshold = 300.0;

  void _reset() => _dx = 0;

  void _maybeCommit(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final adx = _dx.abs();
    final byDistance = adx >= _distanceThreshold;
    final byVelocity =
        velocity.abs() >= _velocityThreshold && adx > 16;
    if (!byDistance && !byVelocity) {
      _reset();
      return;
    }

    final left = _dx < 0 || (adx <= 16 && velocity < 0);
    widget.onMonthDelta(left ? 1 : -1);
    _reset();
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      // opaque：空月 EmptyState 空白区也要能接到横滑（deferToChild 会丢命中）。
      behavior: HitTestBehavior.opaque,
      gestures: <Type, GestureRecognizerFactory>{
        HorizontalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>(
          HorizontalDragGestureRecognizer.new,
          (instance) {
            instance.onStart = (_) => _reset();
            instance.onUpdate = (details) => _dx += details.delta.dx;
            instance.onEnd = _maybeCommit;
          },
        ),
      },
      child: widget.child,
    );
  }
}
