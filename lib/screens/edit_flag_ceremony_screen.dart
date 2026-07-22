import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/document.dart';
import '../services/cached_document_service.dart';
import '../services/document_scanner_service.dart';
import '../services/mlkit_scanner_service.dart';
import '../services/pdf_export_service.dart';
import '../services/google_drive_service.dart';
import '../services/upload_queue_manager.dart';
import '../utils/snackbar_utils.dart';
import '../config/supabase_config.dart';

class EditFlagCeremonyScreen extends StatefulWidget {
  final Document document;

  const EditFlagCeremonyScreen({super.key, required this.document});

  @override
  State<EditFlagCeremonyScreen> createState() => _EditFlagCeremonyScreenState();
}

class _EditFlagCeremonyScreenState extends State<EditFlagCeremonyScreen> {
  final ImagePicker _picker = ImagePicker();

  String? _selectedCeremonyType;
  DateTime? _selectedDate;
  final _remarksController = TextEditingController();

  // Existing attachments
  List<String> _currentImageUrls = [];
  List<String> _currentFileUrls = [];
  List<String> _currentFileNames = [];

  // New attachments
  List<String> _selectedImagePaths = [];
  List<String> _selectedDocumentPaths = [];
  List<List<int>?> _selectedImageBytes = [];
  final Map<String, List<int>> _webFileBytes = {};

  bool _isPickingImage = false;
  bool _isPickingFile = false;
  bool _isSaving = false;
  bool _isMergingPdf = false;
  bool _showValidationErrors = false;
  String _uploadStatus = '';
  int _totalUploads = 0;
  int _completedUploads = 0;

  final List<String> _ceremonyTypes = ['Flag Raising', 'Flag Lowering'];

