import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform, File;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_image_gallery_saver/flutter_image_gallery_saver.dart';

import '../models/document.dart';
import '../services/connectivity_service.dart';
import '../utils/search_filter_utils.dart';
import '../utils/snackbar_utils.dart';
import '../services/upload_queue_manager.dart';
import '../widgets/connectivity_banner.dart';
import '../utils/delete_utils.dart';
import '../services/cached_document_service.dart';
import '../services/auth_service.dart';
import '../utils/date_time_utils.dart';
import '../widgets/move_document_dialog.dart';
import '../services/google_drive_service.dart';
import '../config/supabase_config.dart';
import 'edit_document_screen.dart';
import 'add_document_screen.dart';

class IncomingDocumentsScreen extends StatefulWidget {
  final List<Document> documents;
  final Function(int, String, String, {String? notes}) transferDocument;
  final Function(int, String, String, {String? notes, DateTime? complianceDeadline, String? complianceAssignee}) updateDocumentStatus;
  // final Function(int, Document) editDocument;
  final Function(int) deleteDocument;
  final Function(String) syncDocument;
  final VoidCallback? onRefresh;
  final Future<void> Function() syncAllDocuments;

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
    _filteredDocuments = widget.documents.where((doc) => doc.flowStage == 'incoming').toList();
    _filteredDocuments.sort((a, b) {
      final aDate = a.history.isNotEmpty ? a.history.last.timestamp : (a.createdAt ?? DateTime(1900));
      final bDate = b.history.isNotEmpty ? b.history.last.timestamp : (b.createdAt ?? DateTime(1900));
      return bDate.compareTo(aDate);
    });
    _uploadQueueManager = UploadQueueManager();
    _uploadQueueManager.addListener(_onUploadChanged);
    _loadUsername();
    // Start loading immediately
    _isLoading = true;
    // Simulate loading for better UX - keep it longer to show the indicator
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  void _onUploadChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _uploadQueueManager.removeListener(_onUploadChanged);
    super.dispose();
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

