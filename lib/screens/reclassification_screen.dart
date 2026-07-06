import 'dart:io';
import 'package:com.cpdco.docutracker/screens/add_reclassification_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../widgets/scrollable_image_viewer.dart';
import '../models/document.dart';
import '../services/upload_queue_manager.dart';
import '../widgets/upload_status_banner.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/connectivity_banner.dart';
import '../utils/delete_utils.dart';
import '../services/cached_document_service.dart';
import '../services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/google_drive_service.dart';
import 'edit_document_screen.dart';
import 'pdf_viewer_screen.dart';
import '../services/attachment_view_service.dart';
import '../widgets/document_search_bar.dart';
import '../widgets/document_filter_dialog.dart';

class ReclassificationScreen extends StatefulWidget {
  final List<Document> documents;
  final Function(int, String, String, {String? notes}) transferDocument;
  final Function(int, String, String, {String? notes, DateTime? complianceDeadline, String? complianceAssignee}) updateDocumentStatus;
  final Function(int) deleteDocument;
  final Function(String) syncDocument;
  final VoidCallback? onRefresh;
  final String? initialDocumentCode;

  const ReclassificationScreen({
    super.key,
    required this.documents,
    required this.transferDocument,
    required this.updateDocumentStatus,
    required this.deleteDocument,
    required this.syncDocument,
    this.onRefresh,
    this.initialDocumentCode,
  });

  @override
  State<ReclassificationScreen> createState() => _ReclassificationScreenState();
}

class _ReclassificationScreenState extends State<ReclassificationScreen> {
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

  DateTime _parseDate(String dateStr) {
    try {
      final parts = dateStr.split('/');
      if (parts.length == 3) return DateTime(int.parse(parts[2]), int.parse(parts[0]), int.parse(parts[1]));
    } catch (e) {}
    return DateTime.now();
  }

