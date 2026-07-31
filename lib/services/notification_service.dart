import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import '../services/supabase_service.dart';
import '../models/activity.dart';
import '../models/document.dart';
import '../utils/web_notif.dart';

class NotificationService {
  NotificationService._internal();
  static final NotificationService _instance =
      NotificationService._internal();
  factory NotificationService() => _instance;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  /// Web push VAPID key — Firebase Console → Project Settings →
  /// Cloud Messaging → Web Push certificates → Key pair
  static const String _webVapidKey =
      'BEvvwv7-qAHEABOxzJNYWAYRRXiajNzMl2KPEd6xSBwSudl8oA1Sd8Qe3enA0NDdIlvbrvQ8SZnzkICxGHjBrOg';

  /// Channel constants
  static const String _channelId = 'compliance_channel';
  static const String _channelName = 'Compliance Notifications';
  static const String _channelDesc =
      'Notifications for document compliance deadlines';

  /// Preference keys
  static const String _prefImmediate = 'immediate_notifications';
  static const String _prefTwentyFourHour = 'twenty_four_hour_notifications';
  static const String _prefOverdue = 'overdue_notifications';
  static const String _prefActivity = 'activity_notifications';
  static const String _prefActivityLastShown = 'activity_notification_last_shown';
  static const String _prefAssignment = 'assignment_notifications';
  static const String _prefEventReminder = 'event_reminder_notifications';

  /* -----------------------------------------------------------
   * INITIALIZATION
   * ---------------------------------------------------------*/
  Future<void> initialize() async {
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
    await _requestNotificationPermission();

    // Initialize FCM
    await _initializeFCM();
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

  Future<void> _requestNotificationPermission() async {
    if (!kIsWeb && Platform.isAndroid) {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    }

    // Skip permission request on web to avoid blocking the app startup
    // FirebaseMessaging will handle permission when attempting to get token
    if (!kIsWeb) {
      await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  Future<void> requestNotificationPermission() async {
    await _requestNotificationPermission();
  }

  /* -----------------------------------------------------------
   * FCM SETUP
   * ---------------------------------------------------------*/
  Future<void> _initializeFCM() async {
    // Get FCM token and save to Supabase (non-blocking on web)
    try {
      final token = await _firebaseMessaging.getToken(vapidKey: kIsWeb ? _webVapidKey : null);
      if (token != null) {
        final username = await _getCurrentUsername();
        if (username != null) {
          await SupabaseService().saveDeviceToken(token, username);
        } else {
        }
      }
    } catch (e) {
      // Continue initialization even if token retrieval fails
    }

    // Listen for token refresh
    _firebaseMessaging.onTokenRefresh.listen((newToken) async {
      final username = await _getCurrentUsername();
      if (username != null) {
        await SupabaseService().saveDeviceToken(newToken, username);
      }
    });

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle background messages
    FirebaseMessaging.onBackgroundMessage(_handleBackgroundMessage);

    // Handle messages when app is opened from terminated state
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);
  }

  /* -----------------------------------------------------------
   * FCM MESSAGE HANDLERS
   * ---------------------------------------------------------*/
  Future<void> _handleForegroundMessage(RemoteMessage message) async {

    final notification = message.notification;
    if (notification != null) {
      // Check if notification should be shown based on user preferences
      final shouldShow = await _shouldShowNotification(message);
      if (shouldShow) {
        await _showLocalNotification(
          title: notification.title ?? 'Notification',
          body: notification.body ?? '',
        );
      } else {
      }
    }
  }

  Future<void> _handleMessageOpenedApp(RemoteMessage message) async {
    // Handle navigation if needed
  }

  /* -----------------------------------------------------------
   * LOCAL NOTIFICATION DISPLAY
   * ---------------------------------------------------------*/
  Future<void> _showLocalNotification({
    required String title,
    required String body,
  }) async {
    if (kIsWeb) {
      await showBrowserNotification(title, body);
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
    );

    const iosDetails = DarwinNotificationDetails();

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _plugin.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        notificationDetails,
      );
    } catch (e) {
    }
  }

  /* -----------------------------------------------------------
   * BACKWARD COMPATIBILITY (REMOVE LOCAL SCHEDULING)
   * ---------------------------------------------------------*/
  Future<List<int>> scheduleComplianceNotifications({
    required String documentCode,
    required String assignedTo,
    required DateTime deadline,
    required List<int> existingIds,
  }) async {
    // No longer schedule local notifications
    // Instead, this could trigger a backend call to schedule FCM notifications
    return []; // Return empty list since no local IDs
  }

