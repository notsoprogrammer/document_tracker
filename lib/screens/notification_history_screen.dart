import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/supabase_service.dart';
import '../utils/snackbar_utils.dart';

class NotificationHistoryScreen extends StatefulWidget {
  const NotificationHistoryScreen({super.key});

  @override
  State<NotificationHistoryScreen> createState() => _NotificationHistoryScreenState();
}

class _NotificationHistoryScreenState extends State<NotificationHistoryScreen> {
  final SupabaseService _databaseService = SupabaseService();
  List<Map<String, dynamic>> _notificationLogs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotificationLogs();
  }

  Future<void> _loadNotificationLogs() async {
    try {
      final logs = await _databaseService.fetchNotificationsHistory();
      setState(() {
        _notificationLogs = logs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      // Handle error - could show a snackbar
      print('Error loading notification logs: $e');
    }
  }

  String _formatDateTime(String dateTimeString) {
    final dateTime = DateTime.parse(dateTimeString);
    // Convert UTC timestamp to device's local timezone
    final localDateTime = dateTime.toLocal();
    final hour = localDateTime.hour;
    final minute = localDateTime.minute.toString().padLeft(2, '0');
    final amPm = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final month = localDateTime.month.toString().padLeft(2, '0');
    final day = localDateTime.day.toString().padLeft(2, '0');
    final year = localDateTime.year;
    return '$month/$day/$year $displayHour:$minute $amPm';
  }

  String _getStatusIcon(String status) {
    switch (status) {
      case 'scheduled':
        return '⏰';
      case 'shown':
        return '✅';
      case 'cancelled':
        return '❌';
      case 'completed':
        return '🎉';
      default:
        return '❓';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification History'),
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
            ],
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _notificationLogs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.notifications,
                          size: 64,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No notification history found',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadNotificationLogs,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _notificationLogs.length,
                      itemBuilder: (context, index) {
                        final log = _notificationLogs[index];

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      _getStatusIcon(log['status']),
                                      style: const TextStyle(fontSize: 20),
                                    ),
                                    Expanded(
                                      child: Text(
                                        log['documents']?['title'] ?? log['document_code'] ?? 'Unknown Document',
                                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    ),
                                    Text(
                                      log['status'] ?? 'unknown',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: Theme.of(context).colorScheme.primary,
                                          ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Code: ${log['document_code'] ?? 'N/A'}',
                                          style: Theme.of(context).textTheme.bodyMedium,
                                        ),
                                        const SizedBox(width: 4),
                                        GestureDetector(
                                          onTap: () {
                                            Clipboard.setData(
                                              ClipboardData(text: log['document_code'] ?? ''),
                                            );
                                            SnackbarUtils.showInfoSnackBar(
                                              context,
                                              'Code copied to clipboard',
                                            );
                                          },
                                          child: Icon(
                                            Icons.copy,
                                            size: 16,
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (log['documents']?['compliance_assignee'] != null)
                                      Text(
                                        'Assignee: ${log['documents']['compliance_assignee']}',
                                        style: Theme.of(context).textTheme.bodyMedium,
                                      ),
                                    Text(
                                      'Scheduled: ${_formatDateTime(log['scheduled_time'])}',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
      ),
    );
  }
}
