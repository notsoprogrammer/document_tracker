import 'dart:async';
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

    // Bring existing calendar entries onto the current reminder rules.
    // Deliberately not awaited — it needs the network and must not hold up
    // app startup.
    unawaited(backfillRemindersIfNeeded());
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
      // Android 14+ withholds SCHEDULE_EXACT_ALARM by default. Without it,
      // every timed reminder silently fails to schedule, so ask for it up
      // front. Reminders still work without it, just less precisely.
      if (!await Permission.scheduleExactAlarm.isGranted) {
        await Permission.scheduleExactAlarm.request();
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

  /// Reminder times shared by activities and calendar documents.
  ///
  /// Both reminders are scheduled, independently of each other:
  ///   • 1 hour before the start time — ALWAYS, whatever the start time is
  ///   • 8:10 AM on the day of the event — the day-ahead heads-up, only when
  ///     that lands before the event actually starts
  ///
  /// These used to be mutually exclusive: an event at/after 8:10 AM returned
  /// only the 8:10 AM time, so the 1-hour-before reminder never fired for
  /// virtually any event.
  ///
  /// Returns the times paired with an id offset so each reminder gets its own
  /// notification id and they don't overwrite one another.
  List<({DateTime time, int idOffset})> _reminderTimesFor(DateTime startTime) {
    final now = DateTime.now();
    final reminders = <({DateTime time, int idOffset})>[];

    // 1 hour before — the reminder the user actually relies on.
    final oneHourBefore = startTime.subtract(const Duration(hours: 1));
    if (oneHourBefore.isAfter(now)) {
      reminders.add((time: oneHourBefore, idOffset: 0));
    }

    // 8:10 AM day-of heads-up, only if it precedes the event and is still
    // ahead of us. Skipped when it would duplicate the 1-hour reminder.
    final eightTen =
        DateTime(startTime.year, startTime.month, startTime.day, 8, 10);
    if (eightTen.isBefore(startTime) &&
        eightTen.isAfter(now) &&
        !eightTen.isAtSameMomentAs(oneHourBefore)) {
      reminders.add((time: eightTen, idOffset: 1));
    }

    return reminders;
  }

  /// Android 14+ does not grant SCHEDULE_EXACT_ALARM by default. Without it,
  /// zonedSchedule with an exact mode throws and — previously — the error was
  /// swallowed, so no reminder was ever delivered. Check first so we can fall
  /// back to an inexact alarm instead of silently dropping the notification.
  Future<bool> _canScheduleExactAlarms() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      return await Permission.scheduleExactAlarm.isGranted;
    } catch (e) {
      return false;
    }
  }

  /// Ask the user for exact-alarm permission. Safe to call more than once;
  /// on Android 14+ this opens the system "Alarms & reminders" screen.
  Future<bool> requestExactAlarmPermission() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final status = await Permission.scheduleExactAlarm.request();
      return status.isGranted;
    } catch (e) {
      debugPrint('NotificationService: exact alarm request failed: $e');
      return false;
    }
  }

  /// Bump this when the reminder rules change, to re-run the backfill below.
  static const int _reminderRulesVersion = 2;
  static const String _prefReminderRulesVersion = 'reminder_rules_version';

  /// Re-schedule reminders for everything still in the future.
  ///
  /// Reminders are normally scheduled once, when an activity or document is
  /// created, so a change to the reminder rules would otherwise only affect
  /// newly created entries — everything already on the calendar would keep the
  /// old (or missing) reminders until it was edited. This backfills them.
  ///
  /// Notification IDs are deterministic, so re-scheduling overwrites the
  /// existing reminder rather than duplicating it. Runs at most once per
  /// rules version; best-effort and never throws.
  Future<void> backfillRemindersIfNeeded() async {
    if (kIsWeb) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final applied = prefs.getInt(_prefReminderRulesVersion) ?? 0;
      if (applied >= _reminderRulesVersion) return;

      debugPrint(
          'NotificationService: backfilling reminders (v$applied -> v$_reminderRulesVersion)');

      final now = DateTime.now();
      int activityCount = 0;
      int documentCount = 0;
      bool allSucceeded = true;

      // Activities — rule reminders are otherwise only set at creation time.
      try {
        final activities = await SupabaseService().fetchActivities();
        for (final activity in activities) {
          if (activity.startTime.isAfter(now)) {
            await scheduleActivityReminder(activity);
            activityCount++;
          }
          // Repeat occurrences reuse the start time's time-of-day.
          for (final extraDate in activity.extraDates) {
            final extraDt = DateTime(
              extraDate.year, extraDate.month, extraDate.day,
              activity.startTime.hour, activity.startTime.minute,
            );
            if (extraDt.isAfter(now)) {
              await scheduleActivityReminder(
                  activity.copyWith(startTime: extraDt));
              activityCount++;
            }
          }
        }
      } catch (e) {
        allSucceeded = false;
        debugPrint('NotificationService: activity backfill failed: $e');
      }

      // Documents that carry a calendar deadline.
      try {
        final documents = await SupabaseService().fetchCalendarDocuments();
        for (final doc in documents) {
          final deadline = doc.calendarDeadline;
          if (deadline != null && deadline.isAfter(now)) {
            await scheduleDocumentReminder(doc);
            documentCount++;
          }
        }
      } catch (e) {
        allSucceeded = false;
        debugPrint('NotificationService: document backfill failed: $e');
      }

      // Only mark done if everything actually fetched, so a run that failed
      // because the device was offline at startup is retried next launch.
      if (allSucceeded) {
        await prefs.setInt(_prefReminderRulesVersion, _reminderRulesVersion);
      }
      debugPrint(
          'NotificationService: backfill ${allSucceeded ? 'done' : 'incomplete, will retry'} '
          '— $activityCount activity, $documentCount document reminder(s)');
    } catch (e) {
      debugPrint('NotificationService: backfill aborted: $e');
    }
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

    final reminders = _reminderTimesFor(startTime);
    if (reminders.isEmpty) return;

    final location = tz.getLocation('Asia/Manila');

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

    // Exact alarms need a permission the user may not have granted. Rather
    // than throwing and losing the reminder entirely, downgrade to an inexact
    // alarm — a few minutes of drift beats no notification at all.
    final exact = await _canScheduleExactAlarms();
    final scheduleMode = exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    for (final reminder in reminders) {
      final tzReminder = tz.TZDateTime.from(reminder.time, location);

      // Stable ID from the start time, a salt per source (activity vs
      // document), and an offset per reminder kind so the 1-hour and 8:10 AM
      // reminders don't overwrite each other.
      final notifId = (startTime.millisecondsSinceEpoch ~/ 1000 +
              idSalt +
              reminder.idOffset * 7919) &
          0x7FFFFFFF;

      try {
        await _plugin.zonedSchedule(
          notifId,
          title ?? 'Upcoming Event',
          _reminderBody(startTime, reminder.time),
          tzReminder,
          notifDetails,
          androidScheduleMode: scheduleMode,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      } catch (e) {
        // Surface the failure instead of silently dropping the reminder.
        debugPrint(
            'NotificationService: failed to schedule reminder for $startTime '
            'at ${reminder.time} (exact: $exact): $e');
      }
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

    final exact = await _canScheduleExactAlarms();

    try {
      await _plugin.zonedSchedule(
        notifId,
        title ?? 'Upcoming Event',
        'Starting in $minutesBefore minutes',
        tzReminder,
        notifDetails,
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint(
          'NotificationService: failed to schedule $minutesBefore-min reminder '
          'for $startTime (exact: $exact): $e');
    }
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
