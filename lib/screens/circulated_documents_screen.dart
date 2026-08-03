
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/document.dart';
import '../utils/search_filter_utils.dart';
import '../services/upload_queue_manager.dart';
import '../services/cached_document_service.dart';
import '../services/cabinet_service.dart';
import '../services/auth_service.dart';

class CirculatedDocumentsScreen extends StatefulWidget {
  final List<Document> documents;
  final Function(int, String, String, {String? notes}) transferDocument;
  final Function(int, String, String,
      {String? notes,
      DateTime? complianceDeadline,
      String? complianceAssignee}) updateDocumentStatus;
  final Function(int) deleteDocument;
  final Function(String) syncDocument;
  final VoidCallback? onRefresh;

  const CirculatedDocumentsScreen({
    super.key,
    required this.documents,
    required this.transferDocument,
    required this.updateDocumentStatus,
    required this.deleteDocument,
    required this.syncDocument,
    this.onRefresh,
  });

  @override
  State<CirculatedDocumentsScreen> createState() =>
      _CirculatedDocumentsScreenState();
}

class _CirculatedDocumentsScreenState extends State<CirculatedDocumentsScreen> {
  late List<Document> _filteredDocuments;
  bool _isLoading = true;
  late UploadQueueManager _uploadQueueManager;
  String _searchQuery = '';
  DateTime? _startDate;
  DateTime? _endDate;
  DateTime? _specificDate;
  final Set<int> _expandedTiles = {};
  late final TextEditingController _searchController = TextEditingController();
  String? _username;