  Future<void> cancelAll(List<int> ids) async {
    // No-op since we don't schedule local notifications anymore
  }

  /* -----------------------------------------------------------
   * DEBUG
   * ---------------------------------------------------------*/
  Future<void> showTestNotification() async {
    await _showLocalNotification(
      title: 'Test Notification',
      body: 'If you see this, FCM notifications work 🎉',
    );
  }

  /* -----------------------------------------------------------
   * ACTIVITY NOTIFICATION
   * ---------------------------------------------------------*/
  /// Shows a local notification summarising today's activities and calendar events.
  /// Fires at most once per calendar day (guarded by SharedPreferences).
  Future<void> showTodayActivityNotification({
    required List<Activity> activities,
    required List<Document> calendarDocs,
  }) async {
    final prefs = await getNotificationPreferences();
    if (!(prefs['activityNotifications'] ?? true)) return;

    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);

    final todayActivities = activities.where((a) {
      final start = DateTime(a.startTime.year, a.startTime.month, a.startTime.day);
      final end = a.endTime != null
          ? DateTime(a.endTime!.year, a.endTime!.month, a.endTime!.day)
          : start;
      return !todayDay.isBefore(start) && !todayDay.isAfter(end);
    }).toList();

    final todayDocs = calendarDocs.where((d) {
      final cd = d.calendarDeadline;
      if (cd == null) return false;
      final start = DateTime(cd.year, cd.month, cd.day);
      final end = d.calendarDeadlineEnd != null
          ? DateTime(d.calendarDeadlineEnd!.year, d.calendarDeadlineEnd!.month, d.calendarDeadlineEnd!.day)
          : start;
      return !todayDay.isBefore(start) && !todayDay.isAfter(end);
    }).toList();

    final total = todayActivities.length + todayDocs.length;
    if (total == 0) return;

    // Only show once per day
    final appPrefs = await SharedPreferences.getInstance();
    final todayStr = '${today.year}-${today.month}-${today.day}';
    if (appPrefs.getString(_prefActivityLastShown) == todayStr) return;
    await appPrefs.setString(_prefActivityLastShown, todayStr);

    final title = total == 1 ? '1 Event Today' : '$total Events Today';

    String firstLabel;
    if (todayActivities.isNotEmpty) {
      firstLabel = todayActivities.first.title ?? 'Activity';
    } else {
      firstLabel = todayDocs.first.title ?? 'Event';
    }
    final body = total == 1 ? firstLabel : '$firstLabel and ${total - 1} more';

