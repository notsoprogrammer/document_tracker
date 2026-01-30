import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; // <-- add this
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

  if (kIsWeb) {
    await Hive.initFlutter();
    await Hive.openBox('mydb');
  }

  // ✅ Correct Firebase initialization
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
  );

  await ConnectivityService().initialize();
  await AutoSyncService.initialize();
  await EnhancedSyncService().initialize();
  await NotificationService().initialize();

  runApp(const DocTrackerApp());
}