import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/document.dart';
import '../utils/search_filter_utils.dart';
import '../utils/snackbar_utils.dart';
import '../services/upload_queue_manager.dart';
import '../widgets/connectivity_banner.dart';
import '../utils/delete_utils.dart';
import '../services/cached_document_service.dart';

class IncomingDocumentsScreen extends StatefulWidget {
  final List<Document> documents;
  final Function(int, String, String, {String? notes}) transferDocument;
  final Function(int, String, String, {String? notes}) updateDocumentStatus;
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
    _filteredDocuments = widget.documents.where((doc) => doc.incoming).toList();
    _uploadQueueManager = UploadQueueManager();
    _uploadQueueManager.addListener(_onUploadChanged);
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
        widget.documents.where((doc) => doc.incoming).toList(),
        searchQuery: _searchQuery,
        startDate: _startDate,
        endDate: _endDate,
      );
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
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
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
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                  ],
                ),
              ),
              actions: [
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
            );
          },
        );
      },
    );
  }

  void _showStatusUpdateDialog(BuildContext context, int index) {
    String? selectedStatus;
    final cabinetController = TextEditingController();
    final updatedByController = TextEditingController();
    final notesController = TextEditingController();

    final List<String> statusOptions = [
      'Received',
      'In Progress',
      'Under Review',
      'Approved',
      'Action Required',
      'Returned',
      'Completed',
      'Filed',
      'Urgent',
    ];

    final List<String> cpdcoStaff = [
      'Arnie',
      'Rex',
      'Floro',
      'Arlene',
      'Sharmaine',
      'Path',
      'Jess',
      'Emie',
      'Pau',
      'Chris',
      'Wena',
    ];

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
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
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                    setState(() => selectedStatus = value);
                  },
                ),
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
                RawAutocomplete<String>(
                  textEditingController: updatedByController,
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
                    setState(() => updatedByController.text = selection);
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
                            labelText: "Updated By",
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
                                itemBuilder: (BuildContext context, int index) {
                                  final String option = options.elementAt(
                                    index,
                                  );
                                  return GestureDetector(
                                    onTap: () {
                                      onSelected(option);
                                    },
                                    child: ListTile(title: Text(option)),
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
              ],
            ),
          ),
          actions: [
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
                    updatedByController.text.isNotEmpty) {
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
                    updatedByController.text,
                    notes: combinedNotes,
                  );
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showImageDialog(BuildContext context, List<String> imageUrls) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (_) => Dialog(
        backgroundColor: Colors.black.withOpacity(0.8),
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox.expand(
          child: Stack(
            children: [
              PageView.builder(
                itemCount: imageUrls.length,
                itemBuilder: (context, index) {
                  return InteractiveViewer(
                    child: Center(
                      child: Image.network(
                        imageUrls[index],
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 16),
                                Text(
                                  'Please wait...',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Text('Failed to load image'),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
              Positioned(
                top: 40,
                right: 20,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFileDialog(BuildContext context, Document document) {
    final allFiles = <String>[];
    if (document.filePath != null) {
      allFiles.add(document.filePath!);
    }
    allFiles.addAll(document.fileUrls);

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
              final fileName = filePath.split('/').last.split('\\').last;
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

  void _viewFile(String filePath) async {
    final uri = Uri.parse(filePath);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      // Handle error
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
                        _startDate = picked;
                        _endDate = picked;
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
                        _specificDate =
                            null; // Clear specific date if range is used
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
                        _specificDate =
                            null; // Clear specific date if range is used
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
                });
                Navigator.pop(context);
              },
              child: const Text("Clear All"),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.filter_list),
              label: const Text("Apply"),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () {
                Navigator.pop(context);
              },
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
                                  Text("${doc.code}  "),
                                  if (_expandedTiles.contains(index))
                                    IconButton(
                                      icon: const Icon(Icons.copy, size: 16),
                                      onPressed: () {
                                        Clipboard.setData(ClipboardData(text: doc.code));
                                        SnackbarUtils.showInfoSnackBar(
                                          context,
                                          'Code copied to clipboard',
                                        );
                                      },
                                      tooltip: 'Copy Code',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              _buildUploadStatusIndicator(doc),
                            ],
                          ),
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
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
                                  if (doc.imageUrls.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                  ],

                                  const SizedBox(height: 8),
                                  _buildDetailRow(
                                    Icons.comment,
                                    "Remarks",
                                    doc.remarks,
                                  ),
                                  const SizedBox(height: 8),
                                  _buildDetailRow(
                                    Icons.receipt,
                                    "Received by",
                                    doc.person,
                                  ),
                                  const SizedBox(height: 16),
                                  ExpansionTile(
                                    leading: const Icon(Icons.history),
                                    title: Text(
                                      "Document History (" +
                                          (doc.history.isEmpty
                                              ? '0'
                                              : doc.history
                                                    .asMap()
                                                    .entries
                                                    .where(
                                                      (me) =>
                                                          me.key == 0 ||
                                                          me.value.action.startsWith(
                                                            'Status changed to ',
                                                          ) ||
                                                          me.value.action.startsWith(
                                                            'Transferred to ',
                                                          ),
                                                    )
                                                    .length
                                                    .toString()) +
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

                                      final visible = entries
                                          .asMap()
                                          .entries
                                          .where(
                                            (me) =>
                                                me.key == 0 ||
                                                me.value.action.startsWith(
                                                  'Status changed to ',
                                                ) ||
                                                me.value.action.startsWith(
                                                  'Transferred to ',
                                                ),
                                          )
                                          .toList();

                                      return visible.map((mapEntry) {
                                        final originalIndex = mapEntry.key;
                                        final entry = mapEntry.value;
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
                                                      entry.action,
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
                                                    if (entry.notes != null &&
                                                        entry.notes!.isNotEmpty) ...[
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
                                      ElevatedButton.icon(
                                        icon: const Icon(Icons.delete),
                                        label: const Text("Delete"),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color.fromARGB(
                                            255,
                                            218,
                                            87,
                                            78,
                                          ),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
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
                                            doc.imageUrls,
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
