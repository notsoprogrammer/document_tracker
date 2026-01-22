import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../services/supabase_service.dart';

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
      // Request exact alarm permission for Android API 31+
      if (await Permission.scheduleExactAlarm.isDenied) {
        await Permission.scheduleExactAlarm.request();
      }
    }
  }


  /* -----------------------------------------------------------
   * SCHEDULING
   * ---------------------------------------------------------*/
  Future<bool> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    final tzDate = _toTzDateTime(scheduledDate);

    if (tzDate.isBefore(tz.TZDateTime.now(tz.local))) {
      debugPrint('⚠️ Skipped scheduling (past date): $tzDate');
      return false;
    }

    // Check if exact alarms are permitted on Android
    if (Platform.isAndroid) {
      final canScheduleExact = await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.canScheduleExactNotifications();

      if (canScheduleExact != true) {
        debugPrint('⚠️ Cannot schedule exact notifications. Permission not granted.');
        return false;
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

    try {
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
      return true;
    } catch (e) {
      debugPrint('❌ Failed to schedule notification [$id]: $e');
      return false;
    }
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

    // ⏰ 1 day before
    final oneDayBefore =
        tz.TZDateTime.from(deadline, tz.local)
            .subtract(const Duration(days: 1));

    if (oneDayBefore.isAfter(now)) {
      final id = _generateId(documentCode, 'one_day');
      final success = await schedule(
        id: id,
        title: '📑 Compliance Reminder',
        body:
            'Document $documentCode (assigned to $assignedTo) is due in 1 day.',
        scheduledDate: oneDayBefore,
      );
      if (success) {
        newIds.add(id);
        await SupabaseService().addNotificationHistory(
          documentCode: documentCode,
          notificationType: '1_day_reminder',
          notificationId: id,
          scheduledTime: oneDayBefore,
        );
        debugPrint('Scheduled 1-day reminder for $documentCode at $oneDayBefore');
      }
    } else {
      debugPrint('Skipped 1-day reminder for $documentCode (past date: $oneDayBefore)');
    }

    // ⏰ 5 hours before
    final fiveHoursBefore =
        tz.TZDateTime.from(deadline, tz.local)
            .subtract(const Duration(hours: 5));

    if (fiveHoursBefore.isAfter(now)) {
      final id = _generateId(documentCode, 'five_hours');
      final success = await schedule(
        id: id,
        title: '📑 Compliance Reminder',
        body:
            'Document $documentCode (assigned to $assignedTo) is due in 5 hours.',
        scheduledDate: fiveHoursBefore,
      );
      if (success) {
        newIds.add(id);
        await SupabaseService().addNotificationHistory(
          documentCode: documentCode,
          notificationType: '5_hours_reminder',
          notificationId: id,
          scheduledTime: fiveHoursBefore,
        );
        debugPrint('Scheduled 5-hour reminder for $documentCode at $fiveHoursBefore');
      }
    } else {
      debugPrint('Skipped 5-hour reminder for $documentCode (past date: $fiveHoursBefore)');
    }

    // ⏰ At deadline
    final atDeadline = tz.TZDateTime.from(deadline, tz.local);

    if (atDeadline.isAfter(now)) {
      final timeToDeadline = atDeadline.difference(now);
      if (timeToDeadline.inMinutes <= 5) {
        // For very short deadlines, show immediate notification
        final id = _generateId(documentCode, 'deadline');
        await _plugin.show(
          id,
          '🚨 Compliance Deadline',
          'Document $documentCode (assigned to $assignedTo) is due NOW!',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              _channelName,
              channelDescription: _channelDesc,
              importance: Importance.max,
              priority: Priority.high,
            ),
          ),
        );
        await SupabaseService().addNotificationHistory(
          documentCode: documentCode,
          notificationType: 'immediate_deadline',
          notificationId: id,
          scheduledTime: atDeadline,
          status: 'shown',
        );
        debugPrint('Showed immediate deadline notification for $documentCode');
      } else {
        final id = _generateId(documentCode, 'deadline');
        final success = await schedule(
          id: id,
          title: '🚨 Compliance Deadline',
          body:
              'Document $documentCode (assigned to $assignedTo) is due NOW!',
          scheduledDate: atDeadline,
        );
        if (success) {
          newIds.add(id);
          await SupabaseService().addNotificationHistory(
            documentCode: documentCode,
            notificationType: 'deadline_reminder',
            notificationId: id,
            scheduledTime: atDeadline,
          );
          debugPrint('Scheduled deadline reminder for $documentCode at $atDeadline');
        }
      }
    } else {
      debugPrint('Skipped deadline reminder for $documentCode (past date: $atDeadline)');
    }

    // Add a test notification in 30 seconds if deadline is within 1 hour
    final timeToDeadline = atDeadline.difference(now);
    if (timeToDeadline.inHours < 1 && timeToDeadline.inSeconds > 0) {
      final testTime = now.add(const Duration(seconds: 30));
      final testId = _generateId(documentCode, 'test_30s');
      final success = await schedule(
        id: testId,
        title: 'Test Notification',
        body: 'This is a test notification 30 seconds after setting For Compliance.',
        scheduledDate: testTime,
      );
      if (success) {
        newIds.add(testId);
        debugPrint('Scheduled test notification for $documentCode at $testTime');
      }
    }

    debugPrint('Total notifications scheduled for $documentCode: ${newIds.length}');
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
      await SupabaseService().updateNotificationStatus(id, 'cancelled');
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

  Future<Map<String, bool>> checkPermissions() async {
    final notificationGranted = await Permission.notification.isGranted;
    final exactAlarmGranted = Platform.isAndroid ? await Permission.scheduleExactAlarm.isGranted : true;
    final canScheduleExact = Platform.isAndroid ? await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.canScheduleExactNotifications() ?? false : true;

    return {
      'notification': notificationGranted,
      'exact_alarm': exactAlarmGranted,
      'can_schedule_exact': canScheduleExact,
    };
  }
}
