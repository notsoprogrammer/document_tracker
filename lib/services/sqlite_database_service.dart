import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';
import '../models/document.dart';

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
    String path = join(documentsDirectory.path, 'documents_v4.db');
    return await openDatabase(
      path,
      version: 4,
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
        created_at TEXT,
        updated_at TEXT
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
  }

  Future<List<Document>> fetchDocuments() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('documents');

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
    docData['local_image_paths'] = jsonEncode(docData['local_image_paths'] ?? []);
    docData['local_file_paths'] = jsonEncode(docData['local_file_paths'] ?? []);
    docData['created_at'] = DateTime.now().toIso8601String();
    docData['updated_at'] = DateTime.now().toIso8601String();

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
    if (updates.containsKey('local_image_paths')) {
      updates['local_image_paths'] = jsonEncode(updates['local_image_paths']);
    }
    if (updates.containsKey('local_file_paths')) {
      updates['local_file_paths'] = jsonEncode(updates['local_file_paths']);
    }
    updates['updated_at'] = DateTime.now().toIso8601String();
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

  Future<void> close() async {
    final db = await database;
    db.close();
  }
}
