import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';
import '../services/upload_queue_manager.dart';
import '../services/cached_document_service.dart';

/// Shared banner that shows active upload progress across all list screens.
/// Self-subscribes to UploadQueueManager so it rebuilds without parent setState.
/// Calls [onAllUploadsComplete] when the queue empties after having uploads —
/// list screens use this to refresh their document data.
/// In debug builds only: tappable to open the debug dialog.
class UploadStatusBanner extends StatefulWidget {
  final VoidCallback? onAllUploadsComplete;
  const UploadStatusBanner({super.key, this.onAllUploadsComplete});

  @override
  State<UploadStatusBanner> createState() => _UploadStatusBannerState();
}

class _UploadStatusBannerState extends State<UploadStatusBanner> {
  late final UploadQueueManager _queueManager;
  final ConnectivityService _connectivityService = ConnectivityService();
  StreamSubscription<bool>? _connectivitySub;
  bool _isOnline = true;
  bool _hadUploads = false;
  bool _showSuccess = false;
  Timer? _successTimer;

  @override
  void initState() {
    super.initState();
    _queueManager = UploadQueueManager();
    _queueManager.addListener(_onQueueChanged);
    _initConnectivity();
  }

  Future<void> _initConnectivity() async {
    _isOnline = await _connectivityService.isOnline;
    if (mounted) setState(() {});
    _connectivitySub = _connectivityService.onOnlineStatusChanged.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
  }

  void _onQueueChanged() {
    if (!mounted) return;
    final allItems = _queueManager.getAllItems();
    final activeCount = allItems.where((i) =>
      i['status'] == 'pending' || i['status'] == 'uploading').length;

    if (activeCount > 0) {
      _hadUploads = true;
    } else if (_hadUploads && !_showSuccess) {
      _showSuccess = true;
      widget.onAllUploadsComplete?.call();
      _successTimer?.cancel();
      _successTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() { _showSuccess = false; _hadUploads = false; });
      });
    }
    setState(() {});
  }

  @override
  void dispose() {
    _queueManager.removeListener(_onQueueChanged);
    _connectivitySub?.cancel();
    _successTimer?.cancel();
    super.dispose();
  }

  void _showDebugDialog(
    List<Map<String, dynamic>> allUploads,
    List<Map<String, dynamic>> uploading,
    List<Map<String, dynamic>> pending,
    List<Map<String, dynamic>> failed,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => _UploadDebugDialog(
        allUploads: allUploads,
        uploading: uploading,
        pending: pending,
        failed: failed,
      ),
    );
  }

  Widget _buildSuccessBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, size: 20, color: Colors.green[700]),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Uploads complete — list updated',
              style: TextStyle(
                fontSize: 14,
                color: Colors.green[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Brief success flash after all uploads finish
    if (_showSuccess) return _buildSuccessBanner();

    final allUploads = _queueManager.getAllItems();
    final uploadingUploads = allUploads.where((i) => i['status'] == 'uploading').toList();
    final pendingUploads   = allUploads.where((i) => i['status'] == 'pending').toList();
    final failedUploads    = allUploads.where((i) => i['status'] == 'failed').toList();

    // Offline: show "queued" state instead of the active-upload spinner
    if (!_isOnline) {
      final queuedCount = pendingUploads.length + failedUploads.length + uploadingUploads.length;
      if (queuedCount == 0) return const SizedBox.shrink();
      return _buildOfflineBanner(queuedCount, allUploads, pendingUploads, uploadingUploads, failedUploads);
    }

    // Online: show active upload progress
    if (uploadingUploads.isEmpty && pendingUploads.isEmpty) {
      return const SizedBox.shrink();
    }

    final totalUploading = uploadingUploads.length;
    final totalPending   = pendingUploads.length;

    final label = totalUploading > 0
        ? 'Uploading $totalUploading file${totalUploading > 1 ? 's' : ''}${totalPending > 0 ? ', $totalPending pending' : ''}...'
        : 'Processing $totalPending upload${totalPending > 1 ? 's' : ''}...';

    final banner = Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.orange),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.orange[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (kDebugMode)
            Icon(Icons.info_outline, size: 16, color: Colors.orange[400]),
        ],
      ),
    );

    if (kDebugMode) {
      return GestureDetector(
        onTap: () => _showDebugDialog(allUploads, uploadingUploads, pendingUploads, failedUploads),
        child: banner,
      );
    }
    return banner;
  }

  Widget _buildOfflineBanner(
    int count,
    List<Map<String, dynamic>> allUploads,
    List<Map<String, dynamic>> pending,
    List<Map<String, dynamic>> uploading,
    List<Map<String, dynamic>> failed,
  ) {
    final banner = Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 20, color: Colors.blueGrey[600]),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$count upload${count > 1 ? 's' : ''} queued — will sync when online',
              style: TextStyle(
                fontSize: 14,
                color: Colors.blueGrey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (kDebugMode)
            Icon(Icons.info_outline, size: 16, color: Colors.blueGrey[400]),
        ],
      ),
    );

    if (kDebugMode) {
      return GestureDetector(
        onTap: () => _showDebugDialog(allUploads, uploading, pending, failed),
        child: banner,
      );
    }
    return banner;
  }
}

