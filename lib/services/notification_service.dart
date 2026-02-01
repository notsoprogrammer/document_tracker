import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/supabase_service.dart';

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

    debugPrint('🔔 NotificationService initialized with FCM');
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

    // On web, FirebaseMessaging handles permission internally
    await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<void> requestNotificationPermission() async {
    await _requestNotificationPermission();
  }

  /* -----------------------------------------------------------
   * FCM SETUP
   * ---------------------------------------------------------*/
  Future<void> _initializeFCM() async {
    // Get FCM token and save to Supabase
    final token = await _firebaseMessaging.getToken();
    if (token != null) {
      await SupabaseService().saveDeviceToken(token);
      debugPrint('FCM Token: $token');
    }

    // Listen for token refresh
    _firebaseMessaging.onTokenRefresh.listen((newToken) async {
      await SupabaseService().saveDeviceToken(newToken);
      debugPrint('FCM Token refreshed: $newToken');
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
      // On web, rely on browser push notifications via FCM
      debugPrint('Web notification: $title - $body');
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      icon: '@drawable/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails();

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      notificationDetails,
    );
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
   * NOTIFICATION PREFERENCES
   * ---------------------------------------------------------*/
  Future<void> setNotificationPreferences({
    bool? immediateNotifications,
    bool? nineAMNotifications,
    bool? overdueNotifications,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (immediateNotifications != null) {
      await prefs.setBool('immediate_notifications', immediateNotifications);
    }
    if (nineAMNotifications != null) {
      await prefs.setBool('nine_am_notifications', nineAMNotifications);
    }
    if (overdueNotifications != null) {
      await prefs.setBool('overdue_notifications', overdueNotifications);
    }
  }

  Future<Map<String, bool>> getNotificationPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'immediateNotifications': prefs.getBool('immediate_notifications') ?? false,
      'nineAMNotifications': prefs.getBool('nine_am_notifications') ?? true,
      'overdueNotifications': prefs.getBool('overdue_notifications') ?? true,
    };
  }

  Future<bool> _shouldShowNotification(RemoteMessage message) async {
    final prefs = await getNotificationPreferences();

    // Check notification type from message data
    final data = message.data;
    final notificationType = data['type'] ?? 'immediate'; // Default to immediate if not specified

    switch (notificationType) {
      case 'immediate':
        return prefs['immediateNotifications'] ?? true;
      case '9am':
      case 'nine_am':
        return prefs['nineAMNotifications'] ?? true;
      case 'overdue':
        return prefs['overdueNotifications'] ?? true;
      default:
        // For unknown types, show if immediate notifications are enabled
        return prefs['immediateNotifications'] ?? true;
    }
  }

  Future<Map<String, bool>> checkPermissions() async {
    final notificationGranted = await Permission.notification.isGranted;

    return {
      'notification': notificationGranted,
    };
  }
}

// Background message handler (must be top-level function)
Future<void> _handleBackgroundMessage(RemoteMessage message) async {
  debugPrint('Received background FCM message: ${message.notification?.title}');
  // Note: Background messages don't automatically show notifications on iOS
  // You might need to use local notifications here if needed
}
