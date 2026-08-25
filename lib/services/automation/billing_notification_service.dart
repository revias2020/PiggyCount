import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 记账通知点击动作（ADR-018）。
enum BillingNotificationAction {
  success,
  failure,
}

/// 自动记账进度/结果本地通知。
///
/// Android：进度与结果分渠道——进度默认重要度（不横幅）；结果高重要度横幅且无声无震。
/// 结果渠道用新 id，避免已安装用户无法抬高旧渠道等级。
class BillingNotificationService {
  BillingNotificationService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _progressChannelId = 'piggy_auto_billing';
  static const _resultChannelId = 'piggy_auto_billing_result';
  static const progressId = 1001;
  static const resultId = 1101;

  static const payloadSuccess = 'piggy_auto_billing_ok';
  static const payloadFailure = 'piggy_auto_billing_fail';

  /// 最近一次失败通知正文；点失败通知时弹 Dialog 用。
  String? lastFailureBody;

  /// 最近一次失败通知标题；点失败通知时 Dialog 标题优先用此。
  String? lastFailureTitle;

  /// 最近一次成功直存的账单 syncId（点成功通知滚到该笔）。
  String? lastSuccessSyncId;

  /// App 层注入：切到明细 / 弹失败框。
  void Function(BillingNotificationAction action)? onAction;

  Future<void> ensureInitialized() async {
    if (_ready) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings();
      await _plugin.initialize(
        settings: const InitializationSettings(android: android, iOS: ios),
        onDidReceiveNotificationResponse: _onResponse,
      );
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _progressChannelId,
          '智能记账进度',
          description: '截图/分享识别进行中',
          importance: Importance.defaultImportance,
        ),
      );
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _resultChannelId,
          '智能记账结果',
          description: '截图/分享识别结果（横幅、无声）',
          importance: Importance.high,
          playSound: false,
          enableVibration: false,
        ),
      );
      _ready = true;
    } catch (_) {
      // 测试环境 / 无平台实现时跳过；真机启动仍可稍后重试。
    }
  }

  /// 冷启动：若用户是点结果通知打开的 App，回放一次点击动作。
  Future<void> consumeLaunchAction() async {
    try {
      await ensureInitialized();
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp != true) return;
      final payload = details!.notificationResponse?.payload;
      _dispatchPayload(payload);
    } catch (_) {}
  }

  void _onResponse(NotificationResponse response) {
    _dispatchPayload(response.payload);
  }

  void _dispatchPayload(String? payload) {
    if (payload == payloadSuccess) {
      onAction?.call(BillingNotificationAction.success);
    } else if (payload == payloadFailure) {
      onAction?.call(BillingNotificationAction.failure);
    }
  }

  Future<void> showProgress({
    required String title,
    required String body,
  }) async {
    try {
      await ensureInitialized();
      await _plugin.show(
        id: progressId,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _progressChannelId,
            '智能记账进度',
            channelDescription: '截图/分享识别进行中',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (_) {
      // 通知失败不影响记账主流程
    }
  }

  Future<void> showResult({
    required String title,
    required String body,
    required bool success,
  }) async {
    try {
      await ensureInitialized();
      await _plugin.cancel(id: progressId);
      if (!success) {
        lastFailureBody = body;
        lastFailureTitle = title;
      }
      await _plugin.show(
        id: resultId,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _resultChannelId,
            '智能记账结果',
            channelDescription: '截图/分享识别结果（横幅、无声）',
            importance: Importance.high,
            priority: Priority.high,
            playSound: false,
            enableVibration: false,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: success ? payloadSuccess : payloadFailure,
      );
    } catch (_) {}
  }

  Future<void> cancelProgress() async {
    try {
      await _plugin.cancel(id: progressId);
    } catch (_) {}
  }
}
