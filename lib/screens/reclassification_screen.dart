import 'dart:io';
import 'package:com.cpdco.docutracker/screens/add_reclassification_screen.dart';
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
import '../services/upload_queue_manager.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/connectivity_banner.dart';
import '../utils/delete_utils.dart';
import '../services/cached_document_service.dart';
import '../services/auth_service.dart';
import '../services/google_drive_service.dart';
import '../config/supabase_config.dart';
import 'edit_document_screen.dart';

class ReclassificationScreen extends StatefulWidget {
  final List<Document> documents;
  final Function(int, String, String, {String? notes}) transferDocument;
  final Function(int, String, String, {String? notes, DateTime? complianceDeadline, String? complianceAssignee}) updateDocumentStatus;
  final Function(int) deleteDocument;
  final Function(String) syncDocument;
  final VoidCallback? onRefresh;

  const ReclassificationScreen({
    super.key,
    required this.documents,
    required this.transferDocument,
    required this.updateDocumentStatus,
    required this.deleteDocument,
    required this.syncDocument,
    this.onRefresh,
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

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 8), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: TextStyle(fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.primary, fontSize: 12)), Text(value, style: const TextStyle(fontSize: 14))]))]);
  }

  Widget _buildGlobalUploadStatusIndicator() {
    final queueManager = UploadQueueManager();
    final allUploads = queueManager.getAllItems();
    final uploadingUploads = allUploads.where((item) => item['status'] == 'uploading').toList();
    final pendingUploads = allUploads.where((item) => item['status'] == 'pending').toList();
    if (uploadingUploads.isEmpty && pendingUploads.isEmpty) return const SizedBox.shrink();
    final totalUploading = uploadingUploads.length;
    final totalPending = pendingUploads.length;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.withOpacity(0.3))),
      child: Row(children: [SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.orange))), const SizedBox(width: 12), Expanded(child: Text(totalUploading > 0 ? 'Uploading $totalUploading file${totalUploading > 1 ? 's' : ''}${totalPending > 0 ? ', $totalPending pending' : ''}...' : 'Processing $totalPending upload${totalPending > 1 ? 's' : ''}...', style: TextStyle(fontSize: 14, color: Colors.orange[700], fontWeight: FontWeight.w500)))]),
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
    _searchController.addListener(() { _searchQuery = _searchController.text; _filterDocuments(); });
    _filteredDocuments = widget.documents.where((doc) => doc.mode == 'Reclassification').toList()..sort((a, b) => _parseDate(b.fromOrTo).compareTo(_parseDate(a.fromOrTo)));
    _uploadQueueManager = UploadQueueManager();
    _uploadQueueManager.addListener(_onUploadChanged);
    _loadUsername();
    Future.delayed(const Duration(milliseconds: 500), () { if (mounted) setState(() => _isLoading = false); });
  }

  void _onUploadChanged() { setState(() {}); }

  @override
  void dispose() { _uploadQueueManager.removeListener(_onUploadChanged); super.dispose(); }

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
      }).toList()..sort((a, b) => _parseDate(b.fromOrTo).compareTo(_parseDate(a.fromOrTo)));
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
      }).toList()..sort((a, b) => _parseDate(b.fromOrTo).compareTo(_parseDate(a.fromOrTo)));
    });
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
            preferredSize: const Size.fromHeight(80),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(child: TextField(controller: _searchController, decoration: InputDecoration(hintText: 'Search documents...', prefixIcon: const Icon(Icons.search), filled: true, fillColor: Theme.of(context).colorScheme.surface, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))),
                  IconButton(icon: const Icon(Icons.filter_list), onPressed: () => _showFilterDialog(context, setState), tooltip: 'Filter by Date'),
                ],
              ),
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
                      _buildGlobalUploadStatusIndicator(),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                          itemCount: _filteredDocuments.length,
                          itemBuilder: (context, index) {
                            final document = _filteredDocuments[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              elevation: 2,
                              color: document.needsSync ? Colors.grey[100] : null,
                              child: ExpansionTile(
                                onExpansionChanged: (expanded) { setState(() { if (expanded) _expandedTiles.add(index); else _expandedTiles.remove(index); }); },
                                leading: CircleAvatar(backgroundColor: const Color(0xFF1B5E20), child: const Icon(Icons.swap_horizontal_circle_outlined, color: Colors.white, size: 20)),
                                title: Text(document.category ?? document.type, style: const TextStyle(fontWeight: FontWeight.w400), maxLines: 2, overflow: TextOverflow.ellipsis),
                                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Text('${document.code}  '), if (_expandedTiles.contains(index)) IconButton(icon: const Icon(Icons.copy, size: 16), onPressed: () { Clipboard.setData(ClipboardData(text: document.code)); SnackbarUtils.showInfoSnackBar(context, 'Code copied to clipboard'); }, tooltip: 'Copy Code', padding: EdgeInsets.zero, constraints: const BoxConstraints())]), const SizedBox(height: 4), _buildUploadStatusIndicator(document)]),
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
                                      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                                        if (_username == document.person) ElevatedButton.icon(icon: const Icon(Icons.edit), label: const SizedBox.shrink(), onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (context) => EditDocumentScreen(document: document))).then((_) { if (widget.onRefresh != null) widget.onRefresh!(); }); }, style: ElevatedButton.styleFrom(backgroundColor: const Color.fromARGB(255, 78, 127, 218), minimumSize: const Size(48, 40), padding: const EdgeInsets.only(left: 10), alignment: Alignment.center, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
                                        if (_username == document.person) ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color.fromARGB(255, 218, 87, 78), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), onPressed: () async { final deleted = await confirmAndDeleteRecord(context, document, CachedDocumentService()); if (deleted && mounted) { setState(() => _filteredDocuments.removeAt(index)); if (widget.onRefresh != null) widget.onRefresh!(); } }, child: const Icon(Icons.delete)),
                                        if (document.imageUrls.isNotEmpty || document.localImagePaths.isNotEmpty) ElevatedButton(onPressed: () => _showImageDialog(context, document.imageUrls.isNotEmpty ? document.imageUrls : document.localImagePaths), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: const Icon(Icons.image)),
                                        if (document.filePath != null || document.fileUrls.isNotEmpty) ElevatedButton(onPressed: () { final allFiles = <String>[]; if (document.filePath != null) allFiles.add(document.filePath!); allFiles.addAll(document.fileUrls); if (allFiles.length == 1) _viewFile(allFiles[0]); else _showFileDialog(context, document); }, style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: const Icon(Icons.attach_file)),
                                        if (document.imageUrls.isNotEmpty || document.fileUrls.isNotEmpty) ElevatedButton(onPressed: () => _shareDocument(document), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: const Icon(Icons.share)),
                                      ]),
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

  void _showImageDialog(BuildContext context, List<String> imageUrls) {
    showDialog(
      context: context, barrierDismissible: true, barrierColor: Colors.black.withOpacity(0.5),
      builder: (dialogContext) {
        int currentIndex = 0; bool isDownloading = false; bool isSuccess = false;
        final PageController pageController = PageController();
        return StatefulBuilder(builder: (context, setState) {
          return Dialog(backgroundColor: Colors.white, insetPadding: const EdgeInsets.all(14), child: SizedBox.expand(child: Stack(children: [
            PageView.builder(controller: pageController, itemCount: imageUrls.length, onPageChanged: (index) => setState(() => currentIndex = index), itemBuilder: (context, index) {
              final imageUrl = imageUrls[index];
              final proxyUrl = imageUrl.contains('drive.google.com/uc?id=') ? GoogleDriveService.generateProxyUrl(Uri.parse(imageUrl).queryParameters['id'] ?? imageUrl) : GoogleDriveService.generateProxyUrl(imageUrl);
              return InteractiveViewer(child: Center(child: CachedNetworkImage(imageUrl: proxyUrl, httpHeaders: {'Authorization': 'Bearer ${SupabaseConfig.supabaseAnonKey}'}, fit: BoxFit.contain, placeholder: (context, url) => const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 16), Text('wait la po...', style: TextStyle(color: Colors.black, fontSize: 16))])), errorWidget: (context, url, error) => const Center(child: Text('Failed to load image')))));
            }),
            if (imageUrls.length > 1) ...[
              Positioned(left: 8, top: 0, bottom: 0, child: Center(child: IconButton(icon: const Icon(Icons.chevron_left, size: 36, color: Colors.white), style: IconButton.styleFrom(backgroundColor: Colors.black45, shape: const CircleBorder()), onPressed: currentIndex == 0 ? null : () => pageController.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeInOut)))),
              Positioned(right: 8, top: 0, bottom: 0, child: Center(child: IconButton(icon: const Icon(Icons.chevron_right, size: 36, color: Colors.white), style: IconButton.styleFrom(backgroundColor: Colors.black45, shape: const CircleBorder()), onPressed: currentIndex == imageUrls.length - 1 ? null : () => pageController.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeInOut)))),
              Positioned(bottom: 16, left: 0, right: 0, child: Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)), child: Text('${currentIndex + 1} / ${imageUrls.length}', style: const TextStyle(color: Colors.white, fontSize: 13))))),
            ],
            Positioned(top: 40, right: 20, child: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.download, color: Colors.black, size: 30), onPressed: isDownloading ? null : () async { setState(() { isDownloading = true; isSuccess = false; }); try { await ImageDownloadService.downloadAndSave(imageUrls[currentIndex]); if (context.mounted) { setState(() { isDownloading = false; isSuccess = true; }); await Future.delayed(const Duration(milliseconds: 1500)); if (context.mounted) setState(() => isSuccess = false); } } catch (e) { if (context.mounted) { setState(() => isDownloading = false); SnackbarUtils.showErrorSnackBar(context, e.toString().replaceAll('Exception: ', '')); } } }, tooltip: 'Download Image'),
              IconButton(icon: const Icon(Icons.close, color: Colors.black, size: 30), onPressed: () => Navigator.pop(dialogContext)),
            ])),
            if (isDownloading || isSuccess) Container(color: Colors.black.withOpacity(0.4), child: Center(child: AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: isDownloading ? const CircularProgressIndicator(key: ValueKey('loading'), color: Colors.white) : Column(mainAxisSize: MainAxisSize.min, children: const [Icon(Icons.check, color: Colors.green, size: 48), SizedBox(height: 8), Text('Saved!', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600))])))),
          ])));
        });
      },
    );
  }

  void _showFileDialog(BuildContext context, Document document) {
    final allFiles = <String>[]; final allNames = <String>[];
    if (document.filePath != null) { allFiles.add(document.filePath!); allNames.add(document.fileName ?? document.filePath!.split('/').last.split('\\').last); }
    for (int i = 0; i < document.fileUrls.length; i++) { allFiles.add(document.fileUrls[i]); allNames.add(i < document.fileNames.length ? document.fileNames[i] : document.fileUrls[i].split('/').last.split('\\').last); }
    showDialog(context: context, builder: (context) => AlertDialog(title: const Text('Select File to View'), content: SizedBox(width: double.maxFinite, child: ListView.builder(shrinkWrap: true, itemCount: allFiles.length, itemBuilder: (context, index) => ListTile(leading: const Icon(Icons.attach_file), title: Text(allNames[index]), onTap: () { Navigator.pop(context); _viewFile(allFiles[index]); }))), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))]));
  }

  void _showFilterDialog(BuildContext context, StateSetter setState) {
    showDialog(context: context, barrierDismissible: true, builder: (_) => StatefulBuilder(builder: (context, dialogSetState) => AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), title: Row(children: [Icon(Icons.filter_list, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 8), const Text("Filter Documents", style: TextStyle(fontSize: 16))]), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(height: 16),
      TextField(readOnly: true, controller: TextEditingController(text: _specificDate != null ? "${_specificDate!.month}/${_specificDate!.day}/${_specificDate!.year}" : ''), decoration: InputDecoration(labelText: "Specific Date", prefixIcon: const Icon(Icons.calendar_today), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))), onTap: () async { final picked = await showDatePicker(context: context, initialDate: _specificDate ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime.now()); if (picked != null) { dialogSetState(() {}); setState(() { _specificDate = picked; _startDate = picked; _endDate = picked; }); } }),
      const SizedBox(height: 16),
      TextField(readOnly: true, controller: TextEditingController(text: _startDate != null ? "${_startDate!.month}/${_startDate!.day}/${_startDate!.year}" : ''), decoration: InputDecoration(labelText: "Start Date", prefixIcon: const Icon(Icons.calendar_today), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))), onTap: () async { final picked = await showDatePicker(context: context, initialDate: _startDate ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime.now()); if (picked != null) { dialogSetState(() {}); setState(() { _startDate = picked; _specificDate = null; }); } }),
      const SizedBox(height: 16),
      TextField(readOnly: true, controller: TextEditingController(text: _endDate != null ? "${_endDate!.month}/${_endDate!.day}/${_endDate!.year}" : ''), decoration: InputDecoration(labelText: "End Date", prefixIcon: const Icon(Icons.calendar_today), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))), onTap: () async { final picked = await showDatePicker(context: context, initialDate: _endDate ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime.now()); if (picked != null) { dialogSetState(() {}); setState(() { _endDate = picked; _specificDate = null; }); } }),
    ])), actions: [
      TextButton(onPressed: () { dialogSetState(() {}); setState(() { _specificDate = null; _startDate = null; _endDate = null; }); _filterDocuments(); Navigator.pop(context); }, child: const Text("Clear All")),
      ElevatedButton.icon(icon: const Icon(Icons.filter_list), label: const Text("Apply"), style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), onPressed: () { _filterDocuments(); Navigator.pop(context); }),
    ])));
  }

  String? _extractFileId(String url) {
    if (url.contains('drive.google.com')) { final uri = Uri.parse(url); if (url.contains('/file/d/')) { final segments = uri.pathSegments; final fileIndex = segments.indexOf('d'); if (fileIndex != -1 && fileIndex + 1 < segments.length) return segments[fileIndex + 1]; } else if (url.contains('uc?id=')) return uri.queryParameters['id']; }
    if (RegExp(r'^[a-zA-Z0-9_-]{20,}$').hasMatch(url)) return url;
    return null;
  }

  void _viewFile(String filePath) async {
    try {
      final fileId = _extractFileId(filePath);
      if (fileId == null) { SnackbarUtils.showErrorSnackBar(context, 'Invalid file format'); return; }
      final uri = Uri.parse(kIsWeb ? 'https://drive.google.com/uc?id=$fileId&export=download' : 'https://drive.google.com/file/d/$fileId/view?usp=sharing');
      if (await canLaunchUrl(uri)) { await launchUrl(uri); } else { SnackbarUtils.showErrorSnackBar(context, 'Could not open file'); }
    } catch (e) { SnackbarUtils.showErrorSnackBar(context, 'Could not open file'); }
  }

  Future<void> _loadUsername() async {
    final username = await AuthService.getUsername();
    if (username != null && username.isNotEmpty) setState(() => _username = username);
  }
}