  bool _isImage(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'heic', 'heif'].contains(ext);
  }

  bool _isDocument(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return ['pdf', 'docx'].contains(ext);
  }

  @override
  void initState() {
    super.initState();
    _selectedCeremonyType = widget.document.type;
    _selectedDate = _parseDate(widget.document.fromOrTo);
    _remarksController.text = widget.document.remarks;
    _currentImageUrls = List.from(widget.document.imageUrls);
    _currentFileUrls = List.from(widget.document.fileUrls);
    _currentFileNames = List.from(widget.document.fileNames);
    _setupUploadListener();
  }

  DateTime _parseDate(String dateStr) {
    try {
      final parts = dateStr.split('/');
      if (parts.length == 3) {
        return DateTime(int.parse(parts[2]), int.parse(parts[0]), int.parse(parts[1]));
      }
    } catch (_) {}
    return DateTime.now();
  }

  void _setupUploadListener() {
    UploadQueueManager().addListener(_onUploadStatusChanged);
  }

  @override
  void dispose() {
    UploadQueueManager().removeListener(_onUploadStatusChanged);
    _remarksController.dispose();
    super.dispose();
  }

  void _onUploadStatusChanged() {
    if (!mounted) return;
    final queueManager = UploadQueueManager();
    final code = widget.document.code;
    final pending = queueManager.getPendingUploads(code);
    final uploading = queueManager.getAllItems()
        .where((i) => i['documentCode'] == code && i['status'] == 'uploading')
        .toList();
    final completed = queueManager.getAllItems()
        .where((i) => i['documentCode'] == code && i['status'] == 'completed')
        .toList();
    setState(() {
      _totalUploads = _selectedImagePaths.length + _selectedDocumentPaths.length;
      _completedUploads = completed.length;
      _uploadStatus = uploading.isNotEmpty
          ? 'Uploading ${uploading.length} file(s)...'
          : pending.isEmpty
              ? 'All uploads completed'
              : 'Preparing uploads...';
    });
    if (_isSaving && pending.isEmpty && uploading.isEmpty) {
      _isSaving = false;
      if (mounted) Navigator.pop(context);
    }
  }

  Future<bool> _onWillPop() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Exit'),
        content: const Text('Do you want to exit without saving?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  // ── Scanner (same pipeline as add_flag_ceremony_screen) ──────────────────

  Future<ImageSource?> _chooseWebScanSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text('Scan Document', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                subtitle: const Text('Scan with device camera'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery'),
                subtitle: const Text('Choose from photo library'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _takePicture() async {
    if (!kIsWeb && Platform.isAndroid) {
      await _scanWithMlKit();
      return;
    }
    final ImageSource? source = await _chooseWebScanSource();
    if (source == null || !mounted) return;
    if (_selectedImagePaths.where(_isImage).length >= 20) {
      SnackbarUtils.showErrorSnackBar(context, 'Maximum 20 images allowed');
      return;
    }
    setState(() => _isPickingImage = true);
    final XFile? image = await _picker.pickImage(source: source);
    if (image == null) {
      if (!mounted) return;
      setState(() => _isPickingImage = false);
      SnackbarUtils.showErrorSnackBar(context, 'No image captured');
      return;
    }
    final rawBytes = await image.readAsBytes();
    final scannedBytes = kIsWeb
        ? rawBytes
        : (await DocumentScannerService.processImage(rawBytes) ?? rawBytes);
    if (!mounted) return;
    if (kIsWeb) {
      final fileName = 'scanned_${DateTime.now().millisecondsSinceEpoch}.jpg';
      setState(() {
        _selectedImagePaths.add(fileName);
        _selectedImageBytes.add(scannedBytes);
        _isPickingImage = false;
      });
      UploadQueueManager().addWebCameraImageToQueue(
        documentCode: widget.document.code,
        filePath: fileName,
        bytes: scannedBytes,
      );
    } else {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/scanned_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(scannedBytes);
      if (!mounted) return;
      setState(() {
        _selectedImagePaths.add(tempFile.path);
        _selectedImageBytes.add(null);
        _isPickingImage = false;
      });
      UploadQueueManager().addToQueue(
        documentCode: widget.document.code,
        filePath: tempFile.path,
        isImage: true,
        localPath: tempFile.path,
      );
    }
  }

  Future<void> _scanWithMlKit() async {
    final int remaining = 20 - _selectedImagePaths.where(_isImage).length;
    if (remaining <= 0) { SnackbarUtils.showErrorSnackBar(context, 'Maximum 20 images allowed'); return; }
    setState(() => _isPickingImage = true);
    ScannerOutput? output;
    try {
      output = await MlKitScannerService.scanDocument(maxPages: remaining, format: ScanOutputFormat.image);
    } catch (_) { output = null; }
    if (!mounted) return;
    if (output == null) {
      setState(() => _isPickingImage = false);
      if (_selectedImagePaths.where(_isImage).length >= 20) { SnackbarUtils.showErrorSnackBar(context, 'Maximum 20 images allowed'); return; }
      setState(() => _isPickingImage = true);
      final XFile? image = await _picker.pickImage(source: ImageSource.camera);
      if (image == null) { if (!mounted) return; setState(() => _isPickingImage = false); SnackbarUtils.showErrorSnackBar(context, 'No image captured'); return; }
      final rawBytes = await image.readAsBytes();
      final scannedBytes = kIsWeb ? rawBytes : (await DocumentScannerService.processImage(rawBytes) ?? rawBytes);
      if (!mounted) return;
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/scanned_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(scannedBytes);
      if (!mounted) return;
      setState(() { _selectedImagePaths.add(tempFile.path); _selectedImageBytes.add(null); _isPickingImage = false; });
      UploadQueueManager().addToQueue(documentCode: widget.document.code, filePath: tempFile.path, isImage: true, localPath: tempFile.path);
      return;
    }
    if (output.wasCancelled) { setState(() => _isPickingImage = false); return; }
    try {
      final tempDir = await getTemporaryDirectory();
      for (var i = 0; i < output.images.length; i++) {
        final tempFile = File('${tempDir.path}/mlkit_${DateTime.now().millisecondsSinceEpoch}_$i.jpg');
        await tempFile.writeAsBytes(output.images[i]);
        if (!mounted) return;
        setState(() { _selectedImagePaths.add(tempFile.path); _selectedImageBytes.add(null); });
        UploadQueueManager().addToQueue(documentCode: widget.document.code, filePath: tempFile.path, isImage: true, localPath: tempFile.path);
      }
    } finally {
      if (mounted) setState(() => _isPickingImage = false);
    }
  }

  Future<void> _mergeImagesToPdf() async {
    if (_isMergingPdf) return;
    setState(() => _isMergingPdf = true);
    try {
      final imageOnlyPaths = _selectedImagePaths.where(_isImage).toList();
      final List<Uint8List> imageBytesList = [];
      for (final path in imageOnlyPaths) {
        if (kIsWeb) {
          final idx = _selectedImagePaths.indexOf(path);
          if (idx >= 0 && idx < _selectedImageBytes.length && _selectedImageBytes[idx] != null) {
            imageBytesList.add(Uint8List.fromList(_selectedImageBytes[idx]!));
          } else if (_webFileBytes.containsKey(path)) {
            imageBytesList.add(Uint8List.fromList(_webFileBytes[path]!));
          }
        } else {
          try { imageBytesList.add(await File(path).readAsBytes()); } catch (_) {}
        }
      }
      if (imageBytesList.isEmpty) { if (mounted) SnackbarUtils.showErrorSnackBar(context, 'No image data available to convert'); return; }
      final pdfBytes = await PdfExportService.buildPdfFromLocalImages(imageBytesList);
      for (final path in imageOnlyPaths) { UploadQueueManager().removeFromQueue(widget.document.code, path); }
      if (kIsWeb) {
        final pdfFileName = 'merged_${DateTime.now().millisecondsSinceEpoch}.pdf';
        if (!mounted) return;
        setState(() { _selectedImagePaths.removeWhere(_isImage); _selectedImageBytes.clear(); _selectedDocumentPaths.add(pdfFileName); });
        _webFileBytes[pdfFileName] = pdfBytes;
        UploadQueueManager().addToQueue(documentCode: widget.document.code, filePath: pdfFileName, isImage: false, localPath: pdfFileName, bytes: pdfBytes);
      } else {
        final pdfFile = File('${(await getTemporaryDirectory()).path}/merged_${DateTime.now().millisecondsSinceEpoch}.pdf');
        await pdfFile.writeAsBytes(pdfBytes);
        if (!mounted) return;
        setState(() { _selectedImagePaths.removeWhere(_isImage); _selectedImageBytes.clear(); _selectedDocumentPaths.add(pdfFile.path); });
        UploadQueueManager().addToQueue(documentCode: widget.document.code, filePath: pdfFile.path, isImage: false, localPath: pdfFile.path);
      }
      if (mounted) SnackbarUtils.showSuccessSnackBar(context, '${imageOnlyPaths.length} image(s) merged into PDF');
    } catch (e) {
      if (mounted) SnackbarUtils.showErrorSnackBar(context, 'Failed to merge PDF: $e');
    } finally {
      if (mounted) setState(() => _isMergingPdf = false);
    }
  }

  // ── Save ─────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    setState(() => _showValidationErrors = true);
    if (_selectedCeremonyType == null || _selectedDate == null) return;

    final dateStr = '${_selectedDate!.month}/${_selectedDate!.day}/${_selectedDate!.year}';

    setState(() => _isSaving = true);
    try {
      final updates = {
        'type': _selectedCeremonyType,
        'category': _selectedCeremonyType,
        'from_or_to': dateStr,
        'remarks': _remarksController.text.trim(),
        'image_urls': _currentImageUrls,
        'file_urls': _currentFileUrls,
        'file_names': _currentFileNames,
        'local_image_paths': _selectedImagePaths,
        'local_file_paths': _selectedDocumentPaths,
      };

      await CachedDocumentService().updateDocument(widget.document.code, updates);
      await CachedDocumentService().processPendingUploads();
      await Future.delayed(const Duration(seconds: 2));

      final queueManager = UploadQueueManager();
      final pending = queueManager.getPendingUploads(widget.document.code);
      final uploading = queueManager.getAllItems()
          .where((i) => i['documentCode'] == widget.document.code && i['status'] == 'uploading')
          .toList();

      if (pending.isNotEmpty || uploading.isNotEmpty) {
        SnackbarUtils.showInfoSnackBar(context, 'Some files are still uploading. Please wait.');
        if (mounted) setState(() => _isSaving = false);
        return;
      }

      await CachedDocumentService().syncSpecificDocument(widget.document.code);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      SnackbarUtils.showErrorSnackBar(context, 'Failed to update record: $e');
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Edit Flag Ceremony Record'),
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF4EC377), Color(0xFF38A560)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          foregroundColor: Colors.white,
        ),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Basic Info ───────────────────────────────────────────
                Card(
                  elevation: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Basic Information',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Code (read-only)
                        TextField(
                          controller: TextEditingController(text: widget.document.code),
                          readOnly: true,
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                          decoration: const InputDecoration(
                            labelText: 'Document Code',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Ceremony Type
                        DropdownButtonFormField<String>(
                          value: _selectedCeremonyType,
                          decoration: InputDecoration(
                            labelText: 'Ceremony Type',
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                            errorText: _showValidationErrors && _selectedCeremonyType == null
                                ? 'Ceremony type is required'
                                : null,
                          ),
                          items: _ceremonyTypes
                              .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                              .toList(),
                          onChanged: _isSaving ? null : (v) => setState(() => _selectedCeremonyType = v),
                        ),
                        const SizedBox(height: 12),

                        // Ceremony Date
                        InkWell(
                          onTap: _isSaving ? null : () => _selectDate(context),
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Ceremony Date',
                              border: const OutlineInputBorder(),
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.surface,
                              suffixIcon: const Icon(Icons.calendar_today),
                              errorText: _showValidationErrors && _selectedDate == null
                                  ? 'Ceremony date is required'
                                  : null,
                            ),
                            child: Text(
                              _selectedDate != null
                                  ? '${_selectedDate!.month}/${_selectedDate!.day}/${_selectedDate!.year}'
                                  : 'Select date',
                              style: TextStyle(
                                color: _selectedDate != null
                                    ? Theme.of(context).colorScheme.onSurface
                                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Attachments ──────────────────────────────────────────
                Card(
                  elevation: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Attachments',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Existing images
                        if (_currentImageUrls.isNotEmpty) ...[
                          const Text('Existing Images:', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 280,
                            child: StatefulBuilder(
                              builder: (ctx, setStateDialog) {
                                final PageController pageController = PageController();
                                return Stack(
                                  children: [
                                    PageView.builder(
                                      controller: pageController,
                                      itemCount: _currentImageUrls.length,
                                      itemBuilder: (ctx, index) {
                                        final imageUrl = _currentImageUrls[index];
                                        final proxyUrl = GoogleDriveService.generateProxyUrl(
                                          imageUrl.contains('drive.google.com/uc?id=')
                                              ? Uri.parse(imageUrl).queryParameters['id'] ?? imageUrl
                                              : imageUrl,
                                        );
                                        final fileName = index < _currentFileNames.length
                                            ? _currentFileNames[index]
                                            : 'Image ${index + 1}';
                                        return Column(
                                          children: [
                                            Padding(
                                              padding: const EdgeInsets.all(8),
                                              child: Text(fileName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                            ),
                                            Expanded(
                                              child: InteractiveViewer(
                                                child: CachedNetworkImage(
                                                  imageUrl: proxyUrl,
                                                  httpHeaders: {'Authorization': 'Bearer ${SupabaseConfig.supabaseAnonKey}'},
                                                  fit: BoxFit.contain,
                                                  placeholder: (_, __) => const Center(child: CircularProgressIndicator()),
                                                  errorWidget: (_, __, ___) => const Center(child: Text('Failed to load image')),
                                                ),
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                    Positioned(
                                      top: 10,
                                      left: 10,
                                      child: IconButton(
                                        icon: const Icon(Icons.delete, color: Colors.red),
                                        onPressed: () async {
                                          final idx = pageController.page?.round() ?? 0;
                                          final fileName = idx < _currentFileNames.length
                                              ? _currentFileNames[idx]
                                              : 'Image ${idx + 1}';
                                          final confirm = await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text('Remove Attachment'),
                                              content: Text('Remove "$fileName"? This will delete it from Google Drive.'),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
                                              ],
                                            ),
                                          );
                                          if (confirm == true) {
                                            final url = _currentImageUrls[idx];
                                            setState(() {
                                              _currentImageUrls.removeAt(idx);
                                              if (idx < _currentFileNames.length) _currentFileNames.removeAt(idx);
                                            });
                                            setStateDialog(() {});
                                            final ok = await CachedDocumentService().deleteAttachmentFromDrive(url);
                                            if (!ok && mounted) {
                                              SnackbarUtils.showErrorSnackBar(context, 'Failed to delete from Google Drive');
                                            }
                                          }
                                        },
                                      ),
                                    ),
                                    if (_currentImageUrls.length > 1) ...[
                                      Positioned(
                                        left: 10,
                                        bottom: 10,
                                        child: IconButton(
                                          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                                          onPressed: () {
                                            if ((pageController.page ?? 0) > 0) {
                                              pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                                            }
                                          },
                                        ),
                                      ),
                                      Positioned(
                                        right: 10,
                                        bottom: 10,
                                        child: IconButton(
                                          icon: const Icon(Icons.arrow_forward_ios, color: Colors.white),
                                          onPressed: () {
                                            if ((pageController.page ?? 0) < _currentImageUrls.length - 1) {
                                              pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                                            }
                                          },
                                        ),
                                      ),
                                    ],
                                  ],
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Existing files
                        if (_currentFileUrls.isNotEmpty) ...[
                          const Text('Existing Documents:', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _currentFileUrls.length,
                            itemBuilder: (ctx, index) {
                              final nameIdx = _currentImageUrls.length + index;
                              final fileName = nameIdx < _currentFileNames.length
                                  ? _currentFileNames[nameIdx]
                                  : 'Document ${index + 1}';
                              return ListTile(
                                leading: const Icon(Icons.attach_file),
                                title: Text(fileName),
                                trailing: IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Remove Attachment'),
                                        content: Text('Remove "$fileName"? This will delete it from Google Drive.'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      final url = _currentFileUrls[index];
                                      setState(() {
                                        _currentFileUrls.removeAt(index);
                                        if (nameIdx < _currentFileNames.length) _currentFileNames.removeAt(nameIdx);
                                      });
                                      final ok = await CachedDocumentService().deleteAttachmentFromDrive(url);
                                      if (!ok && mounted) {
                                        SnackbarUtils.showErrorSnackBar(context, 'Failed to delete from Google Drive');
                                      }
                                    }
                                  },
                                ),
                                onTap: () async {
                                  final url = _currentFileUrls[index];
                                  final proxyUrl = RegExp(r'^[a-zA-Z0-9_-]{20,}$').hasMatch(url)
                                      ? GoogleDriveService.generateProxyUrl(url)
                                      : url;
                                  final uri = Uri.parse(proxyUrl);
                                  if (await canLaunchUrl(uri)) launchUrl(uri);
                                },
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Add new attachments
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: (_isPickingImage || _isSaving) ? null : _takePicture,
                                icon: const Icon(Icons.camera_alt),
                                label: const Text('Take Picture'),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: (_isPickingFile || _isSaving) ? null : () async {
                                  setState(() => _isPickingFile = true);
                                  final result = await FilePicker.platform.pickFiles(
                                    type: FileType.custom,
                                    allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'docx', 'pdf'],
                                    allowMultiple: true,
                                    withData: true,
                                  );
                                  if (result != null && result.files.isNotEmpty) {
                                    int imagesAdded = 0;
                                    int docsAdded = 0;
                                    for (final file in result.files) {
                                      String? filePath;
                                      int fileSize = 0;
                                      if (kIsWeb) {
                                        if (file.bytes != null) {
                                          fileSize = file.bytes!.length;
                                          filePath = 'web_file_${DateTime.now().millisecondsSinceEpoch}_${file.name}';
                                          _webFileBytes[filePath] = file.bytes!;
                                        }
                                      } else {
                                        filePath = file.path;
                                        if (filePath != null && filePath.isNotEmpty) {
                                          fileSize = File(filePath).lengthSync();
                                        }
                                      }
                                      if (filePath == null || filePath.isEmpty || fileSize == 0) continue;
                                      if (fileSize > 50 * 1024 * 1024) {
                                        SnackbarUtils.showErrorSnackBar(context, '${file.name} exceeds 50 MB limit');
                                        continue;
                                      }
                                      if (_isImage(file.name)) {
                                        if (_selectedImagePaths.length >= 20) {
                                          SnackbarUtils.showErrorSnackBar(context, 'Only 20 image files allowed');
                                          continue;
                                        }
                                        _selectedImagePaths.add(filePath);
                                        imagesAdded++;
                                        UploadQueueManager().addToQueue(
                                          documentCode: widget.document.code,
                                          filePath: filePath,
                                          isImage: true,
                                          localPath: filePath,
                                          bytes: kIsWeb && _webFileBytes.containsKey(filePath) ? _webFileBytes[filePath] : null,
                                        );
                                      } else if (_isDocument(file.name)) {
                                        _selectedDocumentPaths.add(filePath);
                                        docsAdded++;
                                        UploadQueueManager().addToQueue(
                                          documentCode: widget.document.code,
                                          filePath: filePath,
                                          isImage: false,
                                          localPath: filePath,
                                          bytes: kIsWeb && _webFileBytes.containsKey(filePath) ? _webFileBytes[filePath] : null,
                                        );
                                      }
                                    }
                                    setState(() => _isPickingFile = false);
                                    if (imagesAdded > 0) SnackbarUtils.showSuccessSnackBar(context, '$imagesAdded image(s) added');
                                    if (docsAdded > 0) SnackbarUtils.showSuccessSnackBar(context, '$docsAdded document(s) added');
                                  } else {
                                    setState(() => _isPickingFile = false);
                                  }
                                },
                                icon: const Icon(Icons.attach_file),
                                label: const Text('Pick Files'),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                ),
                              ),
                            ),
                          ],
                        ),

                        if (_isPickingImage) ...[
                          const SizedBox(height: 10),
                          const Row(
                            children: [
                              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                              SizedBox(width: 10),
                              Text('Processing scan...', style: TextStyle(color: Colors.blue)),
                            ],
                          ),
                        ],
                        if (_isPickingFile) ...[
                          const SizedBox(height: 10),
                          const Row(
                            children: [
                              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                              SizedBox(width: 10),
                              Text('Selecting files...', style: TextStyle(color: Colors.blue)),
                            ],
                          ),
                        ],

                        // New files summary
                        if (_selectedImagePaths.isNotEmpty || _selectedDocumentPaths.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.green.withOpacity(0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_selectedImagePaths.length + _selectedDocumentPaths.length} new file(s) queued',
                                  style: TextStyle(fontWeight: FontWeight.w600, color: Colors.green.shade700, fontSize: 13),
                                ),
                                if (_selectedDocumentPaths.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: _selectedDocumentPaths.map((path) {
                                      final name = path.split('\\').last.split('/').last;
                                      return Chip(
                                        label: Text(name.length > 20 ? '${name.substring(0, 17)}...' : name, style: const TextStyle(fontSize: 12)),
                                        onDeleted: _isSaving ? null : () {
                                          UploadQueueManager().removeFromQueue(widget.document.code, path);
                                          setState(() => _selectedDocumentPaths.remove(path));
                                        },
                                      );
                                    }).toList(),
                                  ),
                                ],
                                if (_selectedImagePaths.isNotEmpty) ...[
                                  if (_selectedImagePaths.where(_isImage).length > 10)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Row(
                                        children: [
                                          Icon(Icons.info_outline, size: 13, color: Colors.amber.shade700),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              'You have ${_selectedImagePaths.where(_isImage).length} images — saving as PDF keeps them in one file.',
                                              style: TextStyle(fontSize: 11, color: Colors.amber.shade800),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  const SizedBox(height: 4),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: (_isSaving || _isMergingPdf) ? null : _mergeImagesToPdf,
                                      icon: _isMergingPdf
                                          ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                                          : const Icon(Icons.picture_as_pdf_outlined, size: 14),
                                      label: const Text("Save as PDF instead", style: TextStyle(fontSize: 13)),
                                      style: TextButton.styleFrom(
                                        minimumSize: Size.zero,
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 12),

                        // Remarks
                        TextField(
                          controller: _remarksController,
                          enabled: !_isSaving,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: 'Remarks',
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Save button ──────────────────────────────────────────
                ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 4,
                    backgroundColor: const Color(0xFF4EC377),
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                  ),
                  child: _isSaving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Save Changes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),

                if (_isSaving && _totalUploads > 0) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: _totalUploads > 0 ? _completedUploads / _totalUploads : null),
                  const SizedBox(height: 4),
                  Text(_uploadStatus, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
