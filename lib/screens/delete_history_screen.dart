import 'package:flutter/material.dart';
import '../services/supabase_service.dart';

class DeleteHistoryScreen extends StatefulWidget {
  const DeleteHistoryScreen({super.key});

  @override
  State<DeleteHistoryScreen> createState() => _DeleteHistoryScreenState();
}

class _DeleteHistoryScreenState extends State<DeleteHistoryScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  List<Map<String, dynamic>> _deleteLogs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDeleteLogs();
  }

  Future<void> _loadDeleteLogs() async {
    try {
      final logs = await _supabaseService.fetchDeletedRecords();
      setState(() {
        _deleteLogs = logs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      // Handle error - could show a snackbar
    }
  }

  String _formatDateTime(DateTime dateTime) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delete History'),
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
            : _deleteLogs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.history,
                          size: 64,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No deletion history found',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadDeleteLogs,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _deleteLogs.length,
                      itemBuilder: (context, index) {
                        final log = _deleteLogs[index];

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
                                Text(
                                  log['title'] ?? 'Untitled',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Code: ${log['doc_code'] ?? 'N/A'}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 8),
                                // Last line: deleted_by | time
                                Text(
                                  '${log['deleted_by'] ?? 'Unknown'} | ${_formatDateTime(DateTime.parse(log['deleted_at']))}',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
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
