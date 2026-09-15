import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 记账通知点击动作（ADR-018）。
enum BillingNotificationAction {
  success,
  failure,
}

/// 自动记账进度/结果本地通知。
///
/// Android：进度与结果共用 `piggy_auto_billing`（默认重要度，只进通知栏、不横幅）；
/// 用不同 notification id 区分（1001/1002 进度，1101/1102 结果），避免与 FGS 互相覆盖。
class BillingNotificationService {
  BillingNotificationService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channelId = 'piggy_auto_billing';

  /// 旧结果专用渠道（曾 HIGH 横幅）；已并回 [_channelId]，初始化时删除以免设置里残留。
  static const _legacyResultChannelId = 'piggy_auto_billing_result';

  static const progressId = 1001;
  static const resultId = 1101;

  /// 补扫进度（ADR-080；不被 1001 相位覆盖）。
  static const resumeProgressId = 1002;

  /// 补扫结果（ADR-080；与 1101 分桶）。
  static const resumeResultId = 1102;

  static const payloadSuccess = 'piggy_auto_billing_ok';
  static const payloadFailure = 'piggy_auto_billing_fail';

  /// 最近一次失败通知正文；点失败通知时弹 Dialog 用。
  String? lastFailureBody;

  /// 最近一次失败通知标题；点失败通知时 Dialog 标题优先用此。
  String? lastFailureTitle;

  /// App 层注入：切到明细 / 弹失败框（成功不再滚到某笔，定位只走信封）。
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
          _channelId,
          '智能记账',
          description: '截图/分享识别进度与结果',
          importance: Importance.defaultImportance,
        ),
      );
      // 旧 HIGH 结果渠道无法降级；停用后删掉，避免设置里仍显示「智能记账结果」。
      await androidPlugin?.deleteNotificationChannel(
        channelId: _legacyResultChannelId,
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

  /// [clearProgress]：默认清进度 1001。关联窗取消且 FGS 仍被分享/批次持有时传 false（ADR-076）。
  Future<void> showResult({
    required String title,
    required String body,
    required bool success,
    bool clearProgress = true,
  }) async {
    try {
      await ensureInitialized();
      if (clearProgress) {
        await _plugin.cancel(id: progressId);
      }
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
            _channelId,
            '智能记账',
            channelDescription: '截图/分享识别进度与结果',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
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

  /// 补扫专用进度 1002（ADR-080）。
  Future<void> showResumeProgress({
    required String title,
    required String body,
  }) async {
    try {
      await ensureInitialized();
      await _plugin.show(
        id: resumeProgressId,
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
    } catch (_) {}
  }

  Future<void> cancelResumeProgress() async {
    try {
      await _plugin.cancel(id: resumeProgressId);
    } catch (_) {}
  }

  /// 补扫专用结果 1102；默认清 1002（ADR-080）。
  Future<void> showResumeResult({
    required String title,
    required String body,
    required bool success,
    bool clearResumeProgress = true,
  }) async {
    try {
      await ensureInitialized();
      if (clearResumeProgress) {
        await cancelResumeProgress();
      }
      if (!success) {
        lastFailureBody = body;
        lastFailureTitle = title;
      }
      await _plugin.show(
        id: resumeResultId,
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
        payload: success ? payloadSuccess : payloadFailure,
      );
    } catch (_) {}
  }
}
