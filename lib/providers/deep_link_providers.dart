import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 小组件深链待打开的记一笔类型（`expense` / `income`）；消费后置 null。
final pendingWidgetNewTypeProvider = StateProvider<String?>((ref) => null);
