import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 记账通知点击动作（ADR-018）。
enum BillingNotificationAction {
  success,
  failure,
}

/// 自动记账进度/结果本地通知。
class BillingNotificationService {
  BillingNotificationService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channelId = 'piggy_auto_billing';
  static const progressId = 1001;
  static const resultId = 1101;

  static const payloadSuccess = 'piggy_auto_billing_ok';
  static const payloadFailure = 'piggy_auto_billing_fail';

  /// 最近一次失败通知正文；点失败通知时弹 Dialog 用。
  String? lastFailureBody;

  /// App 层注入：切到明细 / 弹失败框。
  void Function(BillingNotificationAction action)? onAction;

  Future<void> ensureInitialized() async {
    if (_ready) return;
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
        _channelId,
        '智能记账',
        description: '截图/分享识别进度与结果',
        importance: Importance.defaultImportance,
      ),
    );
    _ready = true;
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
            _channelId,
            '智能记账',
            channelDescription: '截图/分享识别进度与结果',
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
      if (!success) lastFailureBody = body;
      await _plugin.show(
        id: resultId,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            '智能记账',
            channelDescription: '截图/分享识别进度与结果',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(),
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