  String _formatDateTime(DateTime dateTime) {
    final hour = dateTime.hour > 12 ? dateTime.hour - 12 : (dateTime.hour == 0 ? 12 : dateTime.hour);
    final amPm = dateTime.hour >= 12 ? 'PM' : 'AM';
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '${dateTime.month.toString().padLeft(2, '0')}/${dateTime.day.toString().padLeft(2, '0')}/${dateTime.year} $hour:$minute $amPm';
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

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 8), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: TextStyle(fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.primary, fontSize: 12)), Text(value, style: const TextStyle(fontSize: 14))]))]);
  }

  Widget _buildUploadStatusIndicator(Document doc) {
    final queueManager = UploadQueueManager();
    final pendingUploads = queueManager.getPendingUploads(doc.code);
    final allUploads = queueManager.getAllItems().where((item) => item['documentCode'] == doc.code).toList();
    final uploadingUploads = allUploads.where((item) => item['status'] == 'uploading').toList();
    final totalFiles = doc.localImagePaths.length + doc.localFilePaths.length;
    final uploadedFiles = doc.imageUrls.length + doc.fileUrls.length;
    final hasUploads = pendingUploads.isNotEmpty || uploadingUploads.isNotEmpty;
    if (!hasUploads && totalFiles == 0) return const SizedBox.shrink();
    if (hasUploads) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.withOpacity(0.3))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.orange))), const SizedBox(width: 8), Text('Uploading $uploadedFiles/$totalFiles files...', style: TextStyle(fontSize: 12, color: Colors.orange[700], fontWeight: FontWeight.w500))]),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  void initState() {
    super.initState();
    _searchController.text = _searchQuery;
    _filteredDocuments = widget.documents.where((doc) => doc.mode == 'Reclassification').toList()..sort((a, b) {
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
    _subscribeToDocumentChanges();
    Future.delayed(const Duration(milliseconds: 500), () { if (mounted) setState(() => _isLoading = false); });
  }

  void _onUploadChanged() { setState(() {}); }

  @override
  void dispose() {
    _docsChannel?.unsubscribe();
    _uploadQueueManager.removeListener(_onUploadChanged);
    super.dispose();
  }

  void _subscribeToDocumentChanges() {
    _docsChannel = Supabase.instance.client
        .channel('documents:reclassification')
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

  void _filterDocuments() {
    setState(() {
      _filteredDocuments = widget.documents.where((doc) {
        if (doc.mode != 'Reclassification') return false;
        bool matchesSearch = _searchQuery.isEmpty || doc.code.toLowerCase().contains(_searchQuery.toLowerCase()) || doc.type.toLowerCase().contains(_searchQuery.toLowerCase()) || doc.remarks.toLowerCase().contains(_searchQuery.toLowerCase()) || doc.person.toLowerCase().contains(_searchQuery.toLowerCase()) || doc.fromOrTo.toLowerCase().contains(_searchQuery.toLowerCase()) || (doc.description?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) || (doc.referenceLink?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
        bool matchesDate = true;
        if (_startDate != null || _endDate != null) {
          final docDate = _parseDate(doc.fromOrTo);
          if (_startDate != null && docDate.isBefore(_startDate!)) matchesDate = false;
          if (_endDate != null && docDate.isAfter(_endDate!)) matchesDate = false;
        }
        return matchesSearch && matchesDate;
      }).toList()..sort((a, b) {
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
      _filteredDocuments = allDocs.where((doc) {
        if (doc.mode != 'Reclassification') return false;
        bool matchesSearch = _searchQuery.isEmpty || doc.code.toLowerCase().contains(_searchQuery.toLowerCase()) || doc.type.toLowerCase().contains(_searchQuery.toLowerCase()) || doc.remarks.toLowerCase().contains(_searchQuery.toLowerCase()) || doc.person.toLowerCase().contains(_searchQuery.toLowerCase()) || doc.fromOrTo.toLowerCase().contains(_searchQuery.toLowerCase()) || (doc.description?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) || (doc.referenceLink?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
        bool matchesDate = true;
        if (_startDate != null || _endDate != null) {
          final docDate = _parseDate(doc.fromOrTo);
          if (_startDate != null && docDate.isBefore(_startDate!)) matchesDate = false;
          if (_endDate != null && docDate.isAfter(_endDate!)) matchesDate = false;
        }
        return matchesSearch && matchesDate;
      }).toList()..sort((a, b) {
          final aDate = a.history.isNotEmpty ? a.history.last.timestamp : (a.createdAt ?? DateTime(1900));
          final bDate = b.history.isNotEmpty ? b.history.last.timestamp : (b.createdAt ?? DateTime(1900));
          return bDate.compareTo(aDate);
        });
    });
  }

  void _showViewersDialog(BuildContext context, String documentCode) {
    showDialog(
      context: context,
      builder: (_) => _ViewersDialog(documentCode: documentCode),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConnectivityBanner(
      child: Scaffold(
        floatingActionButton: FloatingActionButton(
          onPressed: () async { await Navigator.push(context, MaterialPageRoute(builder: (context) => const AddReclassificationScreen())); await _refreshDocuments(); if (widget.onRefresh != null) widget.onRefresh!(); },
          backgroundColor: const Color(0xFF66BB6A),
          child: const Icon(Icons.add),
        ),
        appBar: AppBar(
          title: const Text("Reclassification"),
          backgroundColor: const Color(0xFF66BB6A),
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(104),
            child: DocumentSearchBar(
              controller: _searchController,
              onSearch: (query) {
                _searchQuery = query;
                _filterDocuments();
              },
              onFilterTap: () => _showFilterDialog(context, setState),
              hasActiveFilter: _startDate != null || _endDate != null || _specificDate != null,
              resultCount: _filteredDocuments.length,
              totalCount: widget.documents.where((d) => d.mode == 'Reclassification').length,
            ),
          ),
        ),
        body: RefreshIndicator(
          onRefresh: () async { if (widget.onRefresh != null) widget.onRefresh!(); },
          child: Container(
            decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Theme.of(context).colorScheme.surface, Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3)])),
            child: _isLoading
                ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Loading documents...', style: TextStyle(fontSize: 16))]))
                : _filteredDocuments.isEmpty
                ? const Center(child: Text('No Reclassification records found', style: TextStyle(fontSize: 16, color: Colors.grey)))
                : Column(
                    children: [
                      const UploadStatusBanner(),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                          itemCount: _filteredDocuments.length,
                          separatorBuilder: (_, __) => const Divider(height: 8, thickness: 1),
                          itemBuilder: (context, index) {
                            final document = _filteredDocuments[index];
                            return Container(
                              color: document.needsSync ? Colors.yellow[100] : null,
                              child: ExpansionTile(
                                onExpansionChanged: (expanded) { setState(() { if (expanded) _expandedTiles.add(index); else _expandedTiles.remove(index); }); },
                                leading: _statusIcon(document.status),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: _expandedTiles.contains(index)
                                        ? GestureDetector(
                                            onTap: () {
                                              Clipboard.setData(ClipboardData(text: document.code));
                                              SnackbarUtils.showInfoSnackBar(context, 'Code copied to clipboard');
                                            },
                                            child: Text(document.code, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.blue, decoration: TextDecoration.underline)),
                                          )
                                        : Text(document.code, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                    ),
                                    if (document.needsSync) ...[
                                      const SizedBox(width: 8),
                                      const Icon(Icons.sync, size: 16, color: Colors.orange),
                                    ],
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (document.title != null && document.title!.isNotEmpty)
                                      Text('${document.type} - ${document.title}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                                    const SizedBox(height: 3),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(color: Colors.blueGrey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                                          child: Text(document.assignedTo, style: const TextStyle(fontSize: 10, color: Colors.blueGrey, fontWeight: FontWeight.w500)),
                                        ),
                                        if (document.imageUrls.isEmpty && document.fileUrls.isEmpty && document.filePath == null && document.localImagePaths.isEmpty && document.localFilePaths.isEmpty) ...[
                                          const SizedBox(width: 6),
                                          Tooltip(
                                            message: 'No attachment',
                                            child: Icon(Icons.image_not_supported_outlined, size: 12, color: Colors.grey[400]),
                                          ),
                                        ],
                                      ],
                                    ),
                                    _buildUploadStatusIndicator(document),
                                  ],
                                ),
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3), borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12))),
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      _buildDetailRow(Icons.description, "Document Type", document.type),
                                      if (document.description != null && document.description!.isNotEmpty) ...[const SizedBox(height: 8), _buildDetailRow(Icons.notes, "Description", document.description!)],
                                      const SizedBox(height: 8), _buildDetailRow(Icons.calendar_today, "Date", document.fromOrTo),
                                      const SizedBox(height: 8), _buildDetailRow(Icons.person, "Recorded by", document.person),
                                      const SizedBox(height: 8), _buildDetailRow(Icons.access_time, "Timestamp", document.createdAt != null ? _formatDateTime(document.createdAt!) : 'Unknown'),
                                      if (document.referenceLink != null && document.referenceLink!.isNotEmpty) ...[const SizedBox(height: 8), GestureDetector(onTap: () async { final uri = Uri.parse(document.referenceLink!); if (await canLaunchUrl(uri)) await launchUrl(uri); }, child: Row(children: [const Icon(Icons.link, color: Colors.blue), const SizedBox(width: 8), Expanded(child: Text(document.referenceLink!, style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline), overflow: TextOverflow.ellipsis))]))],
                                      if (document.remarks.isNotEmpty) ...[const SizedBox(height: 8), _buildDetailRow(Icons.comment, "Remarks", document.remarks)],
                                      const SizedBox(height: 16),
                                      Row(children: [Wrap(spacing: 2, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                                        if (_username == document.person) ElevatedButton(onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (context) => EditDocumentScreen(document: document))).then((_) { if (widget.onRefresh != null) widget.onRefresh!(); }); }, style: ElevatedButton.styleFrom(backgroundColor: const Color.fromARGB(255, 78, 127, 218), foregroundColor: Colors.white, minimumSize: const Size(40, 36), padding: const EdgeInsets.symmetric(horizontal: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: const Icon(Icons.edit, size: 18)),
                                        if (_username == document.person) ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color.fromARGB(255, 218, 87, 78), foregroundColor: Colors.white, minimumSize: const Size(40, 36), padding: const EdgeInsets.symmetric(horizontal: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), onPressed: () async { final deleted = await confirmAndDeleteRecord(context, document, CachedDocumentService()); if (deleted && mounted) { setState(() => _filteredDocuments.removeAt(index)); if (widget.onRefresh != null) widget.onRefresh!(); } }, child: const Icon(Icons.delete, size: 18)),
                                        if (document.imageUrls.isNotEmpty || document.localImagePaths.isNotEmpty) ElevatedButton(onPressed: () => _showImageDialog(context, document.imageUrls.isNotEmpty ? document.imageUrls : document.localImagePaths, documentCode: document.code), style: ElevatedButton.styleFrom(minimumSize: const Size(40, 36), padding: const EdgeInsets.symmetric(horizontal: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: const Icon(Icons.image, size: 18)),
                                        if (document.filePath != null || document.fileUrls.isNotEmpty) ElevatedButton(onPressed: () { final allFiles = <String>[]; if (document.filePath != null) allFiles.add(document.filePath!); allFiles.addAll(document.fileUrls); if (allFiles.length == 1) _viewFile(allFiles[0], title: document.title ?? document.type, documentCode: document.code); else _showFileDialog(context, document); }, style: ElevatedButton.styleFrom(minimumSize: const Size(40, 36), padding: const EdgeInsets.symmetric(horizontal: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: const Icon(Icons.attach_file, size: 18)),
                                        if (document.imageUrls.isNotEmpty || document.fileUrls.isNotEmpty) ElevatedButton(onPressed: () => _shareDocument(document), style: ElevatedButton.styleFrom(minimumSize: const Size(40, 36), padding: const EdgeInsets.symmetric(horizontal: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: const Icon(Icons.share, size: 18)),
                                      ]), const Spacer(), if (document.imageUrls.isNotEmpty || document.fileUrls.isNotEmpty) IconButton(icon: const Icon(Icons.remove_red_eye_outlined, size: 20), tooltip: 'View who opened attachments', onPressed: () => _showViewersDialog(context, document.code), style: IconButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),),), ]),
                                    ]),
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

  Future<void> _shareDocument(Document doc) async {
    final title = (doc.title != null && doc.title!.isNotEmpty) ? '${doc.type} - ${doc.title}' : doc.type;
    if (doc.imageUrls.isEmpty && doc.fileUrls.isEmpty) { Share.share(title, subject: title); return; }
    if (kIsWeb) {
      String? extractFileId(String url) {
        if (url.contains('uc?id=')) return Uri.parse(url).queryParameters['id'];
        final m = RegExp(r'/file/d/([a-zA-Z0-9_-]+)').firstMatch(url);
        if (m != null) return m.group(1);
        if (RegExp(r'^[a-zA-Z0-9_-]{20,}$').hasMatch(url)) return url;
        return null;
      }
      final viewLinks = [...doc.imageUrls, ...doc.fileUrls].map(extractFileId).whereType<String>().map((id) => 'https://drive.google.com/file/d/$id/view').toList();
      final shareText = viewLinks.isEmpty ? title : '$title\n\n${viewLinks.join('\n')}';
      await Clipboard.setData(ClipboardData(text: shareText));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(viewLinks.isEmpty ? 'Title copied to clipboard' : 'Links copied to clipboard'), duration: const Duration(seconds: 4)));
      Share.share(shareText, subject: title);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Row(children: [SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)), SizedBox(width: 12), Text('Preparing files to share...')]), duration: Duration(seconds: 60)));
    try {
      final tempDir = await getTemporaryDirectory();
      final xFiles = <XFile>[];
      final safeTitle = title.replaceAll(RegExp(r'[<>:"/\\|?*\r\n]'), '').replaceAll(RegExp(r'\s+'), '_').trim();
      Future<List<int>?> fetchViaProxy(String url) async {
        try {
          final fileId = url.contains('drive.google.com/uc?id=') ? Uri.parse(url).queryParameters['id'] ?? url : url;
          final res = await http.get(Uri.parse(GoogleDriveService.generateProxyUrl(fileId))).timeout(const Duration(seconds: 30));
          if (res.statusCode != 200 || (res.headers['content-type'] ?? '').contains('text/html')) return null;
          return res.bodyBytes;
        } catch (_) { return null; }
      }
      for (int i = 0; i < doc.imageUrls.length; i++) {
        final bytes = await fetchViaProxy(doc.imageUrls[i]);
        if (bytes != null) {
          final mimeType = (bytes.length >= 4 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) ? 'image/png' : 'image/jpeg';
          final file = File('${tempDir.path}/${safeTitle}_${i + 1}.${mimeType == 'image/png' ? 'png' : 'jpg'}');
          await file.writeAsBytes(bytes);
          xFiles.add(XFile(file.path, mimeType: mimeType));
        }
      }
      String? toViewLink(String url) {
        if (url.contains('uc?id=')) { final id = Uri.parse(url).queryParameters['id']; if (id != null) return 'https://drive.google.com/file/d/$id/view'; return null; }
        final m = RegExp(r'/file/d/([a-zA-Z0-9_-]+)').firstMatch(url);
        if (m != null) return 'https://drive.google.com/file/d/${m.group(1)}/view';
        if (RegExp(r'^[a-zA-Z0-9_-]{20,}$').hasMatch(url)) return 'https://drive.google.com/file/d/$url/view';
        return null;
      }
      final pdfLinks = doc.fileUrls.map(toViewLink).whereType<String>().toList();
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      final clipboardText = pdfLinks.isEmpty ? title : '$title\n\n${pdfLinks.join('\n')}';
      await Clipboard.setData(ClipboardData(text: clipboardText));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(pdfLinks.isEmpty ? 'Title copied to clipboard' : 'PDF links copied to clipboard'), duration: const Duration(seconds: 5)));
      if (xFiles.isNotEmpty) { await Share.shareXFiles(xFiles, subject: title); } else if (pdfLinks.isNotEmpty) { await Share.share(clipboardText, subject: title); } else { Share.share(title, subject: title); }
    } catch (e) { if (!mounted) return; ScaffoldMessenger.of(context).hideCurrentSnackBar(); SnackbarUtils.showErrorSnackBar(context, 'Failed to prepare files for sharing'); }
  }

  void _showImageDialog(BuildContext context, List<String> imageUrls, {String? documentCode}) {
    if (documentCode != null && _username != null && _username!.isNotEmpty) {
      AttachmentViewService.recordView(
        documentCode: documentCode,
        username: _username!,
        attachmentType: 'image',
      );
    }
    ScrollableImageViewer.show(context, imageUrls: imageUrls);
  }

  void _showFileDialog(BuildContext context, Document document) {
    final allFiles = <String>[]; final allNames = <String>[];
    if (document.filePath != null) { allFiles.add(document.filePath!); allNames.add(document.fileName ?? document.filePath!.split('/').last.split('\\').last); }
    for (int i = 0; i < document.fileUrls.length; i++) { allFiles.add(document.fileUrls[i]); allNames.add(i < document.fileNames.length ? document.fileNames[i] : document.fileUrls[i].split('/').last.split('\\').last); }
    showDialog(context: context, builder: (context) => AlertDialog(title: const Text('Select File to View'), content: SizedBox(width: double.maxFinite, child: ListView.builder(shrinkWrap: true, itemCount: allFiles.length, itemBuilder: (context, index) => ListTile(leading: const Icon(Icons.attach_file), title: Text(allNames[index]), onTap: () { Navigator.pop(context); _viewFile(allFiles[index], title: document.title ?? document.type, documentCode: document.code); }))), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))]));
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
        _filterDocuments();
      },
    );
  }

  String? _extractFileId(String url) {
    if (url.contains('drive.google.com')) { final uri = Uri.parse(url); if (url.contains('/file/d/')) { final segments = uri.pathSegments; final fileIndex = segments.indexOf('d'); if (fileIndex != -1 && fileIndex + 1 < segments.length) return segments[fileIndex + 1]; } else if (url.contains('uc?id=')) return uri.queryParameters['id']; }
    if (RegExp(r'^[a-zA-Z0-9_-]{20,}$').hasMatch(url)) return url;
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
    if (username != null && username.isNotEmpty) setState(() => _username = username);
  }
}

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
      title: Row(children: [
        Icon(Icons.remove_red_eye_outlined, color: Theme.of(context).colorScheme.primary, size: 20),
        const SizedBox(width: 8),
        const Text('Attachment Viewers', style: TextStyle(fontSize: 16)),
      ]),
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
              return const Center(child: Text('No views recorded yet', style: TextStyle(color: Colors.grey)));
            }
            return ListView.separated(
              itemCount: viewers.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final v = viewers[i];
                return ListTile(
                  dense: true,
                  leading: Icon(
                    v.attachmentType == 'pdf' ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
                    size: 20,
                    color: v.attachmentType == 'pdf' ? Colors.red[400] : Colors.blue[400],
                  ),
                  title: Text(v.username, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
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
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        TextButton(
          onPressed: () => setState(() { _future = AttachmentViewService.getViewers(widget.documentCode); }),
          child: const Text('Refresh'),
        ),
      ],
    );
  }
}