  @override
  void initState() {
    super.initState();
    _searchController.text = _searchQuery;
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
        _updateFilteredDocuments();
      });
    });

    _filteredDocuments = widget.documents
        .where((doc) =>
            doc.flowStage == 'circulated' &&
            doc.mode != 'Flag Ceremony' &&
            doc.mode != 'Office Function MOVs')
        .toList();

    _filteredDocuments.sort((a, b) {
      final aDate = a.history.isNotEmpty
          ? a.history.last.timestamp
          : (a.createdAt ?? DateTime(1900));
      final bDate = b.history.isNotEmpty
          ? b.history.last.timestamp
          : (b.createdAt ?? DateTime(1900));
      return bDate.compareTo(aDate);
    });

    _uploadQueueManager = UploadQueueManager();
    _uploadQueueManager.addListener(_onUploadChanged);

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      _triggerPendingUploads();
    });

    _loadUsername();
  }

  Future<void> _loadUsername() async {
    final username = await AuthService.getUsername();
    if (mounted) {
      setState(() {
        _username = username;
      });
    }
  }

  void _onUploadChanged() {
    setState(() {});
  }

  void _triggerPendingUploads() {
    final allItems = _uploadQueueManager.getAllItems();
    final hasPending = allItems.any((item) =>
      item['status'] == 'pending' ||
      (item['status'] == 'failed' && (item['retryCount'] as int? ?? 0) < 3)
    );
    if (hasPending) {
      CachedDocumentService().processPendingUploads();
    }
  }

  @override
  void dispose() {
    _uploadQueueManager.removeListener(_onUploadChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(CirculatedDocumentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.documents != widget.documents) {
      setState(() {
        _expandedTiles.clear();
        _updateFilteredDocuments();
      });
    }
  }

  void _updateFilteredDocuments() {
    setState(() {
      _filteredDocuments = searchAndFilterDocuments(
        widget.documents
            .where((doc) =>
                doc.flowStage == 'circulated' &&
                doc.mode != 'Flag Ceremony' &&
                doc.mode != 'Office Function MOVs')
            .toList(),
        searchQuery: _searchQuery,
        startDate: _startDate,
        endDate: _endDate,
        specificDate: _specificDate,
      );
    });
  }

  String _formatDateTime(DateTime dateTime) {
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final amPm = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final year = dateTime.year;
    return '\$month/\$day/\$year \$displayHour:\$minute \$amPm';
  }

  Widget _buildUploadStatusIndicator(Document doc) {
    final queueManager = UploadQueueManager();
    final pendingUploads = queueManager.getPendingUploads(doc.code);
    final allUploads = queueManager
        .getAllItems()
        .where((item) => item['documentCode'] == doc.code)
        .toList();
    final uploadingUploads =
        allUploads.where((item) => item['status'] == 'uploading').toList();

    final totalFiles = doc.localImagePaths.length + doc.localFilePaths.length;
    final uploadedFiles = doc.imageUrls.length + doc.fileUrls.length;
    final hasUploads =
        pendingUploads.isNotEmpty || uploadingUploads.isNotEmpty;

    if (!hasUploads && totalFiles == 0) {
      return const SizedBox.shrink();
    }

    if (hasUploads) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Uploading \$uploadedFiles/\$totalFiles files...',
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Future<void> _showLocationUpdateDialog(int idx) async {
    final doc = _filteredDocuments[idx];
    final cabinetNames = await CabinetService().fetchCabinetNames();
    if (!mounted) return;
    String? selected = doc.cabinetLocation;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(children: [
            Icon(Icons.inventory_2_outlined, color: Theme.of(ctx).colorScheme.primary),
            const SizedBox(width: 8),
            const Text("Update Location"),
          ]),
          content: cabinetNames.isEmpty
              ? const Text("No cabinets found. Add cabinets from the Cabinet Library first.")
              : DropdownButtonFormField<String>(
                  key: ValueKey(selected),
                  initialValue: selected,
                  decoration: InputDecoration(
                    labelText: "Cabinet Location",
                    prefixIcon: const Icon(Icons.inventory_2_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text("Not assigned")),
                    ...cabinetNames.map((n) => DropdownMenuItem(value: n, child: Text(n))),
                  ],
                  onChanged: (v) => setDialogState(() => selected = v),
                ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () async {
                await CachedDocumentService().updateDocument(doc.code, {'cabinet_location': selected});
                if (mounted) setState(() { _filteredDocuments[idx] = doc.copyWith(cabinetLocation: selected); });
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showHeldByDialog(int idx) async {
    if (!mounted) return;
    final doc = _filteredDocuments[idx];
    final heldByController = TextEditingController(text: doc.heldBy ?? '');
    final folderController = TextEditingController(text: doc.folderTitle ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.person_pin_outlined, color: Theme.of(ctx).colorScheme.primary),
          const SizedBox(width: 8),
          const Text("Update Holder & Folder"),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: heldByController,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: "Held by",
                prefixIcon: const Icon(Icons.person_pin_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                hintText: "Enter person's name",
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: folderController,
              decoration: InputDecoration(
                labelText: "Folder / Details",
                prefixIcon: const Icon(Icons.folder_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                hintText: "e.g. Blue folder, Top drawer, Binder 2024",
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              final heldByValue = heldByController.text.trim().isEmpty ? null : heldByController.text.trim();
              final folderValue = folderController.text.trim().isEmpty ? null : folderController.text.trim();
              await CachedDocumentService().updateDocument(doc.code, {'held_by': heldByValue, 'folder_title': folderValue});
              if (mounted) setState(() {
                _filteredDocuments[idx].heldBy = heldByValue;
                _filteredDocuments[idx].folderTitle = folderValue;
              });
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Circulated Documents"),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: "Search documents",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                Expanded(
                  child: _filteredDocuments.isEmpty
                      ? const Center(child: Text("No circulated documents found"))
                      : ListView.builder(
                          itemCount: _filteredDocuments.length,
                          itemBuilder: (context, index) {
                            final doc = _filteredDocuments[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              child: ExpansionTile(
                                title: Text(doc.title ?? "Untitled"),
                                subtitle: Text(
                                  "Received: \${doc.receivingDate != null ? _formatDateTime(doc.receivingDate!) : 'Not set'} | Last updated: \${_formatDateTime(doc.history.isNotEmpty ? doc.history.last.timestamp : (doc.createdAt ?? DateTime.now()))}",
                                ),
                                trailing: _buildUploadStatusIndicator(doc),
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                                      borderRadius: const BorderRadius.only(
                                        bottomLeft: Radius.circular(12),
                                        bottomRight: Radius.circular(12),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildDetailRow(Icons.description, "Type", doc.type ?? "N/A"),
                                        const SizedBox(height: 8),
                                        _buildDetailRow(Icons.person, "From", doc.fromOrTo),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Expanded(child: _buildDetailRow(Icons.inventory_2_outlined, "Location", [doc.cabinetLocation ?? 'Not assigned', if ((doc.folderTitle ?? '').isNotEmpty) doc.folderTitle!].join(' | '))),
                                            IconButton(
                                              icon: const Icon(Icons.edit, size: 18),
                                              onPressed: () => _showLocationUpdateDialog(index),
                                              tooltip: "Update Location",
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Expanded(child: _buildDetailRow(Icons.person_pin_outlined, "Held by", [doc.heldBy ?? 'Not specified', if ((doc.folderTitle ?? '').isNotEmpty) doc.folderTitle!].join(' | '))),
                                            IconButton(
                                              icon: const Icon(Icons.edit, size: 18),
                                              onPressed: () => _showHeldByDialog(index),
                                              tooltip: "Update Holder",
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        _buildDetailRow(Icons.assignment_ind, "Assigned To", doc.assignedTo),
                                        const SizedBox(height: 8),
                                        _buildDetailRow(Icons.info, "Status", doc.status),
                                        const SizedBox(height: 8),
                                        _buildDetailRow(Icons.comment, "Remarks", doc.remarks),
                                        const SizedBox(height: 8),
                                        _buildDetailRow(Icons.receipt, "Received by", doc.person),
                                        const SizedBox(height: 16),
                                        ExpansionTile(
                                          leading: const Icon(Icons.history),
                                          title: Text(
                                            "Document History (${doc.history.isEmpty ? '0' : doc.history.length.toString()})",
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          children: (() {
                                            final entries = doc.history;
                                            if (entries.isEmpty) {
                                              return [
                                                const Padding(
                                                  padding: EdgeInsets.all(16),
                                                  child: Text("No history available"),
                                                ),
                                              ];
                                            }
                                            return entries.map((entry) {
                                              return Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                                child: Row(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Icon(
                                                      Icons.circle,
                                                      size: 12,
                                                      color: const Color(0xFFFFB74D),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            entry.action,
                                                            style: const TextStyle(fontWeight: FontWeight.w500),
                                                          ),
                                                          Text(
                                                            "by: ${entry.person} | ${_formatDateTime(entry.timestamp)}",
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                                            ),
                                                          ),
                                                          if (entry.notes != null && entry.notes!.isNotEmpty) ...[
                                                            const SizedBox(height: 4),
                                                            Text(
                                                              "Notes: ${entry.notes}",
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                                fontStyle: FontStyle.italic,
                                                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                                              ),
                                                            ),
                                                          ],
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }).toList();
                                          })(),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
