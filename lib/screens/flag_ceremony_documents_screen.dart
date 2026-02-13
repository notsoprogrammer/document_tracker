import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import '../models/document.dart';
import '../services/upload_queue_manager.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/connectivity_banner.dart';
import '../utils/delete_utils.dart';
import '../services/cached_document_service.dart';
import '../services/google_drive_service.dart';
import '../config/supabase_config.dart';
import './add_flag_ceremony_screen.dart';

class FlagCeremonyDocumentsScreen extends StatefulWidget {
  final List<Document> documents;
  final Function(int, String, String, {String? notes}) transferDocument;
  final Function(int, String, String, {String? notes, DateTime? complianceDeadline, String? complianceAssignee}) updateDocumentStatus;
  final Function(int) deleteDocument;
  final Function(String) syncDocument;
  final VoidCallback? onRefresh;

  const FlagCeremonyDocumentsScreen({
    super.key,
    required this.documents,
    required this.transferDocument,
    required this.updateDocumentStatus,
    required this.deleteDocument,
    required this.syncDocument,
    this.onRefresh,
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
  late UploadQueueManager _uploadQueueManager;

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

  Widget _buildUploadStatusIndicator(Document doc) {
    final queueManager = UploadQueueManager();
    final pendingUploads = queueManager.getPendingUploads(doc.code);
    final allUploads = queueManager.getAllItems().where((item) => item['documentCode'] == doc.code).toList();
    final uploadingUploads = allUploads.where((item) => item['status'] == 'uploading').toList();

    final totalFiles = doc.localImagePaths.length + doc.localFilePaths.length;
    final uploadedFiles = doc.imageUrls.length + doc.fileUrls.length;
    final hasUploads = pendingUploads.isNotEmpty || uploadingUploads.isNotEmpty;

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
              'Uploading ${uploadedFiles}/${totalFiles} files...',
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
    _uploadQueueManager = UploadQueueManager();
    _uploadQueueManager.addListener(_onUploadChanged);
    // Simulate loading for better UX
    Future.delayed(const Duration(milliseconds: 500), () {
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
    return ConnectivityBanner(
      child: Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AddFlagCeremonyScreen(),
            ),
          );
          if (widget.onRefresh != null) {
            widget.onRefresh!();
          }
        },
        backgroundColor: const Color(0xFF4EC377),
        child: const Icon(Icons.add),
      ),
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
      body: RefreshIndicator(
        onRefresh: () async {
          if (widget.onRefresh != null) {
            widget.onRefresh!();
          }
        },
        child: Container(
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
              : Column(
                children: [
                  _buildGlobalUploadStatusIndicator(),
                  Expanded(
                    child: ListView.builder(
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
                          color: document.needsSync ? Colors.grey[100] : null,
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
                              backgroundColor: const Color(0xFF4EC377),
                              child: const Icon(
                                Icons.flag,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              "${document.type}",
                              style: const TextStyle(fontWeight: FontWeight.w400),
                            ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
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
                            const SizedBox(height: 4),
                            _buildUploadStatusIndicator(document),
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
                                          onPressed: () async {
                                            final deleted = await confirmAndDeleteRecord(
                                              context,
                                              document,
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
                ],
              ),

          ),
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
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.all(14),
        child: SizedBox.expand(
          child: Stack(
            children: [
              PageView.builder(
                itemCount: imageUrls.length,
                itemBuilder: (context, index) {
                  // Handle both fileId and Google Drive URL formats
                  String imageUrl = imageUrls[index];
                  String proxyUrl;
                  if (imageUrl.contains('drive.google.com/uc?id=')) {
                    // Legacy: extract fileId from Google Drive URL
                    final uri = Uri.parse(imageUrl);
                    final fileId = uri.queryParameters['id'];
                    proxyUrl = fileId != null ? GoogleDriveService.generateProxyUrl(fileId) : imageUrl;
                  } else {
                    // New: assume it's already a fileId
                    proxyUrl = GoogleDriveService.generateProxyUrl(imageUrl);
                  }
                  return InteractiveViewer(
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
                                'wait la po...',
                                style: TextStyle(
                                  color: Colors.black,
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
                  );
                },
              ),
              Positioned(
                top: 40,
                right: 20,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.download, color: Colors.black, size: 30),
                      onPressed: () => _downloadImage(context, imageUrls.isNotEmpty ? imageUrls[0] : ''),
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
        // Mobile: Request permission and download directly
        final status = await Permission.storage.request();
        if (status.isGranted) {
          final directory = await getExternalStorageDirectory();
          if (directory != null) {
            final fileName = 'document_${DateTime.now().millisecondsSinceEpoch}.jpg';
            final savePath = '${directory.path}/$fileName';

            await Dio().download(downloadUrl, savePath);
            if (context.mounted) {
              SnackbarUtils.showSuccessSnackBar(context, 'Image downloaded to: $savePath');
            }
          }
        } else if (status.isPermanentlyDenied) {
          // Open app settings if permission permanently denied
          await openAppSettings();
        } else {
          // Fallback to browser download
          final uri = Uri.parse(downloadUrl);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }
      }
    } catch (e) {
      SnackbarUtils.showErrorSnackBar(context, 'Failed to download image');
    }
  }
}
