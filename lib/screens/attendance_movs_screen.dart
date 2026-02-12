import 'package:com.cpdco.docutracker/screens/add_attendance_movs_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/document.dart';
import '../services/upload_queue_manager.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/connectivity_banner.dart';
import '../utils/delete_utils.dart';
import '../services/cached_document_service.dart';
import '../services/auth_service.dart';
import '../services/google_drive_service.dart';
import '../config/supabase_config.dart';
import 'edit_document_screen.dart';
import 'add_document_screen.dart';

class AttendanceMovsScreen extends StatefulWidget {
  final List<Document> documents;
  final Function(int, String, String, {String? notes}) transferDocument;
  final Function(int, String, String, {String? notes, DateTime? complianceDeadline, String? complianceAssignee}) updateDocumentStatus;
  final Function(int) deleteDocument;
  final Function(String) syncDocument;
  final VoidCallback? onRefresh;

  const AttendanceMovsScreen({
    super.key,
    required this.documents,
    required this.transferDocument,
    required this.updateDocumentStatus,
    required this.deleteDocument,
    required this.syncDocument,
    this.onRefresh,
  });

  @override
  State<AttendanceMovsScreen> createState() =>
      _AttendanceMovsScreenState();
}

class _AttendanceMovsScreenState
    extends State<AttendanceMovsScreen> {
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
    final hour = dateTime.hour > 12 ? dateTime.hour - 12 : (dateTime.hour == 0 ? 12 : dateTime.hour);
    final amPm = dateTime.hour >= 12 ? 'PM' : 'AM';
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final year = dateTime.year;
    return '$month/$day/$year $hour:$minute $amPm';
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
        .where((doc) => doc.mode == 'Office Function MOVs')
        .toList()
      ..sort((a, b) => _parseDate(b.fromOrTo).compareTo(_parseDate(a.fromOrTo)));
    _uploadQueueManager = UploadQueueManager();
    _uploadQueueManager.addListener(_onUploadChanged);
    _loadUsername();
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
        if (doc.mode != 'Office Function MOVs') return false;

        // Search filter
        bool matchesSearch =
            _searchQuery.isEmpty ||
            doc.code.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            doc.type.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            doc.remarks.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            doc.person.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            doc.fromOrTo.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            (doc.description?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) ||
            (doc.referenceLink?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);

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
              builder: (context) => const AddAttendanceMovScreen(),
            ),
          );
          if (widget.onRefresh != null) {
            widget.onRefresh!();
          }
        },
        backgroundColor: const Color(0xFFDC7DED),
        child: const Icon(Icons.add),
      ),
      appBar: AppBar(
        title: const Text("Office Function MOVs"),
        backgroundColor: const Color(0xFFDC7DED),
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
                    'No Office Function MOVs found',
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
                              backgroundColor: const Color(0xFF9C27B0),
                              child: const Icon(
                                Icons.event_note,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              "${document.category}",
                              style: const TextStyle(fontWeight: FontWeight.w400),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
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
                                    if (_titleExceedsMaxLines(document.type, context)) ...[
                                      _buildDetailRow(
                                        Icons.description,
                                        "Document Type",
                                        document.type,
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                    if (document.description != null && document.description!.isNotEmpty) ...[
                                      _buildDetailRow(
                                        Icons.description,
                                        "Description",
                                        document.description!,
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                    _buildDetailRow(
                                      Icons.calendar_today,
                                      "Receiving Date",
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
                                      Icons.access_time,
                                      "Timestamp",
                                      document.createdAt != null ? _formatDateTime(document.createdAt!) : 'Unknown',
                                    ),
                                    if (document.referenceLink != null && document.referenceLink!.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      GestureDetector(
                                        onTap: () async {
                                          final uri = Uri.parse(document.referenceLink!);
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
                                                document.referenceLink!,
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
                                        if (_username == document.person)
                                          ElevatedButton.icon(
                                            icon: const Icon(Icons.edit),
                                            label: const SizedBox.shrink(),
                                            onPressed: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) => EditDocumentScreen(document: document),
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
                                        if (_username == document.person)
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
    final PageController pageController = PageController();
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.5),
      barrierLabel: '',
      builder: (_) => Dialog(
        backgroundColor: Colors.white.withOpacity(0.8),
        insetPadding: const EdgeInsets.all(14),
        child: SizedBox.expand(
          child: Stack(
            children: [
              PageView.builder(
                controller: pageController,
                itemCount: imageUrls.length,
                itemBuilder: (context, index) {
                  String normalizedFileId = GoogleDriveService.normalizeFileId(imageUrls[index]);
                  String proxyUrl = GoogleDriveService.generateProxyUrl(normalizedFileId);
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
              if (imageUrls.length > 1) ...[
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
                    icon: const Icon(Icons.arrow_forward_ios, color: Colors.black, size: 30),
                    onPressed: () {
                      if (pageController.page! < imageUrls.length - 1) {
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
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.black, size: 30),
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

  Future<void> _loadUsername() async {
    final username = await AuthService.getUsername();
    if (username != null && username.isNotEmpty) {
      setState(() {
        _username = username;
      });
    }
  }
}
