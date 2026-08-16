import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 主壳底部 Tab 下标：0 明细 / 1 报表 / 2 我的。
///
/// 独立成 Provider，便于后续从「记一笔保存成功」等场景跳回明细页。
final tabIndexProvider = StateProvider<int>((ref) => 0);
