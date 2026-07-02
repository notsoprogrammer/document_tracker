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
  List<Map<String, dynamic>> _overdueDocuments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final logs = await _databaseService.fetchNotificationsHistory();
      final overdue = await _databaseService.fetchOverdueComplianceDocuments();
      setState(() {
        _notificationLogs = logs;
        _overdueDocuments = overdue;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      // Handle error - could show a snackbar
    }
  }

  String _formatScheduledTime(String dateTimeString) {
    // Parse as UTC and display directly without local conversion
    final dateTime = DateTime.parse(dateTimeString).toUtc();
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final amPm = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final year = dateTime.year;
    return '$month/$day/$year $displayHour:$minute $amPm';
  }

  String _getDocumentStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'urgent':
        return '🚨';
      case 'for compliance':
        return '📣';
      case 'filed':
        return '🗃️';
      case 'completed':
        return '✅';
      default:
        return '📄';
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
            : RefreshIndicator(
                onRefresh: _loadData,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Overdue Documents Section
                    if (_overdueDocuments.isNotEmpty) ...[
                      Text(
                        'Overdue Compliance Documents',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.error,
                            ),
                      ),
                      const SizedBox(height: 8),
                      ..._overdueDocuments.map((doc) {
                        final deadline = DateTime.parse(doc['compliance_deadline']);
                        final now = DateTime.now();
                        final daysOverdue = now.difference(deadline).inDays;

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
                                      '🚨',
                                      style: const TextStyle(fontSize: 15),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        doc['title'] ?? 'Unknown Document',
                                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                'Code: ${doc['code'] ?? 'N/A'}',
                                                style: Theme.of(context).textTheme.bodyMedium,
                                              ),
                                              const SizedBox(width: 4),
                                              GestureDetector(
                                                onTap: () {
                                                  Clipboard.setData(
                                                    ClipboardData(text: doc['code'] ?? ''),
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
                                        ),
                                        Text(
                                          'Overdue',
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                color: Theme.of(context).colorScheme.error,
                                              ),
                                        ),
                                      ],
                                    ),
                                    if (doc['compliance_assignee'] != null)
                                      Text(
                                        'Assigned to: ${doc['compliance_assignee']}',
                                        style: Theme.of(context).textTheme.bodyMedium,
                                      ),
                                    if (doc['compliance_deadline'] != null)
                                      Text(
                                        'Deadline: ${_formatScheduledTime(doc['compliance_deadline'])} (${daysOverdue} days overdue)',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              color: Theme.of(context).colorScheme.error,
                                            ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 24),
                    ],

                    // Notification History Section
                    Text(
                      'Notifications',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    if (_notificationLogs.isEmpty)
                      Center(
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
                    else
                      ..._notificationLogs.where((log) => ['urgent', 'for compliance'].contains((log['documents']?['status'] ?? '').toLowerCase())).map((log) {
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
                                      _getDocumentStatusIcon(log['documents']?['status'] ?? ''),
                                      style: const TextStyle(fontSize: 15),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        log['documents']?['title'] ?? log['document_code'] ?? 'Unknown Document',
                                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Row(
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
                                        ),
                                        if (['urgent', 'for compliance'].contains((log['documents']?['status'] ?? '').toLowerCase()))
                                          Text(
                                            log['documents']?['status'] ?? 'unknown',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                  color: Theme.of(context).colorScheme.primary,
                                                ),
                                          ),
                                      ],
                                    ),
                                    if (log['documents']?['compliance_assignee'] != null)
                                      Text(
                                        'Assigned to: ${log['documents']['compliance_assignee']}',
                                        style: Theme.of(context).textTheme.bodyMedium,
                                      ),
                                    if (log['documents']?['compliance_deadline'] != null)
                                      Text(
                                        'Deadline: ${_formatScheduledTime(log['documents']['compliance_deadline'])}',
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
                      }),
                  ],
                ),
              ),
      ),
    );
  }
}