  void _showTransferDialog(BuildContext context, int index) {
    final newAssigneeController = TextEditingController();
    final transferredByController = TextEditingController();
    final notesController = TextEditingController();

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
                            Icons.swap_horiz,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            "Transfer Document",
                            style: TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      RawAutocomplete<String>(
                        textEditingController: newAssigneeController,
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
                          setState(() => newAssigneeController.text = selection);
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
                                  labelText: "New Assignee",
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
                              if (newAssigneeController.text.isNotEmpty &&
                                  transferredByController.text.isNotEmpty) {
                                widget.transferDocument(
                                  index,
                                  newAssigneeController.text,
                                  transferredByController.text,
                                  notes: notesController.text.isNotEmpty
                                      ? notesController.text
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
                              firstDate: DateTime.now(),
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

  void _showImageDialog(BuildContext context, Document document) {
    final PageController pageController = PageController();
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox.expand(
          child: Stack(
            children: [
              PageView.builder(
                controller: pageController,
                itemCount: document.imageUrls.length,
                itemBuilder: (context, index) {
                  String fileName = index < document.fileNames.length ? document.fileNames[index] : 'Image ${index + 1}';

                  String normalizedFileId = GoogleDriveService.normalizeFileId(document.imageUrls[index]);
                  String proxyUrl = GoogleDriveService.generateProxyUrl(normalizedFileId);

                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          fileName,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Expanded(
                        child: InteractiveViewer(
                          child: Center(
                            child: CachedNetworkImage(
                              imageUrl: proxyUrl,
                              httpHeaders: {'Authorization': 'Bearer ${SupabaseConfig.supabaseAnonKey}'},
                              fit: BoxFit.contain,
                              placeholder: (context, url) => const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(),
                                    SizedBox(height: 16),
                                    Text(
                                      'Please wait...',
                                      style: TextStyle(
                                        color: Color.fromARGB(255, 56, 56, 56),
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              errorWidget: (context, url, error) => const Center(
                                child: Text('Failed to load image'),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              if (document.imageUrls.length > 1) ...[
                Positioned(
                  left: 10,
                  top: MediaQuery.of(context).size.height * 0.5 - 25,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.black, size: 30),
                    onPressed: () {
                      if (pageController.page! > 0) {
                        pageController.previousPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      }
                    },
                  ),
                ),
                Positioned(
                  right: 10,
                  top: MediaQuery.of(context).size.height * 0.5 - 25,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, color: Color.fromARGB(255, 0, 0, 0), size: 30),
                    onPressed: () {
                      if (pageController.page! < document.imageUrls.length - 1) {
                        pageController.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      }
                    },
                  ),
                ),
              ],
              Positioned(
                top: 40,
                right: 20,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.download, color: Colors.black, size: 30),
                      onPressed: () => _downloadImage(context, document.imageUrls.isNotEmpty ? document.imageUrls[0] : ''),
                      tooltip: 'Download Image',
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.black, size: 30),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  Future<int> _getAndroidVersion() async {
    if (!Platform.isAndroid) return 0;
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.version.sdkInt;
    } catch (e) {
      return 0;
    }
  }

  void _downloadImage(BuildContext context, String imageUrl) async {
    if (imageUrl.isEmpty) {
      SnackbarUtils.showErrorSnackBar(context, 'No image to download');
      return;
    }
    try {
      // Extract file ID from the URL
      String normalizedFileId = GoogleDriveService.normalizeFileId(imageUrl);
      // Build direct download URL
      String downloadUrl = 'https://drive.google.com/uc?id=$normalizedFileId&export=download';

      if (kIsWeb) {
        // Web: Open in browser
        final uri = Uri.parse(downloadUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          SnackbarUtils.showErrorSnackBar(context, 'Could not open download link');
        }
      } else {
        // Mobile: Request permissions and save to gallery using GallerySaver
        bool hasPermission = false;

        if (Platform.isAndroid) {
          final androidVersion = await _getAndroidVersion();
          if (androidVersion >= 33) {
            // Android 13+ (API 33+): Use granular photos permission
            final photosStatus = await Permission.photos.request();
            hasPermission = photosStatus.isGranted || photosStatus.isLimited;
          } else if (androidVersion >= 29) {
            // Android 10-12: Use storage permission (scoped storage)
            final storageStatus = await Permission.storage.request();
            hasPermission = storageStatus.isGranted;
          } else {
            // Android 9 and below: Need write external storage
            final status = await Permission.storage.request();
            hasPermission = status.isGranted;
          }
        } else {
          // iOS or other platforms
          final status = await Permission.photos.request();
          hasPermission = status.isGranted || status.isLimited;
        }

        if (hasPermission) {
          // Show loading indicator
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                    SizedBox(width: 16),
                    Text('Downloading and saving to gallery...'),
                  ],
                ),
                duration: Duration(seconds: 10),
              ),
            );
          }

          // Download image to temporary file first
          final tempDir = await getTemporaryDirectory();
          final fileName = 'doc_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final tempPath = '${tempDir.path}/$fileName';

          await Dio().download(downloadUrl, tempPath);

          // Read file as bytes and save to gallery
          final bytes = await File(tempPath).readAsBytes();
          await FlutterImageGallerySaver.saveImage(bytes);

          // Clean up temporary file
          try {
            await File(tempPath).delete();
          } catch (e) {
            // Ignore cleanup errors
          }

          if (context.mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            SnackbarUtils.showSuccessSnackBar(
              context,
              'Image saved to gallery',
              duration: const Duration(seconds: 5),
            );
          }
        } else {
          // Permission denied - show message
          if (context.mounted) {
            SnackbarUtils.showErrorSnackBar(
              context,
              'Photos permission required to download images',
            );
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        SnackbarUtils.showErrorSnackBar(context, 'Failed to download image: $e');
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
                  _viewFile(filePath);
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

  /// Build download URL for web platform
  String _buildDownloadUrl(String fileId) {
    return 'https://drive.google.com/uc?id=$fileId&export=download';
  }

  /// Build preview URL for mobile/desktop platforms
  String _buildPreviewUrl(String fileId) {
    return 'https://drive.google.com/file/d/$fileId/view?usp=sharing';
  }

  void _viewFile(String filePath) async {
    try {
      final fileId = _extractFileId(filePath);
      if (fileId == null) {
        SnackbarUtils.showErrorSnackBar(context, 'Invalid file format');
        return;
      }

      String urlToLaunch;
      if (kIsWeb) {
        // Web: Use direct download link
        urlToLaunch = _buildDownloadUrl(fileId);
      } else {
        // Mobile/Desktop: Use Drive preview link
        urlToLaunch = _buildPreviewUrl(fileId);
      }

      final uri = Uri.parse(urlToLaunch);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        SnackbarUtils.showErrorSnackBar(context, 'Could not open file');
      }
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



  void _showFilterDialog(BuildContext context, StateSetter setState) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => StatefulBuilder(
        builder: (context, dialogSetState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.filter_list,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              const Text("Filter Documents", style: TextStyle(fontSize: 16)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 16),
                TextField(
                  readOnly: true,
                  controller: TextEditingController(
                    text: _specificDate != null
                        ? "${_specificDate!.month}/${_specificDate!.day}/${_specificDate!.year}"
                        : '',
                  ),
                  decoration: InputDecoration(
                    labelText: "Specific Date",
                    prefixIcon: const Icon(Icons.calendar_today),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _specificDate ?? DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    dialogSetState(() {});
                    setState(() {
                      _specificDate = picked;
                      _startDate = null;
                      _endDate = null;
                      _updateFilteredDocuments();
                    });
                    Navigator.pop(context);
                  }
                },
                ),
                const SizedBox(height: 16),
                TextField(
                  readOnly: true,
                  controller: TextEditingController(
                    text: _startDate != null
                        ? "${_startDate!.month}/${_startDate!.day}/${_startDate!.year}"
                        : '',
                  ),
                  decoration: InputDecoration(
                    labelText: "Start Date",
                    prefixIcon: const Icon(Icons.calendar_today),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _startDate ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      dialogSetState(() {});
                      setState(() {
                        _startDate = picked;
                        _specificDate = null;
                        _updateFilteredDocuments();
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  readOnly: true,
                  controller: TextEditingController(
                    text: _endDate != null
                        ? "${_endDate!.month}/${_endDate!.day}/${_endDate!.year}"
                        : '',
                  ),
                  decoration: InputDecoration(
                    labelText: "End Date",
                    prefixIcon: const Icon(Icons.calendar_today),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _endDate ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      dialogSetState(() {});
                      setState(() {
                        _endDate = picked;
                        _specificDate = null;
                        _updateFilteredDocuments();
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                dialogSetState(() {});
                setState(() {
                  _specificDate = null;
                  _startDate = null;
                  _endDate = null;
                  _updateFilteredDocuments();
                });
                Navigator.pop(context);
              },
              child: const Text("Clear All"),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildGlobalUploadStatusIndicator() {
    final queueManager = UploadQueueManager();
    final allUploads = queueManager.getAllItems();
    final uploadingUploads = allUploads.where((item) => item['status'] == 'uploading').toList();
    final pendingUploads = allUploads.where((item) => item['status'] == 'pending').toList();

    if (uploadingUploads.isEmpty && pendingUploads.isEmpty) {
      return const SizedBox.shrink();
    }

    final totalUploading = uploadingUploads.length;
    final totalPending = pendingUploads.length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              totalUploading > 0
                  ? 'Uploading $totalUploading file${totalUploading > 1 ? 's' : ''}${totalPending > 0 ? ', $totalPending pending' : ''}...'
                  : 'Processing $totalPending upload${totalPending > 1 ? 's' : ''}...',
              style: TextStyle(
                fontSize: 14,
                color: Colors.orange[700],
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
          preferredSize: const Size.fromHeight(80),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      hintText: 'Search documents...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                setState(() {
                                  _searchQuery = '';
                                  _searchController.clear();
                                  _updateFilteredDocuments();
                                });
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.filter_list),
                  onPressed: () => _showFilterDialog(context, setState),
                  tooltip: 'Filter by Date',
                ),
              ],
            ),
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
                _buildGlobalUploadStatusIndicator(),
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
                _buildGlobalUploadStatusIndicator(),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: _filteredDocuments.length,
                    itemBuilder: (context, index) {
                      final doc = _filteredDocuments[index];
                      final originalIndex = widget.documents.indexOf(doc);
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  elevation: 2,
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
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFFFFB74D),
                            child: const Icon(
                              Icons.arrow_downward,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  "${doc.type} - ${doc.title}",
                                  style: const TextStyle(fontWeight: FontWeight.w400),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
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
                              Row(
                                children: [
                                  Icon(
                                    Icons.input,
                                    size: 16,
                                    color: const Color(0xFFFFB74D),
                                  ),
                                  const SizedBox(width: 4),
                                  if (_expandedTiles.contains(index))
                                  GestureDetector(
                                    onTap: () {
                                      Clipboard.setData(ClipboardData(text: doc.code));
                                      SnackbarUtils.showInfoSnackBar(
                                        context,
                                        'Code copied to clipboard',
                                      );
                                    },
                                    child: Text(
                                      doc.code,
                                      style: const TextStyle(
                                        color: Colors.blue, // visually indicate it's clickable
                                        decoration: TextDecoration.underline, // optional
                                      ),
                                    ),
                                  )
                                  else
                                  Text(
                                    doc.code,
                                  ),
                                ],
                              ),
                              if (doc.flowStage == 'incoming' && !doc.incoming) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2196F3).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFF2196F3).withOpacity(0.4)),
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
                              ],
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
                                  _buildDetailRow(Icons.send, "Mode", doc.mode),
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
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    alignment: WrapAlignment.center,
                                    children: [
                                      if (_username == doc.person)
                                        ElevatedButton.icon(
                                          icon: const Icon(Icons.edit),
                                          label: const SizedBox.shrink(),
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
                                            minimumSize: const Size(48, 40), // shrink width, fixed height
                                            padding: EdgeInsets.only(left:10),
                                            alignment: Alignment.center,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                          ),
                                        ),
                                      if (_username == doc.person)
                                        ElevatedButton.icon(
                                          icon: const Icon(Icons.delete),
                                          label: const SizedBox.shrink(),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color.fromARGB(
                                              255,
                                              218,
                                              87,
                                              78,
                                            ),
                                            foregroundColor: Colors.white,
                                            minimumSize: const Size(48, 40), // shrink width, fixed height
                                            padding: EdgeInsets.only(left:10),
                                            alignment: Alignment.center,
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
                                        ),
                                      if (doc.imageUrls.isNotEmpty)
                                        ElevatedButton.icon(
                                          icon: const Icon(Icons.image),
                                          label: const Text("View Image"),
                                          onPressed: () => _showImageDialog(
                                            context,
                                            doc,
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                          ),
                                        ),
                                      if (doc.filePath != null ||
                                          doc.fileUrls.isNotEmpty)
                                        ElevatedButton.icon(
                                          icon: const Icon(Icons.attach_file),
                                          label: Text(
                                            "View File${doc.filePath != null && doc.fileUrls.isNotEmpty ? 's' : ''}",
                                          ),
                                          onPressed: () {
                                            final allFiles = <String>[];
                                            if (doc.filePath != null) {
                                              allFiles.add(doc.filePath!);
                                            }
                                            allFiles.addAll(doc.fileUrls);
                                            if (allFiles.length == 1) {
                                              _viewFile(allFiles[0]);
                                            } else {
                                              _showFileDialog(context, doc);
                                            }
                                          },
                                          style: ElevatedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(8),
                                            ),
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
