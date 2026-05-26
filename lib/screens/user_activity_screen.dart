import 'package:flutter/material.dart';
import '../services/user_activity_service.dart';

class UserActivityScreen extends StatefulWidget {
  const UserActivityScreen({super.key});

  @override
  State<UserActivityScreen> createState() => _UserActivityScreenState();
}

class _UserActivityScreenState extends State<UserActivityScreen>
    with SingleTickerProviderStateMixin {
  final UserActivityService _service = UserActivityService();
  late final TabController _tabController;

  List<Map<String, dynamic>> _userSummaries = [];
  List<Map<String, dynamic>> _allLogs = [];
  List<Map<String, dynamic>> _latestLogs = [];
  List<Map<String, dynamic>> _dailySummary = [];
  bool _isLoading = true;
  String? _selectedUser;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _service.fetchUserSessions(),
      _service.fetchActivityLogs(username: _selectedUser),
      _service.fetchDailySummary(),
      _service.fetchLatestActivityPerUser(),
    ]);
    if (mounted) {
      setState(() {
        _userSummaries = results[0];
        _allLogs = results[1];
        _dailySummary = results[2];
        _latestLogs = results[3];
        _isLoading = false;
      });
    }
  }

  Future<void> _filterByUser(String? username) async {
    setState(() {
      _selectedUser = username;
      _isLoading = true;
    });
    final results = await Future.wait([
      _service.fetchActivityLogs(username: username),
      if (username == null) _service.fetchLatestActivityPerUser()
          else Future.value(<Map<String, dynamic>>[]),
    ]);
    if (mounted) {
      setState(() {
        _allLogs = results[0];
        if (username == null) _latestLogs = results[1];
        _isLoading = false;
      });
    }
    if (username != null) _tabController.animateTo(2);
  }

  String _formatDateTime(String isoString) {
    final dt = DateTime.parse(isoString).toLocal();
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final amPm = h >= 12 ? 'PM' : 'AM';
    final displayH = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '${dt.month}/${dt.day}/${dt.year} $displayH:$m $amPm';
  }

  String _timeAgo(String isoString) {
    final dt = DateTime.parse(isoString).toLocal();
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return _formatDateTime(isoString);
  }

  IconData _actionIcon(String action, String? screen) {
    final a = action.toLowerCase();
    if (a == 'opened screen') {
      final s = (screen ?? '').toLowerCase();
      if (s.contains('incoming')) return Icons.move_to_inbox_outlined;
      if (s.contains('outgoing')) return Icons.outbox_outlined;
      if (s.contains('flag')) return Icons.flag_outlined;
      if (s.contains('attendance') || s.contains('mov')) return Icons.event_note_outlined;
      if (s.contains('calendar')) return Icons.calendar_today_outlined;
      if (s.contains('notification')) return Icons.notifications_outlined;
      if (s.contains('delete')) return Icons.history;
      if (s.contains('about')) return Icons.info_outline;
      if (s.contains('add')) return Icons.add_circle_outline;
      return Icons.open_in_new;
    }
    if (a.contains('app opened') || a.contains('login')) return Icons.login;
    if (a.contains('logout')) return Icons.logout;
    if (a.contains('add') || a.contains('creat')) return Icons.add_circle_outline;
    if (a.contains('edit') || a.contains('updat')) return Icons.edit_outlined;
    if (a.contains('delet') || a.contains('remov')) return Icons.delete_outline;
    if (a.contains('sync')) return Icons.sync;
    if (a.contains('document')) return Icons.description_outlined;
    return Icons.radio_button_unchecked;
  }

  Color _actionColor(String action, ColorScheme cs) {
    final a = action.toLowerCase();
    if (a == 'opened screen') return cs.secondary;
    if (a.contains('app opened') || a.contains('login')) return Colors.green;
    if (a.contains('logout')) return Colors.grey;
    if (a.contains('add') || a.contains('creat')) return cs.primary;
    if (a.contains('edit') || a.contains('updat')) return Colors.orange;
    if (a.contains('delet') || a.contains('remov')) return cs.error;
    if (a.contains('sync')) return Colors.blue;
    return cs.onSurfaceVariant;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Activity'),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.people_outline), text: 'Users'),
            Tab(icon: Icon(Icons.bar_chart), text: 'Daily'),
            Tab(icon: Icon(Icons.timeline), text: 'Activity Log'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildUsersTab(cs),
                _buildDailySummaryTab(cs),
                _buildActivityTab(cs),
              ],
            ),
    );
  }

  Widget _buildUsersTab(ColorScheme cs) {
    final now = DateTime.now();
    final todayLabel =
        '${_monthName(now.month)} ${now.day}, ${now.year}';

    if (_userSummaries.isEmpty) {
      return Column(
        children: [
          _todayHeader(todayLabel, 0, cs),
          Expanded(
            child: _emptyState(
              icon: Icons.people_outline,
              message: 'No one has opened the app today yet.',
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        itemCount: _userSummaries.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) return _todayHeader(todayLabel, _userSummaries.length, cs);

          final user = _userSummaries[i - 1];
          final username = user['username'] as String;
          final sessionCount = user['session_count'] as int;
          final firstOpen = user['first_open'] as String;
          final lastSeen = user['last_seen'] as String;

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              leading: CircleAvatar(
                backgroundColor: cs.primaryContainer,
                child: Text(
                  username.isNotEmpty ? username[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
              ),
              title: Text(username,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: Text(
                'First open: ${_timeOnly(firstOpen)}  ·  Last active: ${_timeAgo(lastSeen)}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$sessionCount',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold, color: cs.primary),
                  ),
                  Text(
                    sessionCount == 1 ? 'open' : 'opens',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              onTap: () {
                _tabController.animateTo(2);
                _filterByUser(username);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _todayHeader(String dateLabel, int count, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 10),
      child: Row(
        children: [
          Icon(Icons.today, size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            dateLabel,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: cs.primary),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count ${count == 1 ? 'user' : 'users'}',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: cs.onPrimaryContainer),
            ),
          ),
        ],
      ),
    );
  }

  String _monthName(int month) {
    const names = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return names[month - 1];
  }

  Widget _buildDailySummaryTab(ColorScheme cs) {
    if (_dailySummary.isEmpty) {
      return _emptyState(
        icon: Icons.bar_chart,
        message: 'No qualifying sessions yet.',
      );
    }

    // Group rows by day
    final Map<String, List<Map<String, dynamic>>> byDay = {};
    for (final row in _dailySummary) {
      final day = row['day'] as String;
      byDay.putIfAbsent(day, () => []).add(row);
    }
    final days = byDay.keys.toList(); // already sorted DESC from query

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: days.length,
        itemBuilder: (context, i) {
          final day = days[i];
          final users = byDay[day]!;
          final uniqueUserCount = users.length;

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: CircleAvatar(
                  backgroundColor: cs.primaryContainer,
                  child: Text(
                    '$uniqueUserCount',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
                title: Text(
                  _dayLabel(day),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                subtitle: Text(
                  '$uniqueUserCount ${uniqueUserCount == 1 ? 'user' : 'users'} active',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                children: users.map((u) {
                  final username = u['username'] as String;
                  final sessionCount = u['session_count'] as int;
                  final totalSeconds = u['total_seconds'] as int;
                  final duration = _formatDuration(totalSeconds);
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: cs.secondaryContainer,
                      child: Text(
                        username[0].toUpperCase(),
                        style: TextStyle(fontSize: 13, color: cs.onSecondaryContainer, fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(username, style: const TextStyle(fontSize: 14)),
                    subtitle: Text(
                      '$sessionCount ${sessionCount == 1 ? 'session' : 'sessions'}  •  $duration total',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                    trailing: Icon(Icons.check_circle, color: Colors.green.shade400, size: 18),
                  );
                }).toList(),
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDuration(int totalSeconds) {
    if (totalSeconds < 60) return '${totalSeconds}s';
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    if (m < 60) return s == 0 ? '${m}m' : '${m}m ${s}s';
    final h = m ~/ 60;
    final rm = m % 60;
    return rm == 0 ? '${h}h' : '${h}h ${rm}m';
  }

  Widget _buildActivityTab(ColorScheme cs) {
    return Column(
      children: [
        if (_userSummaries.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(
              children: [
                const Icon(Icons.filter_list, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: _selectedUser,
                    decoration: InputDecoration(
                      labelText: 'Filter by user',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All users')),
                      ..._userSummaries.map((u) => DropdownMenuItem(
                            value: u['username'] as String,
                            child: Text(u['username'] as String),
                          )),
                    ],
                    onChanged: (v) => _filterByUser(v),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: _selectedUser == null
              ? _buildLatestPerUserList(cs)
              : (_allLogs.isEmpty
                  ? _emptyState(icon: Icons.timeline, message: 'No activity logs found.')
                  : RefreshIndicator(onRefresh: _loadData, child: _buildGroupedLogList(cs))),
        ),
      ],
    );
  }

  // Builds a flat list of mixed items: String = date header, Map = log entry
  List<dynamic> _buildGroupedItems() {
    final items = <dynamic>[];
    String? lastDateKey;
    for (final log in _allLogs) {
      final dt = DateTime.parse(log['timestamp'] as String).toLocal();
      final dateKey = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      if (dateKey != lastDateKey) {
        items.add(dateKey);
        lastDateKey = dateKey;
      }
      items.add(log);
    }
    return items;
  }

  String _dayLabel(String dateKey) {
    final now = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final yKey = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
    if (dateKey == today) return 'Today';
    if (dateKey == yKey) return 'Yesterday';
    final dt = DateTime.parse(dateKey);
    return '${_monthName(dt.month)} ${dt.day}, ${dt.year}';
  }

  String _timeOnly(String isoString) {
    final dt = DateTime.parse(isoString).toLocal();
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final amPm = h >= 12 ? 'PM' : 'AM';
    final displayH = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$displayH:$m $amPm';
  }

  Widget _buildLatestPerUserList(ColorScheme cs) {
    if (_latestLogs.isEmpty) {
      return _emptyState(icon: Icons.timeline, message: 'No activity logs found.');
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _latestLogs.length,
        itemBuilder: (context, i) {
          final log = _latestLogs[i];
          final username = log['username'] as String;
          final action = log['action'] as String;
          final screen = log['screen'] as String?;
          final timestamp = log['timestamp'] as String;
          final color = _actionColor(action, cs);
          final label = (action == 'Opened screen' && screen != null) ? screen : action;

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: cs.primaryContainer,
              child: Text(
                username[0].toUpperCase(),
                style: TextStyle(fontWeight: FontWeight.bold, color: cs.onPrimaryContainer),
              ),
            ),
            title: Text(username, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Row(
              children: [
                Icon(_actionIcon(action, screen), size: 12, color: color),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            trailing: Text(_timeAgo(timestamp),
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            onTap: () => _filterByUser(username),
          );
        },
      ),
    );
  }

  Widget _buildGroupedLogList(ColorScheme cs) {
    final items = _buildGroupedItems();
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];

        // Date header
        if (item is String) {
          return Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 6),
            child: Row(
              children: [
                Text(
                  _dayLabel(item),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Divider(color: cs.outlineVariant, height: 1)),
              ],
            ),
          );
        }

        final log = item as Map<String, dynamic>;
        final action = log['action'] as String;
        final screen = log['screen'] as String?;
        final details = log['details'] as String?;
        final timestamp = log['timestamp'] as String;
        final username = log['username'] as String;
        final color = _actionColor(action, cs);

        final label = screen != null && action == 'Opened screen'
            ? screen
            : action;
        final sub = action == 'Opened screen'
            ? null
            : (screen ?? details);

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Icon(_actionIcon(action, screen), size: 15, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(fontSize: 13, color: cs.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (sub != null || _selectedUser == null)
                      Text(
                        [
                          if (_selectedUser == null) username,
                          if (sub != null) sub,
                        ].join(' · '),
                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _timeOnly(timestamp),
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _emptyState({required IconData icon, required String message}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(color: Colors.grey.shade500, fontSize: 15)),
        ],
      ),
    );
  }
}
