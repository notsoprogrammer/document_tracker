import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';

class UserActivityService {
  static final UserActivityService _instance = UserActivityService._internal();
  factory UserActivityService() => _instance;
  UserActivityService._internal();

  Database? _database;
  int? _remoteSessionId;
  DateTime? _lastPurgeDate;

  SupabaseClient get _supabase => Supabase.instance.client;

  Future<Database> get _db async {
    _database ??= await _openDb();
    return _database!;
  }

  Future<Database> _openDb() async {
    Directory dir = await getApplicationDocumentsDirectory();
    String path = join(dir.path, 'user_activity.db');
    return await openDatabase(
      path,
      version: 2,
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
        await db.execute('''
          CREATE TABLE user_daily_summary (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT NOT NULL,
            date TEXT NOT NULL,
            session_count INTEGER NOT NULL DEFAULT 0,
            total_seconds INTEGER NOT NULL DEFAULT 0,
            UNIQUE(username, date)
          )
        ''');
        await db.execute('CREATE INDEX idx_sessions_username ON user_sessions(username)');
        await db.execute('CREATE INDEX idx_logs_username ON user_activity_logs(username)');
        await db.execute('CREATE INDEX idx_daily_summary_date ON user_daily_summary(date)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS user_daily_summary (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              username TEXT NOT NULL,
              date TEXT NOT NULL,
              session_count INTEGER NOT NULL DEFAULT 0,
              total_seconds INTEGER NOT NULL DEFAULT 0,
              UNIQUE(username, date)
            )
          ''');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_daily_summary_date ON user_daily_summary(date)');
        }
      },
    );
  }

  String _now() => DateTime.now().toIso8601String();

  String _todayPrefix() {
    final t = DateTime.now();
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  String _tomorrowPrefix() {
    final t = DateTime.now().add(const Duration(days: 1));
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  Future<void> _tryRemote(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e) {
    }
  }

  // Summarizes old sessions into user_daily_summary, then deletes raw logs older than today.
  // Runs at most once per app session.
  Future<void> _maybePurgeOldData() async {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    if (_lastPurgeDate == todayDate) return;
    _lastPurgeDate = todayDate;

    await _purgeLocal();
    await _tryRemote(_purgeRemote);
  }

  Future<void> _purgeLocal() async {
    final db = await _db;
    final todayPrefix = _todayPrefix();

    final oldSessions = await db.query(
      'user_sessions',
      where: 'substr(login_time, 1, 10) < ?',
      whereArgs: [todayPrefix],
    );

    if (oldSessions.isNotEmpty) {
      final summary = _aggregateSessions(oldSessions);
      final days = summary.values.map((r) => r['date'] as String).toSet();

      for (final day in days) {
        await db.delete('user_daily_summary', where: 'date = ?', whereArgs: [day]);
      }
      for (final row in summary.values) {
        await db.insert('user_daily_summary', row, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      await db.delete('user_sessions', where: 'substr(login_time, 1, 10) < ?', whereArgs: [todayPrefix]);
      await db.delete('user_activity_logs', where: 'substr(timestamp, 1, 10) < ?', whereArgs: [todayPrefix]);
    }
  }

  Future<void> _purgeRemote() async {
    final todayPrefix = _todayPrefix();

    final oldSessions = await _supabase
        .from('user_sessions')
        .select('username, login_time, last_seen')
        .lt('login_time', '${todayPrefix}T00:00:00');

    if ((oldSessions as List).isNotEmpty) {
      final summary = _aggregateSessions(oldSessions.cast<Map<String, dynamic>>());
      final days = summary.values.map((r) => r['date'] as String).toSet();

      for (final day in days) {
        await _supabase.from('user_daily_summary').delete().eq('date', day);
      }
      await _supabase.from('user_daily_summary').insert(summary.values.toList());

      await _supabase.from('user_sessions').delete().lt('login_time', '${todayPrefix}T00:00:00');
      await _supabase.from('user_activity_logs').delete().lt('timestamp', '${todayPrefix}T00:00:00');
    }
  }

  Map<String, Map<String, dynamic>> _aggregateSessions(List<Map<String, dynamic>> rows) {
    final Map<String, Map<String, dynamic>> summary = {};
    for (final row in rows) {
      final loginTime = DateTime.parse(row['login_time'] as String);
      final lastSeen = DateTime.parse(row['last_seen'] as String);
      final seconds = lastSeen.difference(loginTime).inSeconds.clamp(0, 86400);
      if (seconds < 30) continue;

      final day =
          '${loginTime.year}-${loginTime.month.toString().padLeft(2, '0')}-${loginTime.day.toString().padLeft(2, '0')}';
      final key = '$day|${row['username']}';

      summary.putIfAbsent(key, () => {
        'username': row['username'],
        'date': day,
        'session_count': 0,
        'total_seconds': 0,
      });
      summary[key]!['session_count'] = (summary[key]!['session_count'] as int) + 1;
      summary[key]!['total_seconds'] = (summary[key]!['total_seconds'] as int) + seconds;
    }
    return summary;
  }

  Future<void> logAppOpen({required String username, required String method}) async {
    await _maybePurgeOldData();

    final db = await _db;
    final now = _now();
    await db.insert('user_sessions', {
      'username': username,
      'login_time': now,
      'last_seen': now,
      'login_method': method,
    });
    await _log(db, username: username, action: 'App opened', screen: 'Home', details: 'Method: $method');

    await _tryRemote(() async {
      final response = await _supabase.from('user_sessions').insert({
        'username': username,
        'login_time': now,
        'last_seen': now,
        'login_method': method,
      }).select('id').single();
      _remoteSessionId = response['id'] as int;

      await _supabase.from('user_activity_logs').insert({
        'username': username,
        'action': 'App opened',
        'screen': 'Home',
        'details': 'Method: $method',
        'timestamp': now,
      });
    });
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

    if (_remoteSessionId != null) {
      await _tryRemote(() async {
        await _supabase
            .from('user_sessions')
            .update({'last_seen': _now()})
            .eq('id', _remoteSessionId!);
      });
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

    await _tryRemote(() async {
      await _supabase.from('user_activity_logs').insert({
        'username': username,
        'action': action,
        'screen': screen,
        'details': details,
        'timestamp': _now(),
      });
    });
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

  // --- Read methods: Supabase first, local SQLite fallback ---

  Future<List<Map<String, dynamic>>> fetchUserSessions() async {
    try {
      final todayPrefix = _todayPrefix();
      final tomorrowPrefix = _tomorrowPrefix();

      final rows = await _supabase
          .from('user_sessions')
          .select('username, login_time, last_seen')
          .gte('login_time', '${todayPrefix}T00:00:00')
          .lt('login_time', '${tomorrowPrefix}T00:00:00')
          .order('last_seen', ascending: false);

      final Map<String, Map<String, dynamic>> grouped = {};
      for (final row in (rows as List<dynamic>).cast<Map<String, dynamic>>()) {
        final username = row['username'] as String;
        if (!grouped.containsKey(username)) {
          grouped[username] = {
            'username': username,
            'session_count': 1,
            'first_open': row['login_time'],
            'last_seen': row['last_seen'],
          };
        } else {
          grouped[username]!['session_count'] = (grouped[username]!['session_count'] as int) + 1;
          if ((row['login_time'] as String).compareTo(grouped[username]!['first_open'] as String) < 0) {
            grouped[username]!['first_open'] = row['login_time'];
          }
          if ((row['last_seen'] as String).compareTo(grouped[username]!['last_seen'] as String) > 0) {
            grouped[username]!['last_seen'] = row['last_seen'];
          }
        }
      }

      return grouped.values.toList()
        ..sort((a, b) => (b['last_seen'] as String).compareTo(a['last_seen'] as String));
    } catch (e) {
      return _fetchUserSessionsLocal();
    }
  }

  Future<List<Map<String, dynamic>>> _fetchUserSessionsLocal() async {
    final db = await _db;
    final todayPrefix = _todayPrefix();
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
    try {
      final rows = await _supabase
          .from('user_sessions')
          .select('*')
          .eq('username', username)
          .order('login_time', ascending: false);
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (e) {
      final db = await _db;
      return await db.query(
        'user_sessions',
        where: 'username = ?',
        whereArgs: [username],
        orderBy: 'login_time DESC',
      );
    }
  }

  Future<List<Map<String, dynamic>>> fetchLatestActivityPerUser() async {
    try {
      final rows = await _supabase
          .from('user_activity_logs')
          .select('username, action, screen, details, timestamp')
          .order('timestamp', ascending: false)
          .limit(1000);

      final Map<String, Map<String, dynamic>> latest = {};
      for (final row in (rows as List<dynamic>).cast<Map<String, dynamic>>()) {
        final username = row['username'] as String;
        if (!latest.containsKey(username)) {
          latest[username] = Map<String, dynamic>.from(row);
        }
      }

      return latest.values.toList()
        ..sort((a, b) => (b['timestamp'] as String).compareTo(a['timestamp'] as String));
    } catch (e) {
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
  }

  Future<List<Map<String, dynamic>>> fetchActivityLogs({String? username, int limit = 200}) async {
    try {
      final result = username != null
          ? await _supabase
              .from('user_activity_logs')
              .select('username, action, screen, details, timestamp')
              .eq('username', username)
              .order('timestamp', ascending: false)
              .limit(limit)
          : await _supabase
              .from('user_activity_logs')
              .select('username, action, screen, details, timestamp')
              .order('timestamp', ascending: false)
              .limit(limit);
      return List<Map<String, dynamic>>.from(result as List);
    } catch (e) {
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
  }

  // Daily tab: historical summaries + today's live data computed from user_sessions.
  Future<List<Map<String, dynamic>>> fetchDailySummary() async {
    try {
      final todayPrefix = _todayPrefix();
      final tomorrowPrefix = _tomorrowPrefix();

      final historyRows = await _supabase
          .from('user_daily_summary')
          .select('username, date, session_count, total_seconds')
          .order('date', ascending: false)
          .order('username', ascending: true);

      final todayRows = await _supabase
          .from('user_sessions')
          .select('username, login_time, last_seen')
          .gte('login_time', '${todayPrefix}T00:00:00')
          .lt('login_time', '${tomorrowPrefix}T00:00:00');

      final Map<String, Map<String, dynamic>> todaySummary = {};
      for (final row in (todayRows as List<dynamic>).cast<Map<String, dynamic>>()) {
        final loginTime = DateTime.parse(row['login_time'] as String);
        final lastSeen = DateTime.parse(row['last_seen'] as String);
        final seconds = lastSeen.difference(loginTime).inSeconds;
        if (seconds < 30) continue;
        final username = row['username'] as String;
        todaySummary.putIfAbsent(username, () => {
          'day': todayPrefix,
          'username': username,
          'session_count': 0,
          'total_seconds': 0,
        });
        todaySummary[username]!['session_count'] = (todaySummary[username]!['session_count'] as int) + 1;
        todaySummary[username]!['total_seconds'] = (todaySummary[username]!['total_seconds'] as int) + seconds;
      }

      final todayList = todaySummary.values.toList()
        ..sort((a, b) => (a['username'] as String).compareTo(b['username'] as String));

      final historyList = (historyRows as List<dynamic>).cast<Map<String, dynamic>>().map((r) => {
        'day': r['date'] as String,
        'username': r['username'] as String,
        'session_count': r['session_count'] as int,
        'total_seconds': r['total_seconds'] as int,
      }).toList();

      return [...todayList, ...historyList];
    } catch (e) {
      return _fetchDailySummaryLocal();
    }
  }

  Future<List<Map<String, dynamic>>> _fetchDailySummaryLocal() async {
    final db = await _db;
    final todayPrefix = _todayPrefix();

    final todayRows = await db.rawQuery('''
      SELECT
        ? AS day,
        username,
        COUNT(*) AS session_count,
        CAST(SUM(MAX(0, (julianday(last_seen) - julianday(login_time)) * 86400)) AS INTEGER) AS total_seconds
      FROM user_sessions
      WHERE substr(login_time, 1, 10) = ?
        AND (julianday(last_seen) - julianday(login_time)) * 86400 >= 30
      GROUP BY username
      ORDER BY username ASC
    ''', [todayPrefix, todayPrefix]);

    final history = await db.rawQuery('''
      SELECT date AS day, username, session_count, total_seconds
      FROM user_daily_summary
      ORDER BY date DESC, username ASC
    ''');

    return [...todayRows, ...history];
  }

  Future<DateTime?> getLastSessionTime(String username) async {
    try {
      final rows = await _supabase
          .from('user_sessions')
          .select('login_time')
          .eq('username', username)
          .order('id', ascending: false)
          .limit(1);
      if ((rows as List).isEmpty) return null;
      return DateTime.parse(rows.first['login_time'] as String);
    } catch (e) {
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
  }

  Future<void> clearAllLogs() async {
    final db = await _db;
    await db.delete('user_activity_logs');
    await db.delete('user_sessions');
    await db.delete('user_daily_summary');
  }
}
