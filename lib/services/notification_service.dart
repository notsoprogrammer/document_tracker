import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../utils/date_time_utils.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings();

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  Future<void> scheduleComplianceNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    final tz.TZDateTime scheduledTZDateTime = tz.TZDateTime.from(scheduledDate, tz.local);

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'compliance_channel',
      'Compliance Notifications',
      channelDescription: 'Notifications for document compliance deadlines',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: false,
    );

    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
        DarwinNotificationDetails();

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );

    await _flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      scheduledTZDateTime,
      platformChannelSpecifics,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancelNotification(int id) async {
    await _flutterLocalNotificationsPlugin.cancel(id);
  }

  Future<void> cancelAllNotifications(List<int> ids) async {
    for (final id in ids) {
      await cancelNotification(id);
    }
  }

  Future<List<int>> scheduleComplianceNotifications({
    required String documentCode,
    required DateTime deadline,
    required List<int> existingIds,
  }) async {
    // Cancel existing notifications first
    await cancelAllNotifications(existingIds);

    final now = getPhilippineTime();
    final deadlineInPh = tz.TZDateTime.from(deadline, tz.local);

    List<Map<String, dynamic>> notifications = [];

    // If deadline is more than 2 days away, schedule reminder at 9 AM the day before
    if (deadline.difference(now).inDays > 2) {
      final reminderDate = deadline.subtract(const Duration(days: 1));
      final reminderTime = DateTime(
        reminderDate.year,
        reminderDate.month,
        reminderDate.day,
        9, // 9 AM
        0,
      );
      notifications.add({
        'id': _generateNotificationId(documentCode, 'reminder'),
        'title': '📑 Compliance Reminder',
        'body': 'Document $documentCode deadline tomorrow.',
        'scheduledDate': reminderTime,
      });
    }

    // Schedule notification 12 hours before deadline
    final twelveHoursBefore = deadline.subtract(const Duration(hours: 12));
    if (twelveHoursBefore.isAfter(now)) {
      notifications.add({
        'id': _generateNotificationId(documentCode, 'deadline'),
        'title': '📑 Compliance Reminder',
        'body': 'Document $documentCode deadline in 2 hours.',
        'scheduledDate': twelveHoursBefore,
      });
    }

    // Schedule notifications
    List<int> newIds = [];
    for (final notification in notifications) {
      await scheduleComplianceNotification(
        id: notification['id'],
        title: notification['title'],
        body: notification['body'],
        scheduledDate: notification['scheduledDate'],
      );
      newIds.add(notification['id']);
    }

    return newIds;
  }

  int _generateNotificationId(String documentCode, String type) {
    // Generate unique ID based on document code and type
    return '${documentCode.hashCode}${type.hashCode}'.hashCode.abs();
  }
}
