import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._internal();
  static final NotificationService _instance =
      NotificationService._internal();
  factory NotificationService() => _instance;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Channel constants
  static const String _channelId = 'compliance_channel';
  static const String _channelName = 'Compliance Notifications';
  static const String _channelDesc =
      'Notifications for document compliance deadlines';

  /* -----------------------------------------------------------
   * INITIALIZATION
   * ---------------------------------------------------------*/
  Future<void> initialize() async {
    // 🌏 Initialize timezone (Philippines)
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Manila'));

    const androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _plugin.initialize(initSettings);

    await _createAndroidChannel();
    await _requestAndroidPermission();

    debugPrint('🔔 NotificationService initialized');
  }

  /* -----------------------------------------------------------
   * ANDROID SETUP
   * ---------------------------------------------------------*/
  Future<void> _createAndroidChannel() async {
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.max,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  Future<void> _requestAndroidPermission() async {
    if (Platform.isAndroid) {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    }
  }


  /* -----------------------------------------------------------
   * SCHEDULING
   * ---------------------------------------------------------*/
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    final tzDate = _toTzDateTime(scheduledDate);

    if (tzDate.isBefore(tz.TZDateTime.now(tz.local))) {
      debugPrint('⚠️ Skipped scheduling (past date): $tzDate');
      return;
    }

    // Check if exact alarms are permitted on Android
    if (Platform.isAndroid) {
      final canScheduleExact = await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.canScheduleExactNotifications();

      if (canScheduleExact != true) {
        debugPrint('⚠️ Cannot schedule exact notifications. Permission not granted.');
        return;
      }
    }

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails();

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzDate,
      notificationDetails,
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );

    debugPrint('✅ Scheduled notification [$id] at $tzDate');
  }

  /* -----------------------------------------------------------
   * COMPLIANCE NOTIFICATIONS
   * ---------------------------------------------------------*/
  Future<List<int>> scheduleComplianceNotifications({
    required String documentCode,
    required String assignedTo,
    required DateTime deadline,
    required List<int> existingIds,
  }) async {
    await cancelAll(existingIds);

    final now = tz.TZDateTime.now(tz.local);
    final List<int> newIds = [];

    // 📅 9AM day before
    final dayBefore = tz.TZDateTime(
      tz.local,
      deadline.year,
      deadline.month,
      deadline.day - 1,
      9,
    );

    if (dayBefore.isAfter(now)) {
      final id = _generateId(documentCode, 'day_before');
      await schedule(
        id: id,
        title: '📑 Compliance Reminder',
        body: 'Document $documentCode deadline is tomorrow.',
        scheduledDate: dayBefore,
      );
      newIds.add(id);
    }

    // ⏰ 2 hours before
    final twoHoursBefore =
        tz.TZDateTime.from(deadline, tz.local)
            .subtract(const Duration(hours: 2));

    if (twoHoursBefore.isAfter(now)) {
      final id = _generateId(documentCode, 'two_hours');
      await schedule(
        id: id,
        title: '📑 Compliance Reminder',
        body:
            'Document $documentCode (assigned to $assignedTo) is due in 2 hours.',
        scheduledDate: twoHoursBefore,
      );
      newIds.add(id);
    }

    return newIds;
  }

  /* -----------------------------------------------------------
   * CANCEL
   * ---------------------------------------------------------*/
  Future<void> cancel(int id) async {
    await _plugin.cancel(id);
  }

  Future<void> cancelAll(List<int> ids) async {
    for (final id in ids) {
      await cancel(id);
    }
  }

  /* -----------------------------------------------------------
   * HELPERS
   * ---------------------------------------------------------*/
  tz.TZDateTime _toTzDateTime(DateTime date) {
    return tz.TZDateTime(
      tz.local,
      date.year,
      date.month,
      date.day,
      date.hour,
      date.minute,
      date.second,
    );
  }

  int _generateId(String code, String type) {
    return '$code$type'.hashCode.abs();
  }

  /* -----------------------------------------------------------
   * DEBUG
   * ---------------------------------------------------------*/
  Future<void> showTestNotification() async {
    await _plugin.show(
      999,
      'Test Notification',
      'If you see this, notifications work 🎉',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'test_channel',
          'Test Channel',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
    );
  }
}
