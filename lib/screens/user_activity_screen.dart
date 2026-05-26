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
  bool _isLoading = true;
  String? _selectedUser;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final summaries = await _service.fetchUserSessions();
    final logs = await _service.fetchActivityLogs(username: _selectedUser);
    if (mounted) {
      setState(() {
        _userSummaries = summaries;
        _allLogs = logs;
        _isLoading = false;
      });
    }
  }

  Future<void> _filterByUser(String? username) async {
    setState(() {
      _selectedUser = username;
      _isLoading = true;
    });
    final logs = await _service.fetchActivityLogs(username: username);
    if (mounted) {
      setState(() {
        _allLogs = logs;
        _isLoading = false;
      });
    }
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
                _buildActivityTab(cs),
              ],
            ),
    );
  }

  Widget _buildUsersTab(ColorScheme cs) {
    if (_userSummaries.isEmpty) {
      return _emptyState(
        icon: Icons.people_outline,
        message: 'No user sessions recorded yet.',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _userSummaries.length,
        itemBuilder: (context, i) {
          final user = _userSummaries[i];
          final username = user['username'] as String;
          final sessionCount = user['session_count'] as int;
          final firstSeen = user['first_seen'] as String;
          final lastSeen = user['last_seen'] as String;
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              leading: CircleAvatar(
                backgroundColor: cs.primaryContainer,
                child: Text(
                  username.isNotEmpty ? username[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              title: Text(
                username,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.login, size: 14),
                      const SizedBox(width: 4),
                      Text('First seen: ${_formatDateTime(firstSeen)}', style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.access_time, size: 14),
                      const SizedBox(width: 4),
                      Text('Last active: ${_timeAgo(lastSeen)}', style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ],
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$sessionCount',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                    ),
                  ),
                  Text(
                    sessionCount == 1 ? 'session' : 'sessions',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              onTap: () {
                _tabController.animateTo(1);
                _filterByUser(username);
              },
            ),
          );
        },
      ),
    );
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
          child: _allLogs.isEmpty
              ? _emptyState(
                  icon: Icons.timeline,
                  message: 'No activity logs found.',
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: _buildGroupedLogList(cs),
                ),
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
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String _timeOnly(String isoString) {
    final dt = DateTime.parse(isoString).toLocal();
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final amPm = h >= 12 ? 'PM' : 'AM';
    final displayH = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$displayH:$m $amPm';
  }

  Widget _buildGroupedLogList(ColorScheme cs) {
    final items = _buildGroupedItems();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];

        if (item is String) {
          return Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _dayLabel(item),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Divider(color: cs.outlineVariant)),
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

        // check if next item is also a log (not a header) for the connector line
        final hasConnector = i < items.length - 1 && items[i + 1] is! String;

        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: color.withValues(alpha: 0.15),
                    child: Icon(_actionIcon(action, screen), size: 16, color: color),
                  ),
                  if (hasConnector)
                    Container(width: 2, height: 28, color: cs.outlineVariant),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Card(
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                action,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ),
                            Text(
                              _timeOnly(timestamp),
                              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                        if (screen != null || details != null || _selectedUser == null) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 2,
                            children: [
                              if (_selectedUser == null)
                                _chip(Icons.person, username, cs.primary, cs),
                              if (screen != null)
                                _chip(Icons.smartphone, screen, cs.secondary, cs),
                              if (details != null)
                                Text(details, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(IconData icon, String label, Color color, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
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