    await _showLocalNotification(title: title, body: body);
  }

  /* -----------------------------------------------------------
   * MEETING REMINDER (8:10 AM, or 1 hour before for early events)
   * ---------------------------------------------------------*/
  /// Schedules a device-local notification for an activity.
  /// Reminder rule: events that start before 8:00 AM alert 1 hour before
  /// (an 8:10 AM reminder would land too late); everything else alerts at
  /// 8:10 AM on the day of the event.
  /// No-op on web (handled server-side) or if the reminder time has passed.
  Future<void> scheduleActivityReminder(Activity activity) async {
    if (kIsWeb) return;

    final prefs = await getNotificationPreferences();
    if (!(prefs['eventReminders'] ?? true)) return;

    await _scheduleRuleReminder(activity.startTime, activity.title, 0);
  }

  /// Reminder-time rule shared by activities and calendar documents:
  ///   • start before 8:00 AM  → 1 hour before start
  ///   • start at/after 8:00 AM → 8:10 AM on the day of the event
  /// The 8:00–8:10 AM window falls back to 1 hour before so the reminder
  /// never lands after the event has already started.
  DateTime _reminderTimeFor(DateTime startTime) {
    final eightTen = DateTime(
      startTime.year, startTime.month, startTime.day, 8, 10,
    );
    if (startTime.hour < 8) {
      return startTime.subtract(const Duration(hours: 1));
    }
    if (eightTen.isBefore(startTime)) {
      return eightTen;
    }
    return startTime.subtract(const Duration(hours: 1));
  }

  /// Human-friendly reminder body. Short countdowns read "Starting in N
  /// minutes"; anything further out shows the actual start time of day.
  String _reminderBody(DateTime startTime, DateTime reminderTime) {
    final diff = startTime.difference(reminderTime);
    if (diff.inMinutes <= 0) return 'Starting now';
    if (diff.inMinutes < 60) return 'Starting in ${diff.inMinutes} minutes';
    final hour12 = startTime.hour % 12 == 0 ? 12 : startTime.hour % 12;
    final minute = startTime.minute.toString().padLeft(2, '0');
    final ampm = startTime.hour < 12 ? 'AM' : 'PM';
    return 'Scheduled at $hour12:$minute $ampm today';
  }

  /// Schedules a single rule-based reminder for [startTime]. [idSalt] keeps
  /// activity and document reminders from colliding when they share a time.
  Future<void> _scheduleRuleReminder(
    DateTime startTime,
    String? title,
    int idSalt,
  ) async {
    if (startTime.isBefore(DateTime.now())) return;

    final reminderTime = _reminderTimeFor(startTime);
    if (reminderTime.isBefore(DateTime.now())) return;

    final location = tz.getLocation('Asia/Manila');
    final tzReminder = tz.TZDateTime.from(reminderTime, location);

    const androidDetails = AndroidNotificationDetails(
      _channelId, _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.high,
    );
    const notifDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    // Stable ID derived from the event's start time (plus a salt per source).
    final notifId =
        (startTime.millisecondsSinceEpoch ~/ 1000 + idSalt) & 0x7FFFFFFF;

    try {
      await _plugin.zonedSchedule(
        notifId,
        title ?? 'Upcoming Event',
        _reminderBody(startTime, reminderTime),
        tzReminder,
        notifDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
    }
  }

  /* -----------------------------------------------------------
   * 10-MINUTE REMINDER FOR INVOLVED PERSONNEL
   * ---------------------------------------------------------*/
  /// Schedules a 10-minute pre-schedule notification if the current user is in
  /// the activity's peopleInvolved list and has assignmentNotifications enabled.
  Future<void> scheduleActivityReminderForInvolved(Activity activity, String currentUsername) async {
    if (kIsWeb) return;

    final prefs = await getNotificationPreferences();
    if (!(prefs['assignmentNotifications'] ?? true)) return;

    final people = activity.peopleInvolved
        .split(',')
        .map((p) => p.trim().toLowerCase())
        .toList();
    if (!people.contains(currentUsername.toLowerCase())) return;

    await _scheduleMinutesBeforeReminder(activity.startTime, activity.title, 10);

    // Also schedule for extra dates using the same time-of-day
    for (final extraDate in activity.extraDates) {
      final extraDt = DateTime(
        extraDate.year, extraDate.month, extraDate.day,
        activity.startTime.hour, activity.startTime.minute,
      );
      await _scheduleMinutesBeforeReminder(extraDt, activity.title, 10);
    }
  }

  Future<void> _scheduleMinutesBeforeReminder(DateTime startTime, String? title, int minutesBefore) async {
    if (startTime.isBefore(DateTime.now())) return;

    final reminderTime = startTime.subtract(Duration(minutes: minutesBefore));
    if (reminderTime.isBefore(DateTime.now())) return;

    final location = tz.getLocation('Asia/Manila');
    final tzReminder = tz.TZDateTime.from(reminderTime, location);

    const androidDetails = AndroidNotificationDetails(
      _channelId, _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.high,
    );
    const notifDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    // Offset by minutesBefore * 1M so 10-min and 30-min IDs don't collide
    final notifId = (startTime.millisecondsSinceEpoch ~/ 1000 + minutesBefore * 1000000) & 0x7FFFFFFF;

    try {
      await _plugin.zonedSchedule(
        notifId,
        title ?? 'Upcoming Event',
        'Starting in $minutesBefore minutes',
        tzReminder,
        notifDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {}
  }

  /* -----------------------------------------------------------
   * DOCUMENT CALENDAR REMINDER (8:10 AM, or 1 hour before for early events)
   * ---------------------------------------------------------*/
  /// Schedules a rule-based reminder for a document that has a calendar
  /// deadline (the scheduled date/time shown on the calendar). Uses the same
  /// 8:10 AM / 1-hour-before rule as activities.
  /// No-op on web, if activity notifications are disabled, or if the deadline
  /// has no time-of-day beyond midnight (all-day entries are covered by the
  /// daily summary instead).
  Future<void> scheduleDocumentReminder(Document document) async {
    if (kIsWeb) return;

    final prefs = await getNotificationPreferences();
    if (!(prefs['eventReminders'] ?? true)) return;

    final deadline = document.calendarDeadline;
    if (deadline == null) return;
    if (deadline.isBefore(DateTime.now())) return;

    // Skip all-day entries (midnight with no specific time) — those are handled
    // by the once-a-day summary notification, not a timed reminder.
    if (deadline.hour == 0 && deadline.minute == 0) return;

    await _scheduleRuleReminder(deadline, document.title, 60000000);
  }

  /* -----------------------------------------------------------
   * NOTIFICATION PREFERENCES
   * ---------------------------------------------------------*/
  Future<void> setNotificationPreferences({
    bool? immediateNotifications,
    bool? twentyFourHourNotifications,
    bool? overdueNotifications,
    bool? activityNotifications,
    bool? assignmentNotifications,
    bool? eventReminders,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (immediateNotifications != null) {
      await prefs.setBool(_prefImmediate, immediateNotifications);
    }
    if (twentyFourHourNotifications != null) {
      await prefs.setBool(_prefTwentyFourHour, twentyFourHourNotifications);
    }
    if (overdueNotifications != null) {
      await prefs.setBool(_prefOverdue, overdueNotifications);
    }
    if (activityNotifications != null) {
      await prefs.setBool(_prefActivity, activityNotifications);
    }
    if (assignmentNotifications != null) {
      await prefs.setBool(_prefAssignment, assignmentNotifications);
    }
    if (eventReminders != null) {
      await prefs.setBool(_prefEventReminder, eventReminders);
    }

    await _syncPreferencesToDevice();

    if ((immediateNotifications == true) || (twentyFourHourNotifications == true) || (overdueNotifications == true)) {
      await _getAndSaveToken();
    }
  }

  Future<Map<String, bool>> getNotificationPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'immediateNotifications': prefs.getBool(_prefImmediate) ?? false,
      'twentyFourHourNotifications': prefs.getBool(_prefTwentyFourHour) ?? true,
      'overdueNotifications': prefs.getBool(_prefOverdue) ?? true,
      'activityNotifications': prefs.getBool(_prefActivity) ?? true,
      'assignmentNotifications': prefs.getBool(_prefAssignment) ?? true,
      'eventReminders': prefs.getBool(_prefEventReminder) ?? true,
    };
  }

  Future<bool> _shouldShowNotification(RemoteMessage message) async {
    final prefs = await getNotificationPreferences();
    final notificationType = message.data['type'] ?? 'immediate';

    switch (notificationType) {
      case 'immediate':
        return prefs['immediateNotifications'] ?? true;
      case 'twenty_four_hour':
      case '24h':
        return prefs['twentyFourHourNotifications'] ?? true;
      case 'overdue':
        return prefs['overdueNotifications'] ?? true;
      case 'activity':
      case 'daily_summary':
        return prefs['activityNotifications'] ?? true;
      case 'assignment':
        return prefs['assignmentNotifications'] ?? true;
      default:
        return prefs['immediateNotifications'] ?? true;
    }
  }

  Future<Map<String, bool>> checkPermissions() async {
    final notificationGranted = await Permission.notification.isGranted;
    return {
      'notification': notificationGranted,
    };
  }

  Future<String?> _getCurrentUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('username');
  }

  Future<void> _getAndSaveToken() async {
    final token = await _firebaseMessaging.getToken(vapidKey: kIsWeb ? _webVapidKey : null);
    if (token != null) {
      final username = await _getCurrentUsername();
      if (username != null) {
        await SupabaseService().saveDeviceToken(token, username);
      } else {
      }
    }
  }

  /// Pushes the current device's notification preferences to Supabase so the
  /// backend edge function can skip sending FCM to devices that have opted out.
  Future<void> _syncPreferencesToDevice() async {
    try {
      final token = await _firebaseMessaging.getToken(vapidKey: kIsWeb ? _webVapidKey : null);
      if (token == null) return;
      final prefs = await getNotificationPreferences();
      await SupabaseService().saveDeviceNotificationPreferences(token, prefs);
    } catch (_) {
      // Non-blocking: device falls back to local preference filtering
    }
  }
}

// Background message handler (must be top-level function)
Future<void> _handleBackgroundMessage(RemoteMessage message) async {
  // Note: Background messages don't automatically show notifications on iOS
  // You might need to use local notifications here if needed
}
