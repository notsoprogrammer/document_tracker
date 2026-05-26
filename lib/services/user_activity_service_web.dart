import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';

class UserActivityService {
  static final UserActivityService _instance = UserActivityService._internal();
  factory UserActivityService() => _instance;
  UserActivityService._internal();

  int? _remoteSessionId;
  DateTime? _lastPurgeDate;

  SupabaseClient get _supabase => Supabase.instance.client;

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
      debugPrint('UserActivityService remote error: $e');
    }
  }

  Future<void> _maybePurgeOldData() async {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    if (_lastPurgeDate == todayDate) return;
    _lastPurgeDate = todayDate;
    await _tryRemote(_purgeRemote);
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
    final now = _now();
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
      debugPrint('fetchUserSessions failed: $e');
      return [];
    }
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
      debugPrint('fetchSessionsForUser failed: $e');
      return [];
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
      debugPrint('fetchLatestActivityPerUser failed: $e');
      return [];
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
      debugPrint('fetchActivityLogs failed: $e');
      return [];
    }
  }

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
      debugPrint('fetchDailySummary failed: $e');
      return [];
    }
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
      return null;
    }
  }

  Future<void> clearAllLogs() async {
    // No local storage on web; remote data is retained intentionally
  }
}
