import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/image_download_service.dart';
import '../models/document.dart';
import '../services/connectivity_service.dart';
import '../utils/search_filter_utils.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/connectivity_banner.dart';
import '../services/upload_queue_manager.dart';
import '../utils/delete_utils.dart';
import '../services/cached_document_service.dart';
import '../services/auth_service.dart';
import '../utils/date_time_utils.dart';
import '../widgets/move_document_dialog.dart';
import '../services/google_drive_service.dart';
import '../config/supabase_config.dart';
import 'edit_document_screen.dart';
import 'add_document_screen.dart';

class OutgoingDocumentsScreen extends StatefulWidget {
  final List<Document> documents;
  final Function(int, String, String, {String? notes}) transferDocument;
  final Function(int, String, String, {String? notes, DateTime? complianceDeadline, String? complianceAssignee}) updateDocumentStatus;
  // final Function(int, Document) editDocument;
  final Function(int) deleteDocument;
  final Function(String) syncDocument;
  final VoidCallback? onRefresh;
  final Future<void> Function() syncAllDocuments;

  const OutgoingDocumentsScreen({
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
  State<OutgoingDocumentsScreen> createState() =>
      _OutgoingDocumentsScreenState();
}

class _OutgoingDocumentsScreenState extends State<OutgoingDocumentsScreen> {
  late List<Document> _filteredDocuments;
  bool _isLoading = true;
  late UploadQueueManager _uploadQueueManager;
  final List<String> cpdcoStaff = [
    'Sir Arnie',
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
    'N/A',
    'Arlyn',
    'Dari',
  ];

  final List<String> offices = [
    'CMO - City Mayor\'s Office',
    'CVMO - City Vice Mayor\'s Office',
    'SP - Sangguniang Panlungsod Office',
    'CTO - City Treasurer\'s Office',
    'CAssO - City Assessor\'s Office',
    'CAccO - City Accounting Office',
    'CBO - City Budget Office',
    'CPDCO - City Planning and Development Coordinator\'s Office',
    'CHRMO - City Human Resource Management Office',
    'CCRO - City Civil Registrar\'s Office',
    'CAdmO - City Administrator\'s Office',
    'CLO - City Legal Office',
    'CICTO - City Information and Communications Technology Office',
    'CGSO - City General Services Office',
    'CDRRMO - City Disaster Risk Reduction and Management Office',
    'CIASO - City Internal Audit Services Office',
    'CPYDO - City Population and Youth Development Office',
    'CBPLO - City Business Processing and Licensing Office',
    'BCAO - Barangay And Community Affair\'s Office',
    'CPO - City Procurement Office',
    'CLEAO - Catbalogan Law Enforcement Auxiliary Office',
    'CCCC - Catbalogan City Community College',
    'CHO - City Health Office',
    'CSWDO - City Social Welfare and Development Office',
    'CPDAO - City Persons with Disability Affairs Office',
    'CPESO - City Public Employment Services Office',
    'CTCAO - City Tourism, Culture, Arts, and Information Office',
    'CAgrO - City Agriculture Office',
    'CENRO - City Environment & Natural Resources Office',
    'CEO - City Engineering Office',
    'CVetO - City Veterinary Office',
    'CCDO - City Cooperatives Development Office',
    'CAgBEO - City Agricultural and Biosystem Engineering Office',
    'CEDIPO - City Economic Development and Investment Promotions Office',
    'CEEPUO - City Economic Enterprise and Public Utility Office',
  ];

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
        .where((doc) => (doc.flowStage == 'outgoing' || doc.flowStage == 'circulated') && doc.mode != 'Flag Ceremony' && doc.mode != 'Office Function MOVs')
        .toList();
    _filteredDocuments.sort((a, b) {
      final aDate = a.history.isNotEmpty ? a.history.last.timestamp : (a.createdAt ?? DateTime(1900));
      final bDate = b.history.isNotEmpty ? b.history.last.timestamp : (b.createdAt ?? DateTime(1900));
      return bDate.compareTo(aDate);
    });
    _uploadQueueManager = UploadQueueManager();
    _uploadQueueManager.addListener(_onUploadChanged);
    // Simulate loading for better UX - keep it longer to show the indicator
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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

  @override
  void dispose() {
    _uploadQueueManager.removeListener(_onUploadChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(OutgoingDocumentsScreen oldWidget) {
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
        widget.documents.where((doc) => (doc.flowStage == 'outgoing' || doc.flowStage == 'circulated') && doc.mode != 'Flag Ceremony' && doc.mode != 'Office Function MOVs').toList(),
        searchQuery: _searchQuery,
        startDate: _startDate,
        endDate: _endDate,
        specificDate: _specificDate,
      );
    });
  }

  Future<void> _refreshDocuments() async {
    final allDocs = await CachedDocumentService().fetchDocuments();
    if (!mounted) return;
    setState(() {
      _expandedTiles.clear();
      _filteredDocuments = searchAndFilterDocuments(
        allDocs.where((doc) => (doc.flowStage == 'outgoing' || doc.flowStage == 'circulated') && doc.mode != 'Flag Ceremony' && doc.mode != 'Office Function MOVs').toList(),
        searchQuery: _searchQuery,
        startDate: _startDate,
        endDate: _endDate,
        specificDate: _specificDate,
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
  void _showImageDialog(BuildContext context, Document document) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (dialogContext) {
        int currentIndex = 0;
        bool isDownloading = false;
        bool isSuccess = false;
        final PageController pageController = PageController();

        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: Colors.white,
              insetPadding: const EdgeInsets.all(14),
              child: SizedBox.expand(
                child: Stack(
                  children: [
                    /// IMAGE VIEWER
                    PageView.builder(
                      controller: pageController,
                      itemCount: document.imageUrls.length,
                      onPageChanged: (index) {
                        setState(() => currentIndex = index);
                      },
                      itemBuilder: (context, index) {
                        String fileName = index < document.fileNames.length ? document.fileNames[index] : 'Image ${index + 1}';
                        String imageUrl = document.imageUrls[index];
                        String proxyUrl;

                        if (imageUrl.contains('drive.google.com/uc?id=')) {
                          final uri = Uri.parse(imageUrl);
                          final fileId = uri.queryParameters['id'];
                          proxyUrl = fileId != null
                              ? GoogleDriveService.generateProxyUrl(fileId)
                              : imageUrl;
                        } else {
                          proxyUrl = GoogleDriveService.generateProxyUrl(imageUrl);
                        }

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

                    /// NAVIGATION ARROWS
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
                          icon: const Icon(Icons.arrow_forward_ios, color: Colors.black, size: 30),
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

                    /// TOP RIGHT BUTTONS
                    Positioned(
                      top: 40,
                      right: 20,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.download,
                              color: Colors.black,
                              size: 30,
                            ),
                            onPressed: isDownloading
                                ? null
                                : () async {
                                    setState(() {
                                      isDownloading = true;
                                      isSuccess = false;
                                    });

                                    try {
                                      await ImageDownloadService.downloadAndSave(
                                          document.imageUrls[currentIndex]);

                                      if (context.mounted) {
                                        setState(() {
                                          isDownloading = false;
                                          isSuccess = true;
                                        });

                                        // Auto hide success after 1.5 seconds
                                        await Future.delayed(
                                            const Duration(milliseconds: 1500));

                                        if (context.mounted) {
                                          setState(() {
                                            isSuccess = false;
                                          });
                                        }
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        setState(() {
                                          isDownloading = false;
                                        });

                                        SnackbarUtils.showErrorSnackBar(
                                          context,
                                          e.toString().replaceAll('Exception: ', ''),
                                        );
                                      }
                                    }
                                  },
                            tooltip: 'Download Image',
                          ),
                          IconButton(
                            icon: const Icon(Icons.close,
                                color: Colors.black, size: 30),
                            onPressed: () =>
                                Navigator.pop(dialogContext),
                          ),
                        ],
                      ),
                    ),

                    /// LOADING / SUCCESS OVERLAY
                    if (isDownloading || isSuccess)
                      Container(
                        color: Colors.black.withOpacity(0.4),
                        child: Center(
                          child: AnimatedSwitcher(
                            duration:
                                const Duration(milliseconds: 300),
                            child: isDownloading
                                ? const CircularProgressIndicator(
                                    key: ValueKey('loading'),
                                    color: Colors.white,
                                  )
                                : Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Icon(Icons.check, color: Colors.green, size: 48),
                                      SizedBox(height: 8),
                                      Text(
                                        'Saved!',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
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

  String _detectMimeType(List<int> bytes) {
    if (bytes.length >= 4 &&
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

  void _showStatusUpdateDialog(BuildContext context, int index) async {
    String? selectedStatus;
    final updatedByController = TextEditingController();
    final officeController = TextEditingController(
      text: widget.documents[index].fromOrTo,
    );
    final forwardedToController = TextEditingController();
    final notesController = TextEditingController();

    final connectivityService = ConnectivityService();
    final isOnline = await connectivityService.isOnline;

    final List<String> allStatusOptions = [
      'Urgent',
      'Received',
      'In Progress',
      'For follow-up',
      'Delivered',
      'Under Review',
      'Approved',
      'Returned',
      'Rejected',
      'Completed',
    ];

    final List<String> statusOptions = isOnline
        ? allStatusOptions
        : allStatusOptions.where((status) => status != 'Urgent').toList();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setState) {
            updatedByController.text = _username ?? '';
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
                            Icons.edit,
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
                          prefixIcon: const Icon(Icons.info),
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
                      const SizedBox(height: 16),
                      RawAutocomplete<String>(
                        textEditingController: officeController,
                        focusNode: FocusNode(),
                        optionsBuilder:
                            (TextEditingValue textEditingValue) {
                              if (textEditingValue.text.isEmpty) {
                                return offices;
                              }
                              return offices.where((String option) {
                                return option.toLowerCase().contains(
                                  textEditingValue.text.toLowerCase(),
                                );
                              });
                            },
                        onSelected: (String selection) {
                          setState(() {
                            officeController.text = selection;
                          });
                        },
                        fieldViewBuilder:
                            (
                              BuildContext context,
                              TextEditingController textEditingController,
                              FocusNode focusNode,
                              VoidCallback onFieldSubmitted,
                            ) {
                              return SizedBox(
                                width: 350,
                                child: TextField(
                                  controller: textEditingController,
                                  focusNode: focusNode,
                                  autofocus: false,
                                  decoration: InputDecoration(
                                    labelText: "Office",
                                    prefixIcon: const Icon(Icons.business),
                                    suffixIcon:
                                        textEditingController
                                            .text
                                            .isNotEmpty
                                        ? IconButton(
                                            icon: const Icon(Icons.clear),
                                            onPressed: () {
                                              setState(() {
                                                textEditingController
                                                    .clear();
                                              });
                                            },
                                          )
                                        : null,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                        12,
                                      ),
                                    ),
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
                                    height: (options.length * 56.0 + 16.0)
                                        .clamp(0.0, 200.0),
                                    child: ListView.builder(
                                      padding: const EdgeInsets.all(8.0),
                                      itemCount: options.length,
                                      itemBuilder:
                                          (
                                            BuildContext context,
                                            int index,
                                          ) {
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
                        controller: forwardedToController,
                        decoration: InputDecoration(
                          labelText: "Personnel",
                          prefixIcon: const Icon(Icons.assignment_ind),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
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
                            icon: const Icon(Icons.update),
                            label: const Text(
                              "Update",
                              style: TextStyle(fontSize: 10),
                            ),
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () {
                              if (selectedStatus != null &&
                                  updatedByController.text.isNotEmpty &&
                                  forwardedToController.text.isNotEmpty) {
                                String combinedNotes =
                                    "${officeController.text} - ${forwardedToController.text}";
                                if (notesController.text.isNotEmpty) {
                                  combinedNotes += " | ${notesController.text}";
                                }
                                // Record the status change
                                widget.updateDocumentStatus(
                                  index,
                                  selectedStatus!,
                                  updatedByController.text,
                                  notes: combinedNotes,
                                );
                                Navigator.of(
                                  context,
                                ).popUntil((route) => route.isFirst);
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



  void _showFilterDialog(BuildContext context) {
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
                      setState(() {});
                      this.setState(() {
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
                      setState(() {});
                      this.setState(() {
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
                      setState(() {});
                      this.setState(() {
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
                setState(() {});
                this.setState(() {
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


  @override
  Widget build(BuildContext context) {
    return ConnectivityBanner(
      child: Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AddDocumentScreen(incoming: false),
            ),
          );
          await _refreshDocuments();
          if (widget.onRefresh != null) {
            widget.onRefresh!();
          }
        },
        backgroundColor: const Color(0xFF2196F3),
        child: const Icon(Icons.add),
      ),
        appBar: AppBar(
        title: const Text("Outgoing Documents"),
        backgroundColor: const Color(0xFF2196F3), // Blue complementing orange
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
                  onPressed: () => _showFilterDialog(context),
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
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.document_scanner,
                      size: 80,
                      color: const Color(0xFF2196F3).withOpacity(0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _filteredDocuments.isEmpty && _searchQuery.isEmpty && _startDate == null && _endDate == null
                          ? "No outgoing documents yet"
                          : "No documents match your search/filter",
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _filteredDocuments.isEmpty && _searchQuery.isEmpty && _startDate == null && _endDate == null
                          ? "Outgoing documents will appear here"
                          : "Try adjusting your search or filter criteria",
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
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
                  color: doc.needsSync ? Colors.grey[100] : null,
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
                            backgroundColor: const Color(0xFF2196F3),
                            child: const Icon(
                              Icons.arrow_upward,
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
                                    Icons.output,
                                    size: 16,
                                    color: const Color(0xFF2196F3),
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
                              if (doc.flowStage != 'incoming' && doc.incoming) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFB74D).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFFFB74D).withOpacity(0.4)),
                                  ),
                                  child: const Text(
                                    'Fr. Incoming',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFFFFB74D),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
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
                                  if (_titleExceedsMaxLines("${doc.type} - ${doc.title}", context)) ...[
                                    _buildDetailRow(Icons.title, "Document Title", "${doc.type} - ${doc.title}"),
                                    const SizedBox(height: 8),
                                  ],

                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      ElevatedButton.icon(
                                        icon: const Icon(Icons.arrow_downward),
                                        label: const Text("Move to Incoming"),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFFFFB74D),
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
                                                  moveAction: 'Move to Incoming',
                                                  syncDocument: widget.syncDocument,
                                                  onDocumentMoved: () async {
                                                    if (_username != null && _username!.isNotEmpty) {
                                                      // Move the document to incoming
                                                      widget.documents[originalIndex].flowStage = 'incoming';
                                                       _updateFilteredDocuments();
                                                      final documentService = CachedDocumentService();
                                                      await documentService.updateDocument(widget.documents[originalIndex].code, {'flow_stage': widget.documents[originalIndex].flowStage});
                                                      // Add history entry before sync
                                                      final historyEntry = HistoryEntry(
                                                        action: 'Moved to Incoming',
                                                        person: _username!,
                                                        timestamp: getPhilippineTime(),
                                                      );
                                                      await documentService.addHistoryEntry(widget.documents[originalIndex].code, historyEntry);
                                                      // Update local document history for immediate UI update
                                                      widget.documents[originalIndex].history.add(historyEntry);
                                                      await CachedDocumentService().updateDocument(widget.documents[originalIndex].code, {'needs_sync': true});
                                                      // Automatically sync all documents (after history is added)
                                                      await widget.syncAllDocuments();
                                                      // Force UI refresh to show updated history
                                                      setState(() {});
                                                      Navigator.of(dialogContext).pop();
                                                    }
                                                  },
                                                ),
                                              );
                                            },
                                          ),                                      Column(
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
                                  const SizedBox(height: 8),
                                  _buildDetailRow(Icons.person, "To", doc.fromOrTo),
                                  const SizedBox(height: 8),
                                  _buildDetailRow(Icons.send, "Mode", doc.mode),
                                  const SizedBox(height: 8),
                                  _buildDetailRow(
                                    Icons.assignment_ind,
                                    "Forwarded To",
                                    doc.assignedTo,
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
                                    const SizedBox(height: 4),
                                  _buildDetailRow(
                                    Icons.send,
                                    "Released by",
                                    doc.person,
                                  ),
                                  const SizedBox(height: 8),
                                  ExpansionTile(
                                    leading: const Icon(Icons.history),
                                    // compute visible entries (creation + status changes)
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

                                      // Only include the creation entry (index 0), status-change entries, and transfer entries.
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
                                          if (doc.incoming) {
                                            // For documents originally added in Incoming
                                            mainLine = "Document Received";
                                          } else {
                                            // For documents originally added in Outgoing
                                            mainLine = "Created and forwarded to $office c/o $personnel";
                                          }
                                        } else {
                                          if (entry.action == 'Moved to Outgoing' || entry.action == 'Moved to Incoming') {
                                            mainLine = entry.action;
                                          }
                                          else if (entry.action.startsWith('Status changed to ')) {
                                            final status = entry.action.replaceFirst(
                                              'Status changed to ',
                                              '',
                                            );
                                            mainLine = "$status: $office - $personnel";
                                          } else {
                                            mainLine = entry.action; // fallback
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
                                                color: const Color(0xFF2196F3),
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
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      originalIndex == 0
                                                          ? "by: ${entry.person}"
                                                          : "by: ${entry.person} | ${_formatDateTime(entry.timestamp)}",
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onSurface
                                                            .withOpacity(0.8),
                                                      ),
                                                    ),
                                                    if (additionalNotes != null &&
                                                        additionalNotes
                                                            .isNotEmpty) ...[
                                                      const SizedBox(height: 6),
                                                      Text(
                                                        "Notes: $additionalNotes",
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
                                             alignment: Alignment.center,
                                            backgroundColor: const Color.fromARGB(255, 78, 127, 218),
                                            minimumSize: const Size(48, 40), // shrink width, fixed height
                                            padding: EdgeInsets.only(left:10),
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
                                        ElevatedButton(
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
                                          child: const Icon(Icons.image),
                                        ),
                                      if (doc.filePath != null ||
                                          doc.fileUrls.isNotEmpty)
                                        ElevatedButton(
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
                                          child: const Icon(Icons.attach_file),
                                        ),
                                      if (doc.imageUrls.isNotEmpty || doc.fileUrls.isNotEmpty)
                                        ElevatedButton.icon(
                                          icon: const Icon(Icons.share),
                                          label: const Text("Share"),
                                          onPressed: () => _shareDocument(doc),
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
