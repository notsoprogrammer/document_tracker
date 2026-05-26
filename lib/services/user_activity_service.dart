import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../services/auth_service.dart';

class UserActivityService {
  static final UserActivityService _instance = UserActivityService._internal();
  factory UserActivityService() => _instance;
  UserActivityService._internal();

  Database? _database;

  Future<Database> get _db async {
    _database ??= await _openDb();
    return _database!;
  }

  Future<Database> _openDb() async {
    Directory dir = await getApplicationDocumentsDirectory();
    String path = join(dir.path, 'user_activity.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE user_sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT NOT NULL,
            login_time TEXT NOT NULL,
            last_seen TEXT NOT NULL,
            login_method TEXT NOT NULL DEFAULT 'login'
          )
        ''');
        await db.execute('''
          CREATE TABLE user_activity_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT NOT NULL,
            action TEXT NOT NULL,
            screen TEXT,
            details TEXT,
            timestamp TEXT NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX idx_sessions_username ON user_sessions(username)');
        await db.execute('CREATE INDEX idx_logs_username ON user_activity_logs(username)');
      },
    );
  }

  String _now() => DateTime.now().toIso8601String();

  Future<void> logAppOpen({required String username, required String method}) async {
    final db = await _db;
    final now = _now();
    await db.insert('user_sessions', {
      'username': username,
      'login_time': now,
      'last_seen': now,
      'login_method': method,
    });
    await _log(db, username: username, action: 'App opened', screen: 'Home', details: 'Method: $method');
  }

  Future<void> updateLastSeen(String username) async {
    final db = await _db;
    final sessions = await db.query(
      'user_sessions',
      where: 'username = ?',
      whereArgs: [username],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (sessions.isNotEmpty) {
      await db.update(
        'user_sessions',
        {'last_seen': _now()},
        where: 'id = ?',
        whereArgs: [sessions.first['id']],
      );
    }
  }

  Future<void> logAction({
    required String action,
    String? screen,
    String? details,
  }) async {
    final username = await AuthService.getUsername() ?? 'unknown';
    final db = await _db;
    await _log(db, username: username, action: action, screen: screen, details: details);
    await updateLastSeen(username);
  }

  Future<void> _log(Database db, {
    required String username,
    required String action,
    String? screen,
    String? details,
  }) async {
    await db.insert('user_activity_logs', {
      'username': username,
      'action': action,
      'screen': screen,
      'details': details,
      'timestamp': _now(),
    });
  }

  // Returns today's active users — naturally resets each day.
  Future<List<Map<String, dynamic>>> fetchUserSessions() async {
    final db = await _db;
    final today = DateTime.now();
    final todayPrefix =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    return await db.rawQuery('''
      SELECT
        username,
        COUNT(*) as session_count,
        MIN(login_time) as first_open,
        MAX(last_seen) as last_seen
      FROM user_sessions
      WHERE substr(login_time, 1, 10) = ?
      GROUP BY username
      ORDER BY last_seen DESC
    ''', [todayPrefix]);
  }

  Future<List<Map<String, dynamic>>> fetchSessionsForUser(String username) async {
    final db = await _db;
    return await db.query(
      'user_sessions',
      where: 'username = ?',
      whereArgs: [username],
      orderBy: 'login_time DESC',
    );
  }

  Future<List<Map<String, dynamic>>> fetchLatestActivityPerUser() async {
    final db = await _db;
    return await db.rawQuery('''
      SELECT l.username, l.action, l.screen, l.details, l.timestamp
      FROM user_activity_logs l
      INNER JOIN (
        SELECT username, MAX(id) AS max_id
        FROM user_activity_logs
        GROUP BY username
      ) m ON l.id = m.max_id
      ORDER BY l.timestamp DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> fetchActivityLogs({String? username, int limit = 200}) async {
    final db = await _db;
    if (username != null) {
      return await db.query(
        'user_activity_logs',
        where: 'username = ?',
        whereArgs: [username],
        orderBy: 'timestamp DESC',
        limit: limit,
      );
    }
    return await db.query(
      'user_activity_logs',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
  }

  // Returns per-day summaries of users with at least 30 seconds of interaction.
  // Each row: { day, username, session_count, total_seconds }
  Future<List<Map<String, dynamic>>> fetchDailySummary() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT
        date(login_time) AS day,
        username,
        COUNT(*) AS session_count,
        CAST(SUM(
          MAX(0, (julianday(last_seen) - julianday(login_time)) * 86400)
        ) AS INTEGER) AS total_seconds
      FROM user_sessions
      WHERE (julianday(last_seen) - julianday(login_time)) * 86400 >= 30
      GROUP BY date(login_time), username
      ORDER BY day DESC, username ASC
    ''');
    return rows;
  }

  Future<DateTime?> getLastSessionTime(String username) async {
    final db = await _db;
    final rows = await db.query(
      'user_sessions',
      columns: ['login_time'],
      where: 'username = ?',
      whereArgs: [username],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DateTime.parse(rows.first['login_time'] as String);
  }

  Future<void> clearAllLogs() async {
    final db = await _db;
    await db.delete('user_activity_logs');
    await db.delete('user_sessions');
  }
}
