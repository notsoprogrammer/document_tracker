import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'config/supabase_config.dart';
import 'services/auto_sync_service.dart';
import 'services/connectivity_service.dart';
import 'services/enhanced_sync_service.dart';
import 'services/notification_service.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();

  // Initialize connectivity service first
  final connectivityService = ConnectivityService();
  await connectivityService.initialize();

  // Check if online
  final isOnline = await connectivityService.isOnline;

  // Initialize Supabase in background with timeout (non-blocking)
  Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
  ).timeout(const Duration(seconds: 10)).catchError((e) {
    debugPrint('Supabase initialization failed or timed out - app will work offline: $e');
  });

  // Initialize auto-sync service (handles offline gracefully)
  await AutoSyncService.initialize();

  // Initialize enhanced sync service for UI status updates
  await EnhancedSyncService().initialize();

  // Initialize notification service
  await NotificationService().initialize();

  runApp(const DocTrackerApp());
}
