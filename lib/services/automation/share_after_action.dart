/// 分享入账后的去向策略（「我的」可改；运行时弹窗也可设为默认）。
enum ShareAfterAction {
  /// 每次询问（默认）。
  ask,

  /// 留在小猪记账，不 [moveTaskToBack]。
  stay,

  /// 前台预热后返回上一应用（历史默认行为）。
  retreat,
}

extension ShareAfterActionX on ShareAfterAction {
  String get storageValue => switch (this) {
        ShareAfterAction.ask => 'ask',
        ShareAfterAction.stay => 'stay',
        ShareAfterAction.retreat => 'retreat',
      };

  String get label => switch (this) {
        ShareAfterAction.ask => '每次询问',
        ShareAfterAction.stay => '留在小猪记账',
        ShareAfterAction.retreat => '返回上一应用',
      };

  String get subtitle => switch (this) {
        ShareAfterAction.ask => '分享后弹出选择',
        ShareAfterAction.stay => '识别时继续停留在本应用',
        ShareAfterAction.retreat => '识别开始后回到来源应用',
      };

  static ShareAfterAction? tryParse(String? raw) {
    switch (raw) {
      case 'ask':
        return ShareAfterAction.ask;
      case 'stay':
        return ShareAfterAction.stay;
      case 'retreat':
      case 'return': // 兼容旧写法
        return ShareAfterAction.retreat;
      default:
        return null;
    }
  }
}
