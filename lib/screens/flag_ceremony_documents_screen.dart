import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/document.dart';
import '../services/upload_queue_manager.dart';
import '../utils/snackbar_utils.dart';

class FlagCeremonyDocumentsScreen extends StatefulWidget {
  final List<Document> documents;
  final Function(int, String, String, {String? notes}) transferDocument;
  final Function(int, String, String, {String? notes}) updateDocumentStatus;
  final Function(int) deleteDocument;
  final Function(String) syncDocument;

  const FlagCeremonyDocumentsScreen({
    super.key,
    required this.documents,
    required this.transferDocument,
    required this.updateDocumentStatus,
    required this.deleteDocument,
    required this.syncDocument,
  });

  @override
  State<FlagCeremonyDocumentsScreen> createState() =>
      _FlagCeremonyDocumentsScreenState();
}

class _FlagCeremonyDocumentsScreenState
    extends State<FlagCeremonyDocumentsScreen> {
  late List<Document> _filteredDocuments;
  String _searchQuery = '';
  DateTime? _startDate;
  DateTime? _endDate;
  DateTime? _specificDate;
  final Set<int> _expandedTiles = {};
  late final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  late final Connectivity _connectivity = Connectivity();
  bool _isOnline = true;

  DateTime _parseDate(String dateStr) {
    try {
      final parts = dateStr.split('/');
      if (parts.length == 3) {
        final month = int.parse(parts[0]);
        final day = int.parse(parts[1]);
        final year = int.parse(parts[2]);
        return DateTime(year, month, day);
      }
    } catch (e) {}
    return DateTime.now();
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      return "Today ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}";
    } else if (difference.inDays == 1) {
      return "Yesterday ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}";
    } else if (difference.inDays < 7) {
      return "${difference.inDays} days ago";
    } else {
      return "${dateTime.month}/${dateTime.day}/${dateTime.year}";
    }
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

  @override
  void initState() {
    super.initState();
    _searchController.text = _searchQuery;
    _searchController.addListener(() {
      _searchQuery = _searchController.text;
      _filterDocuments();
    });
    _filteredDocuments = widget.documents
        .where((doc) => doc.mode == 'Flag Ceremony')
        .toList()
      ..sort((a, b) => _parseDate(b.fromOrTo).compareTo(_parseDate(a.fromOrTo)));
    // Simulate loading for better UX
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
    _checkConnectivity();
    _connectivity.onConnectivityChanged.listen((result) {
      setState(() {
        _isOnline = result != ConnectivityResult.none;
      });
    });
  }

  Future<void> _checkConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    setState(() {
      _isOnline = result != ConnectivityResult.none;
    });
  }

  void _filterDocuments() {
    setState(() {
      _filteredDocuments = widget.documents.where((doc) {
        if (doc.mode != 'Flag Ceremony') return false;

        // Search filter
        bool matchesSearch =
            _searchQuery.isEmpty ||
            doc.code.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            doc.type.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            doc.remarks.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            doc.person.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            doc.fromOrTo.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            doc.status.toLowerCase().contains(_searchQuery.toLowerCase());

        // Date filter
        bool matchesDate = true;
        if (_startDate != null || _endDate != null) {
          final docDate = _parseDate(doc.fromOrTo);
          if (_startDate != null && docDate.isBefore(_startDate!)) {
            matchesDate = false;
          }
          if (_endDate != null && docDate.isAfter(_endDate!)) {
            matchesDate = false;
          }
        }

        return matchesSearch && matchesDate;
      }).toList()
        ..sort((a, b) => _parseDate(b.fromOrTo).compareTo(_parseDate(a.fromOrTo)));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Flag Ceremony Documents"),
        backgroundColor: const Color(0xFF4EC377),
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(80),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search documents...',
                      prefixIcon: const Icon(Icons.search),
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
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Loading documents...',
                      style: TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              )
            : _filteredDocuments.isEmpty
            ? const Center(
                child: Text(
                  'No Flag Ceremony documents found',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 16,
                ),
                itemCount: _filteredDocuments.length,
                itemBuilder: (context, index) {
                  final document = _filteredDocuments[index];
                  final originalIndex = widget.documents.indexOf(document);
                  final queueManager = UploadQueueManager();
                  final pendingUploads = queueManager.getPendingUploads(
                    document.code,
                  );
                  final uploadingUploads = queueManager
                      .getAllItems()
                      .where(
                        (item) =>
                            item['documentCode'] == document.code &&
                            item['status'] == 'uploading',
                      )
                      .toList();

                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    elevation: 2,
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
                        backgroundColor: !_isOnline
                            ? Colors.red
                            : const Color(0xFF4EC377),
                        child: Icon(
                          !_isOnline ? Icons.sync : Icons.flag,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        "${document.type}",
                        style: const TextStyle(fontWeight: FontWeight.w400),
                      ),
                      subtitle: Row(
                        children: [
                          Text("${document.code}  "),
                          if (_expandedTiles.contains(index))
                            IconButton(
                              icon: const Icon(Icons.copy, size: 16),
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(text: document.code),
                                );
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
                              _buildDetailRow(
                                Icons.calendar_today,
                                "Date",
                                document.fromOrTo,
                              ),
                              const SizedBox(height: 8),
                              _buildDetailRow(
                                Icons.person,
                                "Recorded by",
                                document.person,
                              ),
                              const SizedBox(height: 8),
                              _buildDetailRow(
                                Icons.info,
                                "Status",
                                document.status,
                              ),
                              if (document.remarks.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                _buildDetailRow(
                                  Icons.comment,
                                  "Remarks",
                                  document.remarks,
                                ),
                              ],
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
                                    onPressed: () =>
                                        _confirmDelete(originalIndex),
                                  ),
                                  if (document.imageUrls.isNotEmpty ||
                                      document.localImagePaths.isNotEmpty)
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.image),
                                      label: const Text("View Image"),
                                      onPressed: () => _showImageDialog(
                                        context,
                                        document.imageUrls.isNotEmpty
                                            ? document.imageUrls
                                            : document.localImagePaths,
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (document.filePath != null ||
                                      document.fileUrls.isNotEmpty)
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.attach_file),
                                      label: Text(
                                        "View File${document.filePath != null && document.fileUrls.isNotEmpty ? 's' : ''}",
                                      ),
                                      onPressed: () {
                                        final allFiles = <String>[];
                                        if (document.filePath != null) {
                                          allFiles.add(document.filePath!);
                                        }
                                        allFiles.addAll(document.fileUrls);
                                        if (allFiles.length == 1) {
                                          _viewFile(allFiles[0]);
                                        } else {
                                          _showFileDialog(context, document);
                                        }
                                      },
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
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
    );
  }

  void _confirmDelete(int originalIndex) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Document'),
        content: const Text('Sure??? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.deleteDocument(originalIndex);
              setState(() {
                _filteredDocuments.removeWhere(
                  (doc) => widget.documents.indexOf(doc) == originalIndex,
                );
              });
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
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
        insetPadding: const EdgeInsets.all(14),
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
                                  'wait la po...',
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
                title: Text(document.code),
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
                _filterDocuments();
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
                _filterDocuments();
                Navigator.pop(context);
              },
            ),
          ],
        ),
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
}