class _UploadDebugDialog extends StatefulWidget {
  final List<Map<String, dynamic>> allUploads;
  final List<Map<String, dynamic>> uploading;
  final List<Map<String, dynamic>> pending;
  final List<Map<String, dynamic>> failed;

  const _UploadDebugDialog({
    required this.allUploads,
    required this.uploading,
    required this.pending,
    required this.failed,
  });

  @override
  State<_UploadDebugDialog> createState() => _UploadDebugDialogState();
}

class _UploadDebugDialogState extends State<_UploadDebugDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final log = UploadQueueManager.debugLog;
    final stats = UploadQueueManager().getQueueStats();

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  const Icon(Icons.upload, color: Colors.orange),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Upload Debug',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Stats row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Wrap(
                spacing: 8,
                children: [
                  _chip('Uploading', widget.uploading.length, Colors.blue),
                  _chip('Pending', widget.pending.length, Colors.orange),
                  _chip('Failed', widget.failed.length, Colors.red),
                  _chip('Total', stats['total'] as int, Colors.grey),
                  _chip('Lock', (stats['isProcessing'] as bool) ? 1 : 0, Colors.purple,
                    override: (stats['isProcessing'] as bool) ? 'LOCKED' : 'FREE'),
                ],
              ),
            ),

            // Action buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Force Retry Now'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange[700],
                        side: BorderSide(color: Colors.orange.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onPressed: () {
                        UploadQueueManager.log('DEBUG: manual force-retry triggered');
                        CachedDocumentService().processPendingUploads();
                        Navigator.pop(context);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.delete_sweep, size: 16),
                      label: const Text('Clear All'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red[700],
                        side: BorderSide(color: Colors.red.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Clear upload queue?'),
                            content: const Text(
                              'This removes all pending uploads from the queue. '
                              'Files will be re-queued automatically on the next upload cycle if local paths still exist.',
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Clear', style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await UploadQueueManager().clearAll();
                          if (context.mounted) Navigator.pop(context);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Tabs
            TabBar(
              controller: _tabs,
              labelColor: Colors.orange[700],
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.orange,
              tabs: [
                Tab(text: 'Queue (${widget.allUploads.length})'),
                Tab(text: 'Log (${log.length})'),
              ],
            ),

            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  // Queue tab
                  widget.allUploads.isEmpty
                    ? const Center(child: Text('Queue is empty', style: TextStyle(color: Colors.grey)))
                    : ListView.separated(
                        padding: const EdgeInsets.all(8),
                        itemCount: widget.allUploads.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final item = widget.allUploads[i];
                          final status = item['status'] as String? ?? '?';
                          final retry  = item['retryCount'] as int? ?? 0;
                          final path   = item['filePath']?.toString() ?? '';
                          final shortPath = path.split('/').last.split('\\').last;
                          final code   = item['documentCode']?.toString() ?? '?';
                          final color  = status == 'uploading' ? Colors.blue
                              : status == 'pending' ? Colors.orange
                              : status == 'failed'  ? Colors.red
                              : Colors.green;
                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 10,
                              backgroundColor: color.withValues(alpha: 0.15),
                              child: Text(
                                status[0].toUpperCase(),
                                style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
                              ),
                            ),
                            title: Text(shortPath, style: const TextStyle(fontSize: 12)),
                            subtitle: Text('code: $code  retry: $retry', style: const TextStyle(fontSize: 11)),
                            trailing: Text(status, style: TextStyle(fontSize: 11, color: color)),
                          );
                        },
                      ),

                  // Log tab
                  log.isEmpty
                    ? const Center(child: Text('No log entries yet', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        reverse: true, // newest at top
                        padding: const EdgeInsets.all(8),
                        itemCount: log.length,
                        itemBuilder: (_, i) {
                          final entry = log[log.length - 1 - i];
                          final isError = entry.contains('ERROR') || entry.contains('FAIL');
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: Text(
                              entry,
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                color: isError ? Colors.red : null,
                              ),
                            ),
                          );
                        },
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, int count, Color color, {String? override}) {
    return Chip(
      padding: EdgeInsets.zero,
      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
      label: Text(
        override != null ? '$label: $override' : '$label: $count',
        style: TextStyle(fontSize: 11, color: color),
      ),
      backgroundColor: color.withValues(alpha: 0.1),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
    );
  }
}
