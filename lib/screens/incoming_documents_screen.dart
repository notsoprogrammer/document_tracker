import 'dart:io';
import 'package:flutter/material.dart';
import '../widgets/scrollable_image_viewer.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../services/image_download_service.dart';
import '../models/document.dart';
import '../services/connectivity_service.dart';
import '../utils/search_filter_utils.dart';
import '../utils/snackbar_utils.dart';
import '../services/upload_queue_manager.dart';
import '../widgets/upload_status_banner.dart';
import '../widgets/connectivity_banner.dart';
import '../utils/delete_utils.dart';
import '../services/cached_document_service.dart';
import '../services/cabinet_service.dart';
import '../services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/date_time_utils.dart';
import '../widgets/move_document_dialog.dart';
import '../services/google_drive_service.dart';
import 'edit_document_screen.dart';
import 'add_document_screen.dart';
import 'pdf_viewer_screen.dart';
import '../services/attachment_view_service.dart';
import '../widgets/document_search_bar.dart';
import '../widgets/document_filter_dialog.dart';
import '../widgets/view_in_cabinet_button.dart';
import '../services/supabase_service.dart';

class IncomingDocumentsScreen extends StatefulWidget {
  final List<Document> documents;
  final Function(int, String, String, {String? notes}) transferDocument;
  final Function(int, String, String, {String? notes, DateTime? complianceDeadline, String? complianceAssignee}) updateDocumentStatus;
  // final Function(int, Document) editDocument;
  final Function(int) deleteDocument;
  final Function(String) syncDocument;
  final VoidCallback? onRefresh;
  final Future<void> Function() syncAllDocuments;
  final String? initialDocumentCode;

  const IncomingDocumentsScreen({
    super.key,
    required this.documents,
    required this.transferDocument,
    required this.updateDocumentStatus,
    // required this.editDocument,
    required this.deleteDocument,
    required this.syncDocument,
    this.onRefresh,
    required this.syncAllDocuments,
    this.initialDocumentCode,
  });

  @override
  State<IncomingDocumentsScreen> createState() =>
      _IncomingDocumentsScreenState();
}

class _IncomingDocumentsScreenState extends State<IncomingDocumentsScreen> {
  late List<Document> _filteredDocuments;
  String _searchQuery = '';
  DateTime? _startDate;
  DateTime? _endDate;
  DateTime? _specificDate;
  final Set<int> _expandedTiles = {};
  late final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  late UploadQueueManager _uploadQueueManager;
  String? _username;
  RealtimeChannel? _docsChannel;
  List<String> _availableUsers = [];

  @override
  void initState() {
    super.initState();
    _searchController.text = _searchQuery;
    _filteredDocuments = widget.documents.where((doc) => doc.flowStage == 'incoming').toList();
    _subscribeToDocumentChanges();
    _filteredDocuments.sort((a, b) {
      final aDate = a.history.isNotEmpty ? a.history.last.timestamp : (a.createdAt ?? DateTime(1900));
      final bDate = b.history.isNotEmpty ? b.history.last.timestamp : (b.createdAt ?? DateTime(1900));
      return bDate.compareTo(aDate);
    });
    if (widget.initialDocumentCode != null) {
      _filteredDocuments = _filteredDocuments
          .where((d) => d.code == widget.initialDocumentCode)
          .toList();
      _searchQuery = widget.initialDocumentCode!;
      _searchController.text = widget.initialDocumentCode!;
    }
    _uploadQueueManager = UploadQueueManager();
    _uploadQueueManager.addListener(_onUploadChanged);
    _loadUsername();
    _loadAvailableUsers();
    // Start loading immediately
    _isLoading = true;
    // Simulate loading for better UX - keep it longer to show the indicator
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      // Kick off any uploads that are pending but not being processed.
      // This handles the case where auto-sync hasn't fired yet, or the queue
      // was re-seeded from SQLite after an app restart.
      _triggerPendingUploads();
    });
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

  void _onUploadChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _docsChannel?.unsubscribe();
    _uploadQueueManager.removeListener(_onUploadChanged);
    super.dispose();
  }

  void _subscribeToDocumentChanges() {
    _docsChannel = Supabase.instance.client
        .channel('documents:incoming')
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'documents',
          callback: (payload) { if (mounted) _refreshDocuments(); },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'documents',
          callback: (payload) { if (mounted) _refreshDocuments(); },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'documents',
          callback: (payload) { if (mounted) _refreshDocuments(); },
        )
        .subscribe();
  }

  @override
  void didUpdateWidget(IncomingDocumentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Rebuild when the documents list changes from parent
    if (oldWidget.documents != widget.documents) {
      setState(() {
        // Clear expanded tiles when list updates to avoid index issues
        _expandedTiles.clear();
        _updateFilteredDocuments();
      });
    }
  }

  void _updateFilteredDocuments() {
    setState(() {
      _filteredDocuments = searchAndFilterDocuments(
        widget.documents.where((doc) => doc.flowStage == 'incoming').toList(),
        searchQuery: _searchQuery,
        startDate: _startDate,
        endDate: _endDate,
        specificDate: _specificDate,
      );
      _filteredDocuments.sort((a, b) {
        final aDate = a.history.isNotEmpty ? a.history.last.timestamp : (a.createdAt ?? DateTime(1900));
        final bDate = b.history.isNotEmpty ? b.history.last.timestamp : (b.createdAt ?? DateTime(1900));
        return bDate.compareTo(aDate);
      });
    });
  }

  Future<void> _refreshDocuments() async {
    final allDocs = await CachedDocumentService().fetchDocuments();
    if (!mounted) return;
    setState(() {
      _expandedTiles.clear();
      _filteredDocuments = searchAndFilterDocuments(
        allDocs.where((doc) => doc.flowStage == 'incoming').toList(),
        searchQuery: _searchQuery,
        startDate: _startDate,
        endDate: _endDate,
        specificDate: _specificDate,
      );
      _filteredDocuments.sort((a, b) {
        final aDate = a.history.isNotEmpty ? a.history.last.timestamp : (a.createdAt ?? DateTime(1900));
        final bDate = b.history.isNotEmpty ? b.history.last.timestamp : (b.createdAt ?? DateTime(1900));
        return bDate.compareTo(aDate);
      });
    });
  }

  String _formatDateTime(DateTime dateTime) {
    // Timestamps are already in Philippine time
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final amPm = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final year = dateTime.year;
    return '$month/$day/$year $displayHour:$minute $amPm';
  }

