import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'services/auto_sync_service.dart';
import 'services/connectivity_service.dart';
import 'services/enhanced_sync_service.dart';
import 'services/notification_service.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
  );

  // Initialize connectivity service
  await ConnectivityService().initialize();

  // Initialize auto-sync service
  await AutoSyncService.initialize();

  // Initialize enhanced sync service for UI status updates
  await EnhancedSyncService().initialize();

  // Initialize notification service
  await NotificationService().initialize();

  runApp(const DocTrackerApp());
}
