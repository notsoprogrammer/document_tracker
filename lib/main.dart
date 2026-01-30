import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'config/supabase_config.dart';
import 'services/auto_sync_service.dart';
import 'services/connectivity_service.dart';
import 'services/enhanced_sync_service.dart';
import 'services/notification_service.dart';
import 'app.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive_flutter/hive_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive for web builds (uses IndexedDB)
  // Mobile builds continue using SQLite via sqflite
  if (kIsWeb) {
    await Hive.initFlutter();
    await Hive.openBox('mydb');
  }

  await Firebase.initializeApp();

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