Widget _buildUploadStatusIndicator(Document doc) {
  final queueManager = UploadQueueManager();
  final allUploads = queueManager.getAllItems()
      .where((item) => item['documentCode'] == doc.code)
      .toList();
  final uploadingUploads = allUploads.where((item) => item['status'] == 'uploading').toList();

  final totalFiles = doc.localImagePaths.length + doc.localFilePaths.length;
  final uploadedFiles = doc.imageUrls.length + doc.fileUrls.length;

  // Only show banner when uploading
  if (uploadingUploads.isNotEmpty) {
    return Row(
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
          'Uploading $uploadedFiles/$totalFiles files...',
          style: const TextStyle(
            fontSize: 12,
            color: Colors.orange,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
  return const SizedBox.shrink();
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
              Text(value, style: const TextStyle(fontSize: 14)),
            ],
          ),
        ),
      ],
    );
  }

  bool _titleExceedsMaxLines(String text, BuildContext context) {
    final TextStyle style = const TextStyle(fontWeight: FontWeight.w400);
    final double maxWidth = MediaQuery.of(context).size.width - 120; // approximate available width
    final TextPainter textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 2,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    return textPainter.didExceedMaxLines;
  }

  Future<void> _showTransferAssigneePicker(
    List<String> current,
    StateSetter setDialogState,
  ) async {
    final temp = List<String>.from(current);
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (ctx, setS) {
            final sorted = List<String>.from(_availableUsers)
              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
            final filtered = query.isEmpty
                ? sorted
                : sorted.where((u) => u.toLowerCase().contains(query.toLowerCase())).toList();
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.6,
              minChildSize: 0.4,
              maxChildSize: 0.85,
              builder: (_, scrollController) => Column(
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Row(
                      children: [
                        Icon(Icons.people_outline, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 10),
                        Text('Assign Personnel',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const Spacer(),
                        if (temp.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text('${temp.length} selected',
                                style: const TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      autofocus: false,
                      decoration: InputDecoration(
                        hintText: 'Search personnel...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      ),
                      onChanged: (v) => setS(() => query = v),
                    ),
                  ),
                  const Divider(height: 1),
                  // Pinned N/A option
                  Builder(builder: (_) {
                    final naSelected = temp.contains('N/A');
                    return CheckboxListTile(
                      title: const Text('N/A', style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic)),
                      subtitle: const Text('Not applicable / no specific assignee', style: TextStyle(fontSize: 11)),
                      value: naSelected,
                      activeColor: Colors.grey.shade600,
                      secondary: CircleAvatar(
                        radius: 16,
                        backgroundColor: naSelected ? Colors.grey.shade600 : Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: Icon(Icons.block, size: 15, color: naSelected ? Colors.white : Colors.grey.shade400),
                      ),
                      onChanged: (checked) => setS(() {
                        if (checked == true) {
                          temp..clear()..add('N/A');
                        } else {
                          temp.remove('N/A');
                        }
                      }),
                    );
                  }),
                  const Divider(height: 1),
                  Expanded(
                    child: _availableUsers.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : filtered.isEmpty
                            ? Center(child: Text('No match for "$query"', style: TextStyle(color: Colors.grey.shade500)))
                            : ListView.builder(
                                controller: scrollController,
                                itemCount: filtered.length,
                                itemBuilder: (_, i) {
                                  final user = filtered[i];
                                  final selected = temp.contains(user);
                                  return CheckboxListTile(
                                    title: Text(user, style: const TextStyle(fontSize: 14)),
                                    value: selected,
                                    activeColor: Theme.of(context).colorScheme.primary,
                                    secondary: CircleAvatar(
                                      radius: 16,
                                      backgroundColor: selected
                                          ? Theme.of(context).colorScheme.primary
                                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                                      child: Text(
                                        user[0].toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 13, fontWeight: FontWeight.bold,
                                          color: selected ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                    onChanged: (checked) => setS(() {
                                      if (checked == true) {
                                        temp..remove('N/A')..add(user);
                                      } else {
                                        temp.remove(user);
                                      }
                                    }),
                                  );
                                },
                              ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(ctx).viewInsets.bottom),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.pop(ctx, temp),
                            child: const Text('Confirm'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (result != null) {
      setDialogState(() => current
        ..clear()
        ..addAll(result));
    }
  }

  void _showTransferDialog(BuildContext context, int index) {
    final transferredByController = TextEditingController();
    final notesController = TextEditingController();
    final List<String> selectedNewAssignees = [];

    final List<String> cpdcoStaff = [
      'Sir Arnie', 'Rex', 'Floro', 'Arlene', 'Sharmaine', 'Path',
      'Jess', 'Emiliana', 'Pau', 'Chris', 'Wena', 'N/A', 'Arlyn', 'Dari',
    ];

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: SingleChildScrollView(
                child: Container(
                  width: 400,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.swap_horiz, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          const Text("Transfer Document", style: TextStyle(fontSize: 16)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // New Assignee — multi-select picker
                      InkWell(
                        onTap: () => _showTransferAssigneePicker(selectedNewAssignees, setState),
                        borderRadius: BorderRadius.circular(12),
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'New Assignee',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                            prefixIcon: const Icon(Icons.people_outline, size: 20),
                            suffixIcon: Icon(Icons.arrow_drop_down, color: Theme.of(context).colorScheme.primary),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          ),
                          child: selectedNewAssignees.isEmpty
                              ? Text('Tap to select personnel',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                                    fontStyle: FontStyle.italic, fontSize: 14,
                                  ))
                              : Wrap(
                                  spacing: 6, runSpacing: 6,
                                  children: selectedNewAssignees.map((a) {
                                    final isNA = a == 'N/A';
                                    return Chip(
                                      avatar: CircleAvatar(
                                        backgroundColor: isNA ? Colors.grey.shade500 : Theme.of(context).colorScheme.primary,
                                        child: isNA
                                            ? const Icon(Icons.block, size: 12, color: Colors.white)
                                            : Text(a[0].toUpperCase(),
                                                style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                                      ),
                                      label: Text(a, style: TextStyle(fontSize: 12, fontStyle: isNA ? FontStyle.italic : FontStyle.normal)),
                                      backgroundColor: isNA ? Colors.grey.shade200 : Theme.of(context).colorScheme.primaryContainer,
                                      labelStyle: TextStyle(color: isNA ? Colors.grey.shade700 : Theme.of(context).colorScheme.onPrimaryContainer),
                                      padding: const EdgeInsets.symmetric(horizontal: 4),
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    );
                                  }).toList(),
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      RawAutocomplete<String>(
                        textEditingController: transferredByController,
                        focusNode: FocusNode(),
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          if (textEditingValue.text == '') {
                            return const Iterable<String>.empty();
                          }
                          return cpdcoStaff.where((String option) {
                            return option.toLowerCase().contains(
                              textEditingValue.text.toLowerCase(),
                            );
                          });
                        },
                        onSelected: (String selection) {
                          setState(
                            () => transferredByController.text = selection,
                          );
                        },
                        fieldViewBuilder:
                            (
                              BuildContext context,
                              TextEditingController textEditingController,
                              FocusNode focusNode,
                              VoidCallback onFieldSubmitted,
                            ) {
                              return TextField(
                                controller: textEditingController,
                                focusNode: focusNode,
                                decoration: InputDecoration(
                                  labelText: "Transferred By",
                                  prefixIcon: const Icon(Icons.person),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              );
                            },
                        optionsViewBuilder:
                            (
                              BuildContext context,
                              AutocompleteOnSelected<String> onSelected,
                              Iterable<String> options,
                            ) {
                              return Align(
                                alignment: Alignment.topLeft,
                                child: Material(
                                  elevation: 4.0,
                                  child: SizedBox(
                                    width: 350,
                                    height: (options.length * 56.0 + 16.0).clamp(
                                      0.0,
                                      200.0,
                                    ),
                                    child: ListView.builder(
                                      padding: const EdgeInsets.all(8.0),
                                      itemCount: options.length,
                                      itemBuilder:
                                          (BuildContext context, int index) {
                                            final String option = options
                                                .elementAt(index);
                                            return GestureDetector(
                                              onTap: () {
                                                onSelected(option);
                                              },
                                              child: ListTile(
                                                title: Text(option),
                                              ),
                                            );
                                          },
                                    ),
                                  ),
                                ),
                              );
                            },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: notesController,
                        decoration: InputDecoration(
                          labelText: "Notes (Optional)",
                          prefixIcon: const Icon(Icons.note),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text("Cancel"),
                          ),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.send),
                            label: const Text("Transfer", style: TextStyle(fontSize: 10)),
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () {
                              if (selectedNewAssignees.isNotEmpty &&
                                  transferredByController.text.isNotEmpty) {
                                Navigator.of(context).pop();
                                final assigneeText = selectedNewAssignees.join(', ');
                                widget.transferDocument(
                                  index,
                                  assigneeText,
                                  transferredByController.text,
                                  notes: notesController.text.isNotEmpty
                                      ? notesController.text
                                      : null,
                                );
                                final notifyAssignees = selectedNewAssignees.where((a) => a != 'N/A').toList();
                                if (notifyAssignees.isNotEmpty) {
                                  final doc = _filteredDocuments[index];
                                  SupabaseService().scheduleAssignmentNotification(
                                    doc.code,
                                    doc.title ?? 'Document',
                                    notifyAssignees,
                                  );
                                }
                                _updateFilteredDocuments();
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showStatusUpdateDialog(BuildContext context, int index) async {
    String? selectedStatus;
    DateTime? selectedDeadline;
    final cabinetController = TextEditingController();
    final notesController = TextEditingController();
    final complianceAssigneeController = TextEditingController();

    final connectivityService = ConnectivityService();
    final isOnline = await connectivityService.isOnline;

    final List<String> allStatusOptions = [
      'Received',
      'In Progress',
      'Under Review',
      'Approved',
      'Action Required',
      'Returned',
      'Completed',
      'Filed',
      'Urgent',
      'For Compliance',
    ];

    final List<String> statusOptions = isOnline
        ? allStatusOptions
        : allStatusOptions.where((status) => status != 'Urgent' && status != 'For Compliance').toList();

    final List<String> cpdcoStaff = [
      'Sir Arnie',
      'Rex',
      'Floro',
      'Arlene',
      'Sharmaine',
      'Path',
      'Jess',
      'Emiliana',
      'Pau',
      'Chris',
      'Wena',
      'N/A',
      'Arlyn',
      'Dari',
    ];



    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: SingleChildScrollView(
                child: Container(
                  width: 400,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.edit_document,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            "Update Document Status",
                            style: TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: selectedStatus,
                        decoration: InputDecoration(
                          labelText: "New Status",
                          prefixIcon: const Icon(Icons.flag),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: statusOptions.map((String option) {
                          return DropdownMenuItem<String>(
                            value: option,
                            child: Text(option),
                          );
                        }).toList(),
                        onChanged: (String? value) {
                          setState(() {
                            selectedStatus = value;
                            if (value != 'For Compliance') {
                              selectedDeadline = null; // Clear deadline if not For Compliance
                            }
                          });
                        },
                      ),
                      if (selectedStatus == 'For Compliance') ...[
                        const SizedBox(height: 16),
                        TextField(
                          readOnly: true,
                          controller: TextEditingController(
                            text: selectedDeadline != null
                                ? "${selectedDeadline!.month}/${selectedDeadline!.day}/${selectedDeadline!.year} ${selectedDeadline!.hour.toString().padLeft(2, '0')}:${selectedDeadline!.minute.toString().padLeft(2, '0')}"
                                : '',
                          ),
                          decoration: InputDecoration(
                            labelText: "Compliance Deadline",
                            hintText: "Select date and time",
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            suffixIcon: const Icon(Icons.calendar_today),
                          ),
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: selectedDeadline ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (date != null) {
                              final time = await showTimePicker(
                                context: context,
                                initialTime: selectedDeadline != null ? TimeOfDay.fromDateTime(selectedDeadline!) : const TimeOfDay(hour: 9, minute: 0),
                              );
                              if (time != null) {
                                setState(() {
                                  selectedDeadline = DateTime(
                                    date.year,
                                    date.month,
                                    date.day,
                                    time.hour,
                                    time.minute,
                                  );
                                });
                              }
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        RawAutocomplete<String>(
                          textEditingController: complianceAssigneeController,
                          focusNode: FocusNode(),
                          optionsBuilder: (TextEditingValue textEditingValue) {
                            if (textEditingValue.text == '') {
                              return const Iterable<String>.empty();
                            }
                            return cpdcoStaff.where((String option) {
                              return option.toLowerCase().contains(
                                textEditingValue.text.toLowerCase(),
                              );
                            });
                          },
                          onSelected: (String selection) {
                            setState(() => complianceAssigneeController.text = selection);
                          },
                          fieldViewBuilder:
                              (
                                BuildContext context,
                                TextEditingController textEditingController,
                                FocusNode focusNode,
                                VoidCallback onFieldSubmitted,
                              ) {
                                return TextField(
                                  controller: textEditingController,
                                  focusNode: focusNode,
                                  decoration: InputDecoration(
                                    labelText: "Compliance Assignee",
                                    hintText: "Select CPDCO staff member",
                                    prefixIcon: const Icon(Icons.person),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                );
                              },
                          optionsViewBuilder:
                              (
                                BuildContext context,
                                AutocompleteOnSelected<String> onSelected,
                                Iterable<String> options,
                              ) {
                                return Align(
                                  alignment: Alignment.topLeft,
                                  child: Material(
                                    elevation: 4.0,
                                    child: SizedBox(
                                      width: 350,
                                      height: (options.length * 56.0 + 16.0).clamp(
                                        0.0,
                                        200.0,
                                      ),
                                      child: ListView.builder(
                                        padding: const EdgeInsets.all(8.0),
                                        itemCount: options.length,
                                        itemBuilder:
                                            (BuildContext context, int index) {
                                              final String option = options
                                                  .elementAt(index);
                                              return GestureDetector(
                                                onTap: () {
                                                  onSelected(option);
                                                },
                                                child: ListTile(
                                                  title: Text(option),
                                                ),
                                              );
                                            },
                                      ),
                                    ),
                                  ),
                                );
                              },
                        ),
                      ],
                      if (selectedStatus == 'Filed') ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: cabinetController,
                          decoration: InputDecoration(
                            labelText: "File Location",
                            hintText: "Enter shelf info",
                            prefixIcon: const Icon(Icons.inventory),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),
                      TextField(
                        controller: notesController,
                        decoration: InputDecoration(
                          labelText: "Notes (Optional)",
                          prefixIcon: const Icon(Icons.note),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text("Cancel"),
                          ),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.update),
                            label: const Text("Update", style: TextStyle(fontSize: 10)),
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () {
                              if (selectedStatus != null &&
                                  _username != null && _username!.isNotEmpty) {
                                // Validate compliance assignee if status is For Compliance
                                if (selectedStatus == 'For Compliance' &&
                                    (complianceAssigneeController.text.isEmpty)) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Please select a compliance assignee'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                  return;
                                }

                                String? combinedNotes = notesController.text.isNotEmpty
                                    ? notesController.text
                                    : null;
                                if (selectedStatus == 'Filed' &&
                                    cabinetController.text.isNotEmpty) {
                                  combinedNotes = combinedNotes != null
                                      ? '$combinedNotes\nFiled in: ${cabinetController.text}'
                                      : 'Filed in: ${cabinetController.text}';
                                }
                                widget.updateDocumentStatus(
                                  index,
                                  selectedStatus!,
                                  _username!,
                                  notes: combinedNotes,
                                  complianceDeadline: selectedDeadline,
                                  complianceAssignee: selectedStatus == 'For Compliance'
                                      ? complianceAssigneeController.text
                                      : null,
                                );
                                Navigator.of(context).popUntil((route) => route.isFirst);
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showLocationUpdateDialog(int idx) async {
    final doc = _filteredDocuments[idx];
    final cabinetNames = await CabinetService().fetchCabinetNames();
    if (!mounted) return;
    String? selected = doc.cabinetLocation;
    final folderController = TextEditingController(text: doc.folderTitle ?? '');
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(children: [
            Icon(Icons.inventory_2_outlined, color: Theme.of(ctx).colorScheme.primary),
            const SizedBox(width: 8),
            const Text("Update Location"),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              cabinetNames.isEmpty
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
                final folderValue = folderController.text.trim().isEmpty ? null : folderController.text.trim();
                await CachedDocumentService().updateDocument(doc.code, {'cabinet_location': selected, 'folder_title': folderValue});
                if (mounted) setState(() {
                  _filteredDocuments[idx] = doc.copyWith(cabinetLocation: selected);
                  _filteredDocuments[idx].folderTitle = folderValue;
                });
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
    final folderController = TextEditingController(text: doc.heldByFolder ?? '');
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
              await CachedDocumentService().updateDocument(doc.code, {'held_by': heldByValue, 'held_by_folder': folderValue});
              if (mounted) setState(() {
                _filteredDocuments[idx].heldBy = heldByValue;
                _filteredDocuments[idx].heldByFolder = folderValue;
              });
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void _showImageDialog(BuildContext context, Document document) {
    if (_username != null && _username!.isNotEmpty) {
      AttachmentViewService.recordView(
        documentCode: document.code,
        username: _username!,
        attachmentType: 'image',
      );
    }
    ScrollableImageViewer.show(
      context,
      imageUrls: document.imageUrls,
      fileNames: document.fileNames,
    );
  }

  Future<void> _shareDocument(Document doc) async {
    final title = (doc.title != null && doc.title!.isNotEmpty)
        ? '${doc.type} - ${doc.title}'
        : doc.type;

    if (doc.imageUrls.isEmpty && doc.fileUrls.isEmpty) {
      Share.share(title, subject: title);
      return;
    }

    // Web: Google Drive blocks cross-origin fetches (CORS). Share view links instead.
    if (kIsWeb) {
      String? extractFileId(String url) {
        if (url.contains('uc?id=')) return Uri.parse(url).queryParameters['id'];
        final m = RegExp(r'/file/d/([a-zA-Z0-9_-]+)').firstMatch(url);
        if (m != null) return m.group(1);
        if (RegExp(r'^[a-zA-Z0-9_-]{20,}$').hasMatch(url)) return url;
        return null;
      }
      final viewLinks = [...doc.imageUrls, ...doc.fileUrls]
          .map(extractFileId)
          .whereType<String>()
          .map((id) => 'https://drive.google.com/file/d/$id/view')
          .toList();
      final shareText = viewLinks.isEmpty ? title : '$title\n\n${viewLinks.join('\n')}';
      await Clipboard.setData(ClipboardData(text: shareText));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(viewLinks.isEmpty ? 'Title copied to clipboard' : 'Links copied to clipboard'),
          duration: const Duration(seconds: 4),
        ),
      );
      Share.share(shareText, subject: title);
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(children: [
          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
          SizedBox(width: 12),
          Text('Preparing files to share...'),
        ]),
        duration: Duration(seconds: 60),
      ),
    );

    try {
      final tempDir = await getTemporaryDirectory();
      final xFiles = <XFile>[];
      final safeTitle = title.replaceAll(RegExp(r'[<>:"/\\|?*\r\n]'), '').replaceAll(RegExp(r'\s+'), '_').trim();

      // Download images through the Supabase proxy, which authenticates with
      // the service account — the same mechanism used by the in-app image viewer.
      // Direct Google Drive downloads are not possible because the folders are private.
      Future<List<int>?> fetchImageViaProxy(String imageUrl) async {
        try {
          final fileId = imageUrl.contains('drive.google.com/uc?id=')
              ? Uri.parse(imageUrl).queryParameters['id'] ?? imageUrl
              : imageUrl;
          final proxyUrl = GoogleDriveService.generateProxyUrl(fileId);
          final res = await http.get(Uri.parse(proxyUrl)).timeout(const Duration(seconds: 30));
          if (res.statusCode != 200) return null;
          if ((res.headers['content-type'] ?? '').contains('text/html')) return null;
          return res.bodyBytes;
        } catch (_) {
          return null;
        }
      }

      for (int i = 0; i < doc.imageUrls.length; i++) {
        final bytes = await fetchImageViaProxy(doc.imageUrls[i]);
        if (bytes != null) {
          final mimeType = _detectMimeType(bytes);
          final ext = mimeType == 'image/png' ? 'png' : 'jpg';
          final file = File('${tempDir.path}/${safeTitle}_${i + 1}.$ext');
          await file.writeAsBytes(bytes);
          xFiles.add(XFile(file.path, mimeType: mimeType));
        }
      }

      // PDFs → Google Drive view links (no download; Messenger can't open PDFs natively)
      String? toViewLink(String url) {
        if (url.contains('uc?id=')) {
          final id = Uri.parse(url).queryParameters['id'];
          if (id != null) return 'https://drive.google.com/file/d/$id/view';
          return null;
        }
        final m = RegExp(r'/file/d/([a-zA-Z0-9_-]+)').firstMatch(url);
        if (m != null) return 'https://drive.google.com/file/d/${m.group(1)}/view';
        if (RegExp(r'^[a-zA-Z0-9_-]{20,}$').hasMatch(url)) return 'https://drive.google.com/file/d/$url/view';
        return null;
      }

      final pdfLinks = <String>[];
      for (final fileUrl in doc.fileUrls) {
        final link = toViewLink(fileUrl);
        if (link != null) pdfLinks.add(link);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      // Clipboard: title + any PDF links so user can paste them in Messenger
      final clipboardText = pdfLinks.isEmpty
          ? title
          : '$title\n\n${pdfLinks.join('\n')}';
      await Clipboard.setData(ClipboardData(text: clipboardText));

      if (mounted) {
        final msg = pdfLinks.isEmpty
            ? 'Title copied to clipboard — paste it as your message in Messenger'
            : 'PDF links copied to clipboard — paste them in Messenger after sending the images';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 5)),
        );
      }

      if (xFiles.isNotEmpty) {
        // Omit text: title — Messenger drops attached files when a text extra is present.
        await Share.shareXFiles(xFiles, subject: title);
      } else if (pdfLinks.isNotEmpty) {
        await Share.share(clipboardText, subject: title);
      } else {
        Share.share(title, subject: title);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      SnackbarUtils.showErrorSnackBar(context, 'Failed to prepare files for sharing');
    }
  }

  /// Detects image MIME type from magic bytes so files are saved with the correct
  /// extension and MIME type before being handed to the share sheet.
  String _detectMimeType(List<int> bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      return 'image/png';
    }
    return 'image/jpeg';
  }

  void _downloadImage(BuildContext context, String imageUrl) async {
    try {
      await ImageDownloadService.downloadAndSave(imageUrl);

      if (context.mounted) {
        SnackbarUtils.showSuccessSnackBar(
          context,
          'Image saved to gallery',
          duration: const Duration(seconds: 4),
        );
      }
    } catch (e) {
      if (context.mounted) {
        SnackbarUtils.showErrorSnackBar(
          context,
          e.toString().replaceAll('Exception: ', ''),
        );
      }
    }
  }

  void _showFileDialog(BuildContext context, Document document) {
    final allFiles = <String>[];
    final allNames = <String>[];
    if (document.filePath != null) {
      allFiles.add(document.filePath!);
      allNames.add(document.fileName ?? document.filePath!.split('/').last.split('\\').last);
    }
    for (int i = 0; i < document.fileUrls.length; i++) {
      allFiles.add(document.fileUrls[i]);
      if (i < document.fileNames.length) {
        allNames.add(document.fileNames[i]);
      } else {
        allNames.add(document.fileUrls[i].split('/').last.split('\\').last);
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select File to View'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: allFiles.length,
            itemBuilder: (context, index) {
              final filePath = allFiles[index];
              final fileName = allNames[index];
              return ListTile(
                leading: const Icon(Icons.attach_file),
                title: Text(fileName),
                onTap: () {
                  Navigator.pop(context);
                  _viewFile(filePath, title: document.title ?? document.type, documentCode: document.code);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  /// Extract file ID from various Google Drive URL formats
  String? _extractFileId(String url) {
    if (url.contains('drive.google.com')) {
      final uri = Uri.parse(url);
      if (url.contains('/file/d/')) {
        // Format: https://drive.google.com/file/d/FILE_ID/view
        final segments = uri.pathSegments;
        final fileIndex = segments.indexOf('d');
        if (fileIndex != -1 && fileIndex + 1 < segments.length) {
          return segments[fileIndex + 1];
        }
      } else if (url.contains('uc?id=')) {
        // Format: https://drive.google.com/uc?id=FILE_ID
        return uri.queryParameters['id'];
      }
    }
    // Assume it's already a file ID if it matches the pattern
    if (RegExp(r'^[a-zA-Z0-9_-]{20,}$').hasMatch(url)) {
      return url;
    }
    return null;
  }

  void _viewFile(String filePath, {String title = 'Document', String? documentCode}) async {
    try {
      final fileId = _extractFileId(filePath);
      if (fileId == null) {
        SnackbarUtils.showErrorSnackBar(context, 'Invalid file format');
        return;
      }
      if (documentCode != null && _username != null && _username!.isNotEmpty) {
        AttachmentViewService.recordView(
          documentCode: documentCode,
          username: _username!,
          attachmentType: 'pdf',
        );
      }
      if (kIsWeb) {
        final uri = Uri.parse('https://drive.google.com/file/d/$fileId/view');
        final canLaunch = await canLaunchUrl(uri);
        if (!mounted) return;
        if (canLaunch) {
          await launchUrl(uri);
        } else {
          SnackbarUtils.showErrorSnackBar(context, 'Could not open file');
        }
        return;
      }
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(fileId: fileId, fileName: title),
        ),
      );
    } catch (e) {
      SnackbarUtils.showErrorSnackBar(context, 'Could not open file');
    }
  }

  Future<void> _loadUsername() async {
    final username = await AuthService.getUsername();
    if (username != null && username.isNotEmpty) {
      setState(() {
        _username = username;
      });
    }
  }

  Future<void> _loadAvailableUsers() async {
    final users = await SupabaseService().fetchAllUsernames();
    if (mounted) setState(() => _availableUsers = users);
  }



  void _showViewersDialog(BuildContext context, String documentCode) {
    showDialog(
      context: context,
      builder: (_) => _ViewersDialog(documentCode: documentCode),
    );
  }

  void _showFilterDialog(BuildContext context, StateSetter setState) {
    DocumentFilterDialog.show(
      context,
      specificDate: _specificDate,
      startDate: _startDate,
      endDate: _endDate,
      onApply: (specific, start, end) {
        setState(() {
          _specificDate = specific;
          _startDate = start;
          _endDate = end;
        });
        _updateFilteredDocuments();
      },
    );
  }


  Widget _statusIcon(String status) {
    switch (status) {
      case 'Urgent':
        return const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20);
      case 'Completed':
        return const Icon(Icons.check_circle_outline, color: Colors.green, size: 20);
      case 'For Compliance':
        return const Icon(Icons.access_time, color: Colors.orange, size: 20);
      default:
        return const Icon(Icons.description_outlined, color: Color(0xFF4988C4), size: 20);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConnectivityBanner(
      child: Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AddDocumentScreen(incoming: true),
            ),
          );
          await _refreshDocuments();
          if (widget.onRefresh != null) {
            widget.onRefresh!();
          }
        },
        backgroundColor: const Color(0xFFFFB74D),
        child: const Icon(Icons.add),
      ),
      appBar: AppBar(
        title: const Text("Incoming Documents"),
        backgroundColor: const Color(0xFFFFB74D), // Pastel orange
        foregroundColor: Colors.white,

        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: DocumentSearchBar(
            controller: _searchController,
            onSearch: (query) {
              _searchQuery = query;
              _updateFilteredDocuments();
            },
            onFilterTap: () => _showFilterDialog(context, setState),
            hasActiveFilter: _startDate != null || _endDate != null || _specificDate != null,
            resultCount: _filteredDocuments.length,
            totalCount: widget.documents.where((d) => d.flowStage == 'incoming').length,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (widget.onRefresh != null) {
            widget.onRefresh!();
          }
        },
        child: _isLoading
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading documents...', style: TextStyle(fontSize: 16)),
                  ],
                ),
              )
            : _filteredDocuments.isEmpty
            ? Column(
              children: [
                UploadStatusBanner(onAllUploadsComplete: widget.onRefresh),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.document_scanner,
                          size: 80,
                          color: const Color(0xFFFFB74D).withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "No incoming documents yet",
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Incoming documents will appear here",
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
            : Column(
              children: [
                UploadStatusBanner(onAllUploadsComplete: widget.onRefresh),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: _filteredDocuments.length,
                    separatorBuilder: (_, _) => const Divider(height: 8, thickness: 1),
                    itemBuilder: (context, index) {
                      final doc = _filteredDocuments[index];
                      final originalIndex = widget.documents.indexOf(doc);
                return Container(
                  color: doc.needsSync ? Colors.yellow[100] : null,
                  child: ExpansionTile(
                          onExpansionChanged: (expanded) {
                            setState(() {
                              if (expanded) {
                                _expandedTiles.add(index);
                              } else {
                                _expandedTiles.remove(index);
                              }
                            });
                          },
                          leading: _statusIcon(doc.status),
                          title: Row(
                            children: [
                              Expanded(
                                child: _expandedTiles.contains(index)
                                  ? GestureDetector(
                                      onTap: () {
                                        Clipboard.setData(ClipboardData(text: doc.code));
                                        SnackbarUtils.showInfoSnackBar(context, 'Code copied to clipboard');
                                      },
                                      child: Text(
                                        doc.code,
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.blue, decoration: TextDecoration.underline),
                                      ),
                                    )
                                  : Text(
                                      doc.code,
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                    ),
                              ),
                              if (doc.needsSync) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.sync,
                                  size: 16,
                                  color: Colors.orange,
                                ),
                              ],
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (doc.title != null && doc.title!.isNotEmpty)
                                Text(
                                  "${doc.type} - ${doc.title}",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  if (doc.flowStage == 'incoming' && !doc.incoming) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2196F3).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: const Color(0xFF2196F3).withValues(alpha: 0.4)),
                                      ),
                                      child: const Text(
                                        'Fr. Outgoing',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Color(0xFF2196F3),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.blueGrey.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      doc.assignedTo,
                                      style: const TextStyle(fontSize: 10, color: Colors.blueGrey, fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                  if (doc.imageUrls.isEmpty && doc.fileUrls.isEmpty && doc.filePath == null && doc.localImagePaths.isEmpty && doc.localFilePaths.isEmpty) ...[
                                    const SizedBox(width: 6),
                                    Tooltip(
                                      message: 'No attachment',
                                      child: Icon(Icons.image_not_supported_outlined, size: 12, color: Colors.grey[400]),
                                    ),
                                  ],
                                ],
                              ),
                              _buildUploadStatusIndicator(doc),
                            ],
                          ),
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceVariant.withOpacity(0.3),
                                borderRadius: const BorderRadius.only(
                                  bottomLeft: Radius.circular(12),
                                  bottomRight: Radius.circular(12),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          ElevatedButton.icon(
                                            icon: const Icon(Icons.forward),
                                            label: const Text("Move to Outgoing"),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFF90C67C),
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                            ),
                                            onPressed: () {
                                              showDialog(
                                                context: context,
                                                builder: (dialogContext) => MoveDocumentDialog(
                                                  document: doc,
                                                  moveAction: 'Move to Outgoing',
                                                  syncDocument: widget.syncDocument,
                                                  onDocumentMoved: () async {
                                                    if (_username != null && _username!.isNotEmpty) {
                                                      // Move the document to outgoing
                                                      widget.documents[originalIndex].flowStage = 'outgoing';
                                                    // Update filtered documents to remove the moved document immediately
                                                      _updateFilteredDocuments();
                                                      // Update the document in the service
                                                      final documentService = CachedDocumentService();
                                                      await documentService.updateDocument(widget.documents[originalIndex].code, {'flow_stage': widget.documents[originalIndex].flowStage});
                                                      // Add history entry
                                                      final historyEntry = HistoryEntry(
                                                        action: 'Moved to Outgoing',
                                                        person: _username!,
                                                        timestamp: getPhilippineTime(),
                                                      );
                                                      await documentService.addHistoryEntry(widget.documents[originalIndex].code, historyEntry);
                                                      // Update local document history
                                                      widget.documents[originalIndex].history.add(historyEntry);
                                                      await CachedDocumentService().updateDocument(widget.documents[originalIndex].code, {'needs_sync': true});

                                                      // Automatically sync all documents
                                                      await widget.syncAllDocuments();
                                                      // Force UI refresh to show updated history
                                                      setState(() {});
                                                      // Close the dialog
                                                      Navigator.of(dialogContext).pop();
                                                    }
                                                  },
                                                ),
                                              );
                                            },
                                          ),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                "Receiving Date:",
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              Text(
                                                doc.receivingDate != null
                                                    ? _formatDateTime(doc.receivingDate!)
                                                    : "Not set",
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      
                                  if (_titleExceedsMaxLines("${doc.type} - ${doc.title}", context)) ...[
                                    _buildDetailRow(Icons.title, "Document Title", "${doc.type} - ${doc.title}"),
                                  ],
                                  const SizedBox(height: 8),
                                  _buildDetailRow(Icons.person, "From", doc.fromOrTo),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(child: _buildDetailRow(Icons.inventory_2_outlined, "Location", [doc.cabinetLocation ?? 'Not assigned', if ((doc.folderTitle ?? '').isNotEmpty) doc.folderTitle!].join(' | '))),
                                      ViewInCabinetButton(document: doc),
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
                                      Expanded(child: _buildDetailRow(Icons.person_pin_outlined, "Held by", [doc.heldBy ?? 'Not specified', if ((doc.heldByFolder ?? '').isNotEmpty) doc.heldByFolder!].join(' | '))),
                                      IconButton(
                                        icon: const Icon(Icons.edit, size: 18),
                                        onPressed: () => _showHeldByDialog(index),
                                        tooltip: "Update Holder",
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildDetailRow(
                                          Icons.assignment_ind,
                                          "Assigned To",
                                          doc.assignedTo,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.swap_horiz),
                                        onPressed: () => _showTransferDialog(
                                          context,
                                          originalIndex,
                                        ),
                                        tooltip: "Transfer Document",
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildDetailRow(
                                          Icons.info,
                                          "Status",
                                          doc.status,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.edit),
                                        onPressed: () => _showStatusUpdateDialog(
                                          context,
                                          originalIndex,
                                        ),
                                        tooltip: "Update Status",
                                      ),
                                    ],
                                  ),
                                  if (doc.status == 'For Compliance' && doc.complianceDeadline != null) ...[
                                    const SizedBox(height: 8),
                                    _buildDetailRow(
                                      Icons.schedule,
                                      "Compliance Deadline",
                                      _formatDateTime(doc.complianceDeadline!),
                                    ),
                                  ],
                                  if (doc.imageUrls.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                  ],
                                  if (doc.remarksList.isNotEmpty) ...[
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Icon(Icons.comment, size: 20, color: Theme.of(context).colorScheme.primary),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                "Remarks",
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w500,
                                                  color: Theme.of(context).colorScheme.primary,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              ...doc.remarksList.map((remark) => Padding(
                                                padding: const EdgeInsets.only(bottom: 4),
                                                child: Text(
                                                  remark,
                                                  style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                                                ),
                                              )),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ] else ...[
                                    _buildDetailRow(
                                      Icons.comment,
                                      "Remarks",
                                      doc.remarks,
                                    ),
                                  ],
                                  const SizedBox(height: 4),
                                  _buildDetailRow(
                                    Icons.receipt,
                                    "Received by",
                                    doc.person,
                                  ),
                                  if (doc.referenceLink != null && doc.referenceLink!.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      GestureDetector(
                                        onTap: () async {
                                          final uri = Uri.parse(doc.referenceLink!);
                                          if (await canLaunchUrl(uri)) {
                                            await launchUrl(uri);
                                          }
                                        },
                                        child: Row(
                                          children: [
                                            const Icon(Icons.link, color: Colors.blue),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                doc.referenceLink!,
                                                style: const TextStyle(
                                                  color: Colors.blue,
                                                  decoration: TextDecoration.underline,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  const SizedBox(height: 8),
                                  ExpansionTile(
                                    leading: const Icon(Icons.history),
                                    title: Text(
                                      "Document History (" +
                                          doc.history.length.toString() +
                                          ")",
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

                                      // Create display items, skipping "Added Remark" and collecting remarks for move entries
                                          List<Map<String, dynamic>> displayItems = [];
                                          int i = 0;

                                          while (i < entries.length) {
                                            final entry = entries[i];

                                            // Skip "Added Remark" entries entirely
                                            if (entry.action.startsWith('Added Remark ')) {
                                              i++;
                                              continue;
                                            }

                                            Map<String, dynamic> item = {'entry': entry, 'remarks': <String>[]};

                                            if (entry.action == 'Moved to Incoming' || entry.action == 'Moved to Outgoing') {
                                              // Collect subsequent "Added Remark" entries into this move
                                              int j = i + 1;
                                              while (j < entries.length && entries[j].action.startsWith('Added Remark ')) {
                                                final remarkNumber = int.tryParse(entries[j].action.split(' ').last);
                                                if (remarkNumber != null && remarkNumber <= doc.remarksList.length) {
                                                  item['remarks'].add(doc.remarksList[remarkNumber - 1]);
                                                }
                                                j++;
                                              }
                                              // Advance i to skip over the remarks we just bundled
                                              i = j;
                                            } else {
                                              i++;
                                            }

                                            displayItems.add(item);
                                          }

                                      return displayItems.reversed.map((item) {
                                        final entry = item['entry'] as HistoryEntry;
                                        final originalIndex = entries.indexOf(entry);
                                        String office = doc.fromOrTo;
                                        String personnel = doc.assignedTo;
                                        String? additionalNotes;

                                        // If the history entry has notes, parse them to get office and personnel (creation stores a snapshot there).
                                        if (entry.notes != null &&
                                            entry.notes!.isNotEmpty) {
                                          final parts = entry.notes!.split('|');
                                          if (originalIndex == 0) {
                                            // Creation: notes = "office|personnel"
                                            if (parts.length >= 2) {
                                              office = parts[0].trim();
                                              personnel = parts[1].trim();
                                            }
                                          } else {
                                            // Status change: notes = "office - personnel|additional"
                                            final officePersonnelStr = parts[0]
                                                .trim();
                                            final sepIndex = officePersonnelStr
                                                .lastIndexOf(' - ');
                                            if (sepIndex != -1) {
                                              office = officePersonnelStr
                                                  .substring(0, sepIndex)
                                                  .trim();
                                              personnel = officePersonnelStr
                                                  .substring(sepIndex + 3)
                                                  .trim();
                                            } else {
                                              final officePersonnel =
                                                  officePersonnelStr.split(' - ');
                                              if (officePersonnel.length >= 2) {
                                                office = officePersonnel[0].trim();
                                                personnel = officePersonnel[1].trim();
                                              }
                                            }
                                            if (parts.length > 1) {
                                              additionalNotes = parts
                                                  .sublist(1)
                                                  .join('|')
                                                  .trim();
                                            }
                                          }
                                        } else if (originalIndex == 0 && entry.action.startsWith('Document Created')) {
                                          // For outgoing creation entry without notes, parse from action
                                          final action = entry.action;
                                          final match = RegExp(r'Document Created and forwarded to (.+) c/o (.+)').firstMatch(action);
                                          if (match != null) {
                                            office = match.group(1)!.trim();
                                            personnel = match.group(2)!.trim();
                                          }
                                        }

                                        String mainLine;
                                        if (originalIndex == 0) {
                                          // Retain initial entry from respective screen
                                          if (doc.incoming) {
                                            mainLine = "Document Received";
                                          } else {
                                            mainLine = "Created and forwarded to $office c/o $personnel";
                                          }
                                        } else {
                                          if (entry.action == 'Moved to Outgoing' || entry.action == 'Moved to Incoming') {
                                            mainLine = entry.action;
                                          }
                                          else if (entry.action.startsWith('Transferred to ')) {
                                          // NEW branch
                                          mainLine = entry.action; // or parse office/personnel if needed

                                          }else if (entry.action.startsWith('Status changed to ') || entry.action.startsWith('For Compliance: ')) {
                                            mainLine = entry.action;
                                          } else {
                                            mainLine = entry.action; // fallback
                                          }
                                        }

                                        // Parse notes for move entries to extract remarks and attachments
                                        String? remarksText;
                                        String? attachmentsText;
                                        if ((entry.action == 'Moved to Outgoing' || entry.action == 'Moved to Incoming') && entry.notes != null) {
                                          final parts = entry.notes!.split(' | ');
                                          for (final part in parts) {
                                            if (part.startsWith('Remarks: ')) {
                                              remarksText = part.substring('Remarks: '.length);
                                            } else if (part.startsWith('Attachments: ')) {
                                              attachmentsText = part.substring('Attachments: '.length);
                                            }
                                          }
                                        }

                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 8,
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Icon(
                                                Icons.circle,
                                                size: 12,
                                                color: const Color(0xFFFFB74D),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      mainLine,
                                                      style: const TextStyle(
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                    Text(
                                                      originalIndex == 0
                                                          ? "by: ${entry.person}"
                                                          : "by: ${entry.person} | ${_formatDateTime(entry.timestamp)}",
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onSurface
                                                            .withOpacity(0.6),
                                                      ),
                                                    ),
                                                    if (remarksText != null && remarksText.isNotEmpty) ...[
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        "Remarks: $remarksText",
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontStyle: FontStyle.italic,
                                                          color: Theme.of(context)
                                                              .colorScheme
                                                              .onSurface
                                                              .withOpacity(0.7),
                                                        ),
                                                      ),
                                                    ],
                                                    if (attachmentsText != null && attachmentsText.isNotEmpty) ...[
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        "Attachments: $attachmentsText",
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                                        ),
                                                      ),
                                                    ],
                                                    if (entry.notes != null &&
                                                        entry.notes!.isNotEmpty &&
                                                        entry.action != 'Moved to Outgoing' &&
                                                        entry.action != 'Moved to Incoming') ...[
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        "Notes: ${entry.notes}",
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontStyle: FontStyle.italic,
                                                          color: Theme.of(context)
                                                              .colorScheme
                                                              .onSurface
                                                              .withOpacity(0.7),
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
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Wrap(
                                        spacing: 2,
                                        runSpacing: 2,
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        children: [
                                          if (_username == doc.person)
                                            ElevatedButton(
                                              onPressed: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (context) => EditDocumentScreen(document: doc),
                                                  ),
                                                ).then((_) {
                                                  if (widget.onRefresh != null) {
                                                    widget.onRefresh!();
                                                  }
                                                });
                                              },
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color.fromARGB(255, 78, 127, 218),
                                                foregroundColor: Colors.white,
                                                minimumSize: const Size(40, 36),
                                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                              ),
                                              child: const Icon(Icons.edit, size: 18),
                                            ),
                                          if (_username == doc.person)
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color.fromARGB(255, 218, 87, 78),
                                                foregroundColor: Colors.white,
                                                minimumSize: const Size(40, 36),
                                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                              ),
                                              onPressed: () async {
                                                final deleted = await confirmAndDeleteRecord(
                                                  context,
                                                  doc,
                                                  CachedDocumentService(),
                                                );
                                                if (deleted && mounted) {
                                                  setState(() {
                                                    _filteredDocuments.removeAt(index);
                                                  });
                                                  if (widget.onRefresh != null) {
                                                    widget.onRefresh!();
                                                  }
                                                }
                                              },
                                              child: const Icon(Icons.delete, size: 18),
                                            ),
                                          if (doc.imageUrls.isNotEmpty)
                                            ElevatedButton(
                                              onPressed: () => _showImageDialog(context, doc),
                                              style: ElevatedButton.styleFrom(
                                                minimumSize: const Size(40, 36),
                                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                              ),
                                              child: const Icon(Icons.image, size: 18),
                                            ),
                                          if (doc.filePath != null || doc.fileUrls.isNotEmpty)
                                            ElevatedButton(
                                              onPressed: () {
                                                final allFiles = <String>[];
                                                if (doc.filePath != null) allFiles.add(doc.filePath!);
                                                allFiles.addAll(doc.fileUrls);
                                                if (allFiles.length == 1) {
                                                  _viewFile(allFiles[0], title: doc.title ?? doc.type, documentCode: doc.code);
                                                } else {
                                                  _showFileDialog(context, doc);
                                                }
                                              },
                                              style: ElevatedButton.styleFrom(
                                                minimumSize: const Size(40, 36),
                                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                              ),
                                              child: const Icon(Icons.attach_file, size: 18),
                                            ),
                                          if (doc.imageUrls.isNotEmpty || doc.fileUrls.isNotEmpty)
                                            ElevatedButton(
                                              onPressed: () => _shareDocument(doc),
                                              style: ElevatedButton.styleFrom(
                                                minimumSize: const Size(40, 36),
                                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                              ),
                                              child: const Icon(Icons.share, size: 18),
                                            ),
                                        ],
                                      ),
                                      const Spacer(),
                                      if (doc.imageUrls.isNotEmpty || doc.fileUrls.isNotEmpty)
                                        IconButton(
                                          icon: const Icon(Icons.remove_red_eye_outlined, size: 20),
                                          tooltip: 'View who opened attachments',
                                          onPressed: () => _showViewersDialog(context, doc.code),
                                          style: IconButton.styleFrom(
                                            foregroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                          ),
                                        ),
                                    ],
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
      ),
      ),
      );

  }
}

// ---------------------------------------------------------------------------
// Viewers dialog — shows who viewed attachments for a document
// ---------------------------------------------------------------------------

class _ViewersDialog extends StatefulWidget {
  final String documentCode;

  const _ViewersDialog({required this.documentCode});

  @override
  State<_ViewersDialog> createState() => _ViewersDialogState();
}

class _ViewersDialogState extends State<_ViewersDialog> {
  late Future<List<AttachmentViewEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = AttachmentViewService.getViewers(widget.documentCode);
  }

  String _formatDate(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final amPm = h >= 12 ? 'PM' : 'AM';
    final displayH = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '${dt.month}/${dt.day}/${dt.year} $displayH:$m $amPm';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.remove_red_eye_outlined,
              color: Theme.of(context).colorScheme.primary, size: 20),
          const SizedBox(width: 8),
          const Text('Attachment Viewers', style: TextStyle(fontSize: 16)),
        ],
      ),
      content: SizedBox(
        width: 340,
        height: 260,
        child: FutureBuilder<List<AttachmentViewEntry>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final viewers = snap.data ?? [];
            if (viewers.isEmpty) {
              return const Center(
                child: Text(
                  'No views recorded yet',
                  style: TextStyle(color: Colors.grey),
                ),
              );
            }
            return ListView.separated(
              itemCount: viewers.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final v = viewers[i];
                return ListTile(
                  dense: true,
                  leading: Icon(
                    v.attachmentType == 'pdf'
                        ? Icons.picture_as_pdf_outlined
                        : Icons.image_outlined,
                    size: 20,
                    color: v.attachmentType == 'pdf'
                        ? Colors.red[400]
                        : Colors.blue[400],
                  ),
                  title: Text(v.username,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    '${v.attachmentType == 'pdf' ? 'PDF' : 'Image'} · ${_formatDate(v.viewedAt)}',
                    style: const TextStyle(fontSize: 11),
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        TextButton(
          onPressed: () => setState(() {
            _future = AttachmentViewService.getViewers(widget.documentCode);
          }),
          child: const Text('Refresh'),
        ),
      ],
    );
  }
}
