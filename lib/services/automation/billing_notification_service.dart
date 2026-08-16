import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 自动记账进度/结果本地通知。
class BillingNotificationService {
  BillingNotificationService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channelId = 'piggy_auto_billing';
  static const progressId = 1001;
  static const resultId = 1101;

  Future<void> ensureInitialized() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
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
  }) async {
    try {
      await ensureInitialized();
      await _plugin.cancel(id: progressId);
      await _plugin.show(
        id: resultId,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            '智能记账',
            channelDescription: '截图/分享识别进度与结果',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (_) {}
  }

  Future<void> cancelProgress() async {
    try {
      await _plugin.cancel(id: progressId);
    } catch (_) {}
  }
}
