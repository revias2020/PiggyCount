import 'package:flutter/material.dart';

import '../styles/tokens.dart';

/// 引擎级键盘高度。modal builder 里 [MediaQuery.viewInsets] 常被清成 0。
double workspaceKeyboardInset(BuildContext context) {
  return MediaQueryData.fromView(View.of(context)).viewInsets.bottom;
}

/// 弹出工作台弹层：overlay 透明，白卡在底部且不超过屏高比例（ADR-040）。
///
/// [fixedHeight] 占满 [heightFraction]（默认工作台 85%）。
/// [ignoreKeyboard] 为 true 时钉在物理屏底（记一笔主层）；否则键盘升起把弹层顶上去，收起后落回。
Future<T?> showWorkspaceSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool fixedHeight = false,
  bool ignoreKeyboard = false,
  bool useRootNavigator = false,
  double? heightFraction,
  Color? barrierColor,
  AnimationStyle? sheetAnimationStyle,
}) {
  final screenH = MediaQuery.sizeOf(context).height;
  final fraction = heightFraction ?? PigTokens.sheetMaxFraction;
  final capByFraction = screenH * fraction;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: useRootNavigator,
    useSafeArea: false,
    backgroundColor: Colors.transparent,
    elevation: 0,
    clipBehavior: Clip.none,
    barrierColor: barrierColor ?? Colors.black.withValues(alpha: 0.45),
    sheetAnimationStyle: sheetAnimationStyle,
    builder: (ctx) {
      final sheet = Material(
        color: PigTokens.surface,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(PigTokens.radiusSheet),
          ),
        ),
        child: builder(ctx),
      );
      return LayoutBuilder(
        builder: (context, constraints) {
          if (ignoreKeyboard) {
            return OverflowBox(
              alignment: Alignment.topCenter,
              maxHeight: screenH,
              child: SizedBox(
                height: screenH,
                width: double.infinity,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    height: capByFraction,
                    width: double.infinity,
                    child: sheet,
                  ),
                ),
              ),
            );
          }

          final parentH = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : screenH;
          final keyboard = workspaceKeyboardInset(context);
          var alreadyLifted = screenH - parentH;
          if (alreadyLifted < 0) alreadyLifted = 0;
          final extraPad =
              keyboard > alreadyLifted ? keyboard - alreadyLifted : 0.0;

          final card = SizedBox(
            height: fixedHeight ? capByFraction : null,
            width: double.infinity,
            child: fixedHeight
                ? sheet
                : ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: capByFraction),
                    child: sheet,
                  ),
          );

          return Padding(
            padding: EdgeInsets.only(bottom: extraPad),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: card,
            ),
          );
        },
      );
    },
  );
}

/// 工作台弹层内边距（限高与键盘由 [showWorkspaceSheet] 处理）。
class WorkspaceSheetFrame extends StatelessWidget {
  const WorkspaceSheetFrame({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 20),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}

/// 限高内可滚动的中间区：内容少则变矮，超出才滚（须放在 [Flexible] 里）。
class WorkspaceSheetScroll extends StatelessWidget {
  const WorkspaceSheetScroll({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      children: [child],
    );
  }
}
