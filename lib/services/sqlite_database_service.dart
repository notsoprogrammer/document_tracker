// Conditional import to choose the correct database service implementation
// Mobile platforms (Android, iOS) use SQLite via sqflite
// Web platform uses Hive for key-value storage in IndexedDB
import 'sqlite_database_service_mobile.dart'
    if (dart.library.html) 'sqlite_database_service_web.dart';

// Re-export the class
export 'sqlite_database_service_mobile.dart'
    if (dart.library.html) 'sqlite_database_service_web.dart';
