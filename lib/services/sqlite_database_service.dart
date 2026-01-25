import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';
import '../models/document.dart';
import '../models/activity.dart';
import '../utils/date_time_utils.dart';

class SQLiteDatabaseService {
  static final SQLiteDatabaseService _instance = SQLiteDatabaseService._internal();
  factory SQLiteDatabaseService() => _instance;
  SQLiteDatabaseService._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, 'documents_v8.db');
    return await openDatabase(
      path,
      version: 14,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }
  Future<void> _onCreate(Database db, int version) async {
    // Documents table
    await db.execute('''
      CREATE TABLE documents (
        code TEXT PRIMARY KEY,
        title TEXT,
        type TEXT,
        from_or_to TEXT,
        mode TEXT,
        addressed_to TEXT,
        file_path TEXT,
        remarks TEXT,
        person TEXT,
        incoming INTEGER,
        status TEXT,
        image_urls TEXT,
        file_urls TEXT,
        local_image_paths TEXT,
        local_file_paths TEXT,
        needs_sync INTEGER,
        deleted_pending_sync INTEGER DEFAULT 0,
        created_at TEXT,
        updated_at TEXT,
        compliance_deadline TEXT,
        scheduled_notification_ids TEXT,
        compliance_assignee TEXT,
        category TEXT
      )
    ''');

    // History entries table
    await db.execute('''
      CREATE TABLE history_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        document_code TEXT,
        action TEXT,
        person TEXT,
        timestamp TEXT,
        notes TEXT,
        personnel TEXT,
        FOREIGN KEY (document_code) REFERENCES documents (code)
      )
    ''');

    // Pending deletions table
    await db.execute('''
      CREATE TABLE pending_deletions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        deleted_by TEXT NOT NULL,
        doc_code TEXT NOT NULL,
        title TEXT NOT NULL,
        deleted_at TEXT NOT NULL,
        synced INTEGER DEFAULT 0
      )
    ''');

    // Notifications history table
    await db.execute('''
      CREATE TABLE notifications_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        document_code TEXT NOT NULL,
        notification_type TEXT NOT NULL,
        notification_id INTEGER NOT NULL,
        scheduled_time TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'scheduled',
        created_at TEXT NOT NULL,
        FOREIGN KEY (document_code) REFERENCES documents (code)
      )
    ''');

    // Activities table
    await db.execute('''
      CREATE TABLE activities (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        start_time TEXT NOT NULL,
        end_time TEXT,
        people_involved TEXT NOT NULL,
        remarks TEXT NOT NULL,
        person TEXT NOT NULL,
        location TEXT,
        needs_sync INTEGER DEFAULT 0,
        created_at TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add needs_sync column to existing documents table
      await db.execute('ALTER TABLE documents ADD COLUMN needs_sync INTEGER DEFAULT 0');
    }
    if (oldVersion < 4) {
      // Add local file path columns for offline uploads
      try {
        await db.execute('ALTER TABLE documents ADD COLUMN local_image_paths TEXT');
      } catch (e) {
        // Column might already exist
      }
      try {
        await db.execute('ALTER TABLE documents ADD COLUMN local_file_paths TEXT');
      } catch (e) {
        // Column might already exist
      }
    }
    if (oldVersion < 5) {
      // Add deleted_pending_sync column to documents table
      try {
        await db.execute('ALTER TABLE documents ADD COLUMN deleted_pending_sync INTEGER DEFAULT 0');
      } catch (e) {
        // Column might already exist
      }

      // Create pending_deletions table
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS pending_deletions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            deleted_by TEXT NOT NULL,
            doc_code TEXT NOT NULL,
            title TEXT NOT NULL,
            deleted_at TEXT NOT NULL,
            synced INTEGER DEFAULT 0
          )
        ''');
      } catch (e) {
        // Table might already exist
      }
    }
    if (oldVersion < 6) {
      // Add compliance deadline and notification IDs columns
      try {
        await db.execute('ALTER TABLE documents ADD COLUMN compliance_deadline TEXT');
      } catch (e) {
        // Column might already exist
      }
      try {
        await db.execute('ALTER TABLE documents ADD COLUMN scheduled_notification_ids TEXT');
      } catch (e) {
        // Column might already exist
      }
    }
    if (oldVersion < 8) {
      // Add compliance assignee column
      try {
        await db.execute('ALTER TABLE documents ADD COLUMN compliance_assignee TEXT');
      } catch (e) {
        // Column might already exist
      }
    }
    if (oldVersion < 9) {
      // Create notifications_history table
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS notifications_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            document_code TEXT NOT NULL,
            notification_type TEXT NOT NULL,
            scheduled_time TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'scheduled',
            created_at TEXT NOT NULL,
            FOREIGN KEY (document_code) REFERENCES documents (code)
          )
        ''');
      } catch (e) {
        // Table might already exist
      }
    }
    if (oldVersion < 10) {
      // Add category column to documents table
      try {
        await db.execute('ALTER TABLE documents ADD COLUMN category TEXT');
      } catch (e) {
        // Column might already exist
      }
    }
    if (oldVersion < 11) {
      // Add calendar columns to documents table
      try {
        await db.execute('ALTER TABLE documents ADD COLUMN calendar_deadline TEXT');
      } catch (e) {
        // Column might already exist
      }
      try {
        await db.execute('ALTER TABLE documents ADD COLUMN calendar_added INTEGER DEFAULT 0');
      } catch (e) {
        // Column might already exist
      }
      try {
        await db.execute('ALTER TABLE documents ADD COLUMN attachments TEXT');
      } catch (e) {
        // Column might already exist
      }
    }
    if (oldVersion < 12) {
      // Create activities table (drop old if exists)
      try {
        await db.execute('DROP TABLE IF EXISTS activities');
        await db.execute('''
          CREATE TABLE activities (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT,
            start_time TEXT NOT NULL,
            end_time TEXT,
            people_involved TEXT NOT NULL,
            remarks TEXT NOT NULL,
            person TEXT NOT NULL,
            location TEXT,
            needs_sync INTEGER DEFAULT 0,
            created_at TEXT
          )
        ''');
      } catch (e) {
        // Table might already exist
      }
    }
    if (oldVersion < 13) {
      // Recreate activities table with correct schema (drop old if exists)
      try {
        await db.execute('DROP TABLE IF EXISTS activities');
        await db.execute('''
          CREATE TABLE activities (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT,
            start_time TEXT NOT NULL,
            end_time TEXT,
            people_involved TEXT NOT NULL,
            remarks TEXT NOT NULL,
            person TEXT NOT NULL,
            location TEXT,
            needs_sync INTEGER DEFAULT 0,
            created_at TEXT
          )
        ''');
      } catch (e) {
        // Table might already exist
      }
    }
    if (oldVersion < 14) {
      // Add file_names column to documents table
      try {
        await db.execute('ALTER TABLE documents ADD COLUMN file_names TEXT');
      } catch (e) {
        // Column might already exist
      }
    }
  }

  Future<List<Document>> fetchDocuments() async {
    final db = await database;
    // Exclude documents marked as deleted_pending_sync
    final List<Map<String, dynamic>> maps = await db.query(
      'documents',
      where: 'deleted_pending_sync = ?',
      whereArgs: [0],
    );

    List<Document> documents = [];
    for (var map in maps) {
      final history = await fetchHistory(map['code']);
      documents.add(Document.fromJson(map)..history.addAll(history));
    }

    return documents;
  }

  Future<Document> createDocument(Document document) async {
    final db = await database;
    final docData = document.toJson();
    // Convert boolean to integer for SQLite (handle both bool and int)
    docData['incoming'] = (docData['incoming'] == true || docData['incoming'] == 1) ? 1 : 0;
    // Convert lists to JSON strings for SQLite
    docData['image_urls'] = jsonEncode(docData['image_urls']);
    docData['file_urls'] = jsonEncode(docData['file_urls']);
    docData['file_names'] = jsonEncode(docData['file_names'] ?? []);
    docData['local_image_paths'] = jsonEncode(docData['local_image_paths'] ?? []);
    docData['local_file_paths'] = jsonEncode(docData['local_file_paths'] ?? []);
    docData['attachments'] = jsonEncode(docData['attachments'] ?? []);
    docData['calendar_added'] = (docData['calendar_added'] == true || docData['calendar_added'] == 1) ? 1 : 0;
    docData['created_at'] = getPhilippineTime().toIso8601String();
    docData['updated_at'] = getPhilippineTime().toIso8601String();

    await db.insert('documents', docData, conflictAlgorithm: ConflictAlgorithm.replace);

    // Add history entries
    for (var entry in document.history) {
      await addHistoryEntry(document.code, entry);
    }

    return document;
  }

  Future<void> updateDocument(String documentCode, Map<String, dynamic> updates) async {
    final db = await database;
    // Convert boolean to integer for SQLite if present
    if (updates.containsKey('incoming')) {
      updates['incoming'] = (updates['incoming'] == true || updates['incoming'] == 1) ? 1 : 0;
    }
    if (updates.containsKey('needs_sync')) {
      updates['needs_sync'] = (updates['needs_sync'] == true || updates['needs_sync'] == 1) ? 1 : 0;
    }
    // Convert lists to JSON strings for SQLite if present
    if (updates.containsKey('image_urls')) {
      updates['image_urls'] = jsonEncode(updates['image_urls']);
    }
    if (updates.containsKey('file_urls')) {
      updates['file_urls'] = jsonEncode(updates['file_urls']);
    }
    if (updates.containsKey('file_names')) {
      updates['file_names'] = jsonEncode(updates['file_names']);
    }
    if (updates.containsKey('local_image_paths')) {
      updates['local_image_paths'] = jsonEncode(updates['local_image_paths']);
    }
    if (updates.containsKey('local_file_paths')) {
      updates['local_file_paths'] = jsonEncode(updates['local_file_paths']);
    }
    if (updates.containsKey('scheduled_notification_ids')) {
      updates['scheduled_notification_ids'] = jsonEncode(updates['scheduled_notification_ids']);
    }
    if (updates.containsKey('attachments')) {
      updates['attachments'] = jsonEncode(updates['attachments']);
    }
    if (updates.containsKey('calendar_added')) {
      updates['calendar_added'] = (updates['calendar_added'] == true || updates['calendar_added'] == 1) ? 1 : 0;
    }
    updates['updated_at'] = getPhilippineTime().toIso8601String();
    await db.update('documents', updates, where: 'code = ?', whereArgs: [documentCode]);
  }

  Future<void> deleteDocument(String documentCode) async {
    final db = await database;
    await db.delete('history_entries', where: 'document_code = ?', whereArgs: [documentCode]);
    await db.delete('documents', where: 'code = ?', whereArgs: [documentCode]);
  }

  Future<void> addHistoryEntry(String documentCode, HistoryEntry entry, {String? personnel}) async {
    final db = await database;
    await db.insert('history_entries', {
      'document_code': documentCode,
      'action': entry.action,
      'person': entry.person,
      'timestamp': entry.timestamp.toIso8601String(),
      'notes': entry.notes,
      'personnel': personnel ?? entry.person,
    });
  }

  Future<List<HistoryEntry>> fetchHistory(String documentCode) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'history_entries',
      where: 'document_code = ?',
      whereArgs: [documentCode],
      orderBy: 'timestamp ASC',
    );

    return maps.map((map) => HistoryEntry.fromJson(map)).toList();
  }

  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('history_entries');
    await db.delete('documents');
  }

  // Pending deletions methods
  Future<void> addPendingDeletion({
    required String deletedBy,
    required String docCode,
    required String title,
  }) async {
    final db = await database;
    await db.insert('pending_deletions', {
      'deleted_by': deletedBy,
      'doc_code': docCode,
      'title': title,
      'deleted_at': getPhilippineTime().toIso8601String(),
      'synced': 0,
    });
  }

  Future<List<Map<String, dynamic>>> getPendingDeletions() async {
    final db = await database;
    return await db.query(
      'pending_deletions',
      where: 'synced = ?',
      whereArgs: [0],
    );
  }

  Future<void> markDeletionAsSynced(int deletionId) async {
    final db = await database;
    await db.update(
      'pending_deletions',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [deletionId],
    );
  }

  Future<void> markDocumentAsDeletedPending(String documentCode) async {
    final db = await database;
    await db.update(
      'documents',
      {'deleted_pending_sync': 1},
      where: 'code = ?',
      whereArgs: [documentCode],
    );
  }

  Future<void> deletePendingDeletionRecord(int deletionId) async {
    final db = await database;
    await db.delete(
      'pending_deletions',
      where: 'id = ?',
      whereArgs: [deletionId],
    );
  }

  Future<void> close() async {
    final db = await database;
    db.close();
  }

  // Notifications history methods
  Future<void> addNotificationHistory({
    required String documentCode,
    required String notificationType,
    required int notificationId,
    required DateTime scheduledTime,
    String status = 'scheduled',
  }) async {
    final db = await database;
    await db.insert('notifications_history', {
      'document_code': documentCode,
      'notification_type': notificationType,
      'notification_id': notificationId,
      'scheduled_time': scheduledTime.toIso8601String(),
      'status': status,
      'created_at': getPhilippineTime().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> fetchNotificationsHistory() async {
    final db = await database;
    return await db.query(
      'notifications_history',
      orderBy: 'created_at DESC',
    );
  }

  Future<void> updateNotificationStatus(int id, String status) async {
    final db = await database;
    await db.update(
      'notifications_history',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateNotificationStatusByNotificationId(int notificationId, String status) async {
    final db = await database;
    await db.update(
      'notifications_history',
      {'status': status},
      where: 'notification_id = ?',
      whereArgs: [notificationId],
    );
  }

  Future<void> updateNotificationsStatusByDocumentCode(String documentCode, String status) async {
    final db = await database;
    await db.update(
      'notifications_history',
      {'status': status},
      where: 'document_code = ?',
      whereArgs: [documentCode],
    );
  }

  Future<void> deleteOldNotifications() async {
    final db = await database;
    final oneMonthAgo = getPhilippineTime().subtract(const Duration(days: 30));
    await db.delete(
      'notifications_history',
      where: 'created_at < ?',
      whereArgs: [oneMonthAgo.toIso8601String()],
    );
  }

  // Activities methods
  Future<List<Activity>> fetchActivities() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('activities');

    return maps.map((map) => Activity.fromJson(map)).toList();
  }

  Future<Activity> createActivity(Activity activity) async {
    final db = await database;
    final actData = activity.toJson();
    actData.remove('id'); // Remove id for AUTOINCREMENT
    actData['needs_sync'] = (actData['needs_sync'] == true || actData['needs_sync'] == 1) ? 1 : 0;
    actData['created_at'] = getPhilippineTime().toIso8601String();

    final id = await db.insert('activities', actData, conflictAlgorithm: ConflictAlgorithm.replace);

    return activity.copyWith(id: id);
  }

  Future<void> updateActivity(int activityId, Map<String, dynamic> updates) async {
    final db = await database;
    if (updates.containsKey('needs_sync')) {
      updates['needs_sync'] = (updates['needs_sync'] == true || updates['needs_sync'] == 1) ? 1 : 0;
    }
    await db.update('activities', updates, where: 'id = ?', whereArgs: [activityId]);
  }

  Future<void> deleteActivity(int activityId) async {
    final db = await database;
    await db.delete('activities', where: 'id = ?', whereArgs: [activityId]);
  }
}
