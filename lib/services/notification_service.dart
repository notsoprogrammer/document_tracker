import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  /// Channel constants
  static const String _channelId = 'compliance_channel';
  static const String _channelName = 'Compliance Notifications';
  static const String _channelDesc =
      'Notifications for document compliance deadlines';

  /// Preference keys
  static const String _prefImmediate = 'immediate_notifications';
  static const String _prefNineAM = 'nine_am_notifications';
  static const String _prefOverdue = 'overdue_notifications';
  static const String _prefActivity = 'activity_notifications';
  static const String _prefActivityLastShown = 'activity_notification_last_shown';

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
      final token = await _firebaseMessaging.getToken();
      if (token != null) {
        final username = await _getCurrentUsername();
        if (username != null) {
          await SupabaseService().saveDeviceToken(token, username);
          debugPrint('FCM Token: $token for user: $username');
        } else {
          debugPrint('No username found, skipping device token save');
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
        debugPrint('FCM Token refreshed: $newToken for user: $username');
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
    debugPrint('Received foreground FCM message: ${message.notification?.title}');

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
        debugPrint('Notification suppressed due to user preferences');
      }
    }
  }

  Future<void> _handleMessageOpenedApp(RemoteMessage message) async {
    debugPrint('App opened from FCM message: ${message.notification?.title}');
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
      debugPrint('flutter_local_notifications show failed: $e');
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
    debugPrint('FCM: Compliance notifications will be handled by backend for $documentCode');
    return []; // Return empty list since no local IDs
  }

  Future<void> cancelAll(List<int> ids) async {
    // No-op since we don't schedule local notifications anymore
    debugPrint('FCM: No local notifications to cancel');
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
   * NOTIFICATION PREFERENCES
   * ---------------------------------------------------------*/
  Future<void> setNotificationPreferences({
    bool? immediateNotifications,
    bool? nineAMNotifications,
    bool? overdueNotifications,
    bool? activityNotifications,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (immediateNotifications != null) {
      await prefs.setBool(_prefImmediate, immediateNotifications);
    }
    if (nineAMNotifications != null) {
      await prefs.setBool(_prefNineAM, nineAMNotifications);
    }
    if (overdueNotifications != null) {
      await prefs.setBool(_prefOverdue, overdueNotifications);
    }
    if (activityNotifications != null) {
      await prefs.setBool(_prefActivity, activityNotifications);
    }

    // Sync preferences to Supabase so the backend can filter per device
    await _syncPreferencesToDevice();

    if ((immediateNotifications == true) || (nineAMNotifications == true) || (overdueNotifications == true)) {
      await _getAndSaveToken();
    }
  }

  Future<Map<String, bool>> getNotificationPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'immediateNotifications': prefs.getBool(_prefImmediate) ?? false,
      'nineAMNotifications': prefs.getBool(_prefNineAM) ?? true,
      'overdueNotifications': prefs.getBool(_prefOverdue) ?? true,
      'activityNotifications': prefs.getBool(_prefActivity) ?? true,
    };
  }

  Future<bool> _shouldShowNotification(RemoteMessage message) async {
    final prefs = await getNotificationPreferences();
    final notificationType = message.data['type'] ?? 'immediate';

    switch (notificationType) {
      case 'immediate':
        return prefs['immediateNotifications'] ?? true;
      case '9am':
      case 'nine_am':
        return prefs['nineAMNotifications'] ?? true;
      case 'overdue':
        return prefs['overdueNotifications'] ?? true;
      case 'activity':
        return prefs['activityNotifications'] ?? true;
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
    final token = await _firebaseMessaging.getToken();
    if (token != null) {
      final username = await _getCurrentUsername();
      if (username != null) {
        await SupabaseService().saveDeviceToken(token, username);
        debugPrint('FCM Token: $token for user: $username');
      } else {
        debugPrint('No username found, skipping device token save');
      }
    }
  }

  /// Pushes the current device's notification preferences to Supabase so the
  /// backend edge function can skip sending FCM to devices that have opted out.
  Future<void> _syncPreferencesToDevice() async {
    try {
      final token = await _firebaseMessaging.getToken();
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
  debugPrint('Received background FCM message: ${message.notification?.title}');
  // Note: Background messages don't automatically show notifications on iOS
  // You might need to use local notifications here if needed
}
