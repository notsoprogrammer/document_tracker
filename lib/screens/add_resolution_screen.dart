import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show TextInputFormatter, TextEditingValue, TextSelection;
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models/document.dart';
import '../services/cached_document_service.dart';
import '../services/document_scanner_service.dart';
import '../services/mlkit_scanner_service.dart';
import '../services/pdf_export_service.dart';
import '../services/upload_queue_manager.dart';
import '../services/auth_service.dart';
import '../utils/snackbar_utils.dart';
import '../utils/date_time_utils.dart';
import '../widgets/cabinet_location_picker.dart';

class AddResolutionScreen extends StatefulWidget {
  const AddResolutionScreen({super.key});

  @override
  State<AddResolutionScreen> createState() => _AddResolutionScreenState();
}

class _AddResolutionScreenState extends State<AddResolutionScreen> {
  final ImagePicker _picker = ImagePicker();
  final codeController = TextEditingController();
  final titleController = TextEditingController();
  final descriptionController = TextEditingController();
  final referenceLinkController = TextEditingController();
  final remarksController = TextEditingController();
  final personController = TextEditingController();
  final heldByController = TextEditingController();
  final heldByFolderController = TextEditingController();
  final folderTitleController = TextEditingController();

  DateTime? selectedDate;
  String _typeValue = '';
  List<String> _resolutionTypes = [];
  // Reference to the controller provided by Autocomplete's fieldViewBuilder
  TextEditingController? _typeFieldController;

  List<String> _selectedImagePaths = [];
  List<String> _selectedDocumentPaths = [];
  List<List<int>?> _selectedImageBytes = [];
  final Map<String, List<int>> _webFileBytes = {};
  bool _isPickingImage = false;
  bool _isPickingFile = false;
  bool _isMergingPdf = false;

  String? _selectedCabinet;
  bool _showValidationErrors = false;
  bool _isSaving = false;

  bool _isImage(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'heic'].contains(ext);
  }

  bool _isDocument(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return ['pdf', 'jpg', 'jpeg', 'png'].contains(ext);
  }

  @override
  void initState() {
    super.initState();
    codeController.text = '-';
    UploadQueueManager().addListener(_onUploadStatusChanged);
    _loadUsername();
    _loadResolutionTypes();
  }

  Future<void> _loadResolutionTypes() async {
    final docs = await CachedDocumentService().fetchDocuments();
    final types = docs
        .where((d) => d.mode == 'Resolutions' && d.category != null && d.category!.isNotEmpty)
        .map((d) => d.category!)
        .toSet()
        .toList()
      ..sort();
    if (mounted) setState(() => _resolutionTypes = types);
  }

  bool _saved = false;

  @override
  void dispose() {
    UploadQueueManager().removeListener(_onUploadStatusChanged);
    if (!_saved) UploadQueueManager().removeAllForDocument(codeController.text);
    codeController.dispose();
    titleController.dispose();
    descriptionController.dispose();
    referenceLinkController.dispose();
    remarksController.dispose();
    personController.dispose();
    heldByController.dispose();
    heldByFolderController.dispose();
    folderTitleController.dispose();
    super.dispose();
  }

  Future<void> _loadUsername() async {
    final username = await AuthService.getUsername();
    if (username != null && username.isNotEmpty && mounted) {
      setState(() => personController.text = username);
    }
  }

  void _onUploadStatusChanged() {}

  String _generateCode() {
    final title = titleController.text.trim();
    if (title.isEmpty) return '-';
    return 'RES-${title.replaceAll(RegExp(r'\s+'), '-')}';
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != selectedDate) {
      setState(() => selectedDate = picked);
    }
  }

  Future<bool> _onWillPop() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Exit'),
        content: const Text('Do you want to exit?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Yes')),
        ],
      ),
    );
    return result ?? false;
  }

  Future<ImageSource?> _chooseWebScanSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => SafeArea(
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
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
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
      SnackbarUtils.showWarningSnackBar(context, 'Maximum 20 images allowed');
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
    final scannedBytes = kIsWeb ? rawBytes : (await DocumentScannerService.processImage(rawBytes) ?? rawBytes);
    if (!mounted) return;
    if (kIsWeb) {
      final fileName = 'scanned_${DateTime.now().millisecondsSinceEpoch}.jpg';
      setState(() {
        _selectedImagePaths.add(fileName);
        _selectedImageBytes.add(scannedBytes);
        _isPickingImage = false;
      });
      UploadQueueManager().addWebCameraImageToQueue(
        documentCode: codeController.text, filePath: fileName, bytes: scannedBytes);
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
        documentCode: codeController.text, filePath: tempFile.path, isImage: true, localPath: tempFile.path);
    }
  }

  Future<void> _scanWithMlKit() async {
    final int remaining = 20 - _selectedImagePaths.where(_isImage).length;
    if (remaining <= 0) {
      SnackbarUtils.showWarningSnackBar(context, 'Maximum 20 images allowed');
      return;
    }
    setState(() => _isPickingImage = true);
    ScannerOutput? output;
    try {
      output = await MlKitScannerService.scanDocument(maxPages: remaining, format: ScanOutputFormat.image);
    } catch (_) {
      output = null;
    }
    if (!mounted) return;
    if (output == null || output.wasCancelled) {
      setState(() => _isPickingImage = false);
      return;
    }
    try {
      final tempDir = await getTemporaryDirectory();
      for (var i = 0; i < output.images.length; i++) {
        final tempFile = File('${tempDir.path}/mlkit_${DateTime.now().millisecondsSinceEpoch}_$i.jpg');
        await tempFile.writeAsBytes(output.images[i]);
        if (!mounted) return;
        setState(() {
          _selectedImagePaths.add(tempFile.path);
          _selectedImageBytes.add(null);
        });
        UploadQueueManager().addToQueue(
          documentCode: codeController.text, filePath: tempFile.path, isImage: true, localPath: tempFile.path);
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
      if (imageBytesList.isEmpty) {
        if (mounted) SnackbarUtils.showErrorSnackBar(context, 'No image data available to convert');
        return;
      }
      final pdfBytes = await PdfExportService.buildPdfFromLocalImages(imageBytesList);
      for (final path in imageOnlyPaths) {
        UploadQueueManager().removeFromQueue(codeController.text, path);
      }
      if (kIsWeb) {
        final pdfFileName = 'merged_${DateTime.now().millisecondsSinceEpoch}.pdf';
        if (!mounted) return;
        setState(() {
          _selectedImagePaths.removeWhere(_isImage);
          _selectedImageBytes.clear();
          _selectedDocumentPaths.add(pdfFileName);
        });
        _webFileBytes[pdfFileName] = pdfBytes;
        UploadQueueManager().addToQueue(
          documentCode: codeController.text, filePath: pdfFileName,
          isImage: false, localPath: pdfFileName, bytes: pdfBytes);
      } else {
        final tempDir = await getTemporaryDirectory();
        final pdfFile = File('${tempDir.path}/merged_${DateTime.now().millisecondsSinceEpoch}.pdf');
        await pdfFile.writeAsBytes(pdfBytes);
        if (!mounted) return;
        setState(() {
          _selectedImagePaths.removeWhere(_isImage);
          _selectedImageBytes.clear();
          _selectedDocumentPaths.add(pdfFile.path);
        });
        UploadQueueManager().addToQueue(
          documentCode: codeController.text, filePath: pdfFile.path,
          isImage: false, localPath: pdfFile.path);
      }
      if (mounted) SnackbarUtils.showSuccessSnackBar(context, '${imageOnlyPaths.length} image(s) merged into PDF');
    } catch (e) {
      if (mounted) SnackbarUtils.showErrorSnackBar(context, 'Failed to merge PDF: $e');
    } finally {
      if (mounted) setState(() => _isMergingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Add Resolution'),
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFCE93D8), Color(0xFF7B1FA2)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          foregroundColor: Colors.white,
        ),
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Basic Information
                Card(
                  elevation: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
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
                        Autocomplete<String>(
                          optionsBuilder: (TextEditingValue value) {
                            final query = value.text.toLowerCase();
                            if (query.isEmpty) return _resolutionTypes;
                            return _resolutionTypes.where(
                              (t) => t.toLowerCase().contains(query));
                          },
                          onSelected: (String selection) {
                            setState(() => _typeValue = selection);
                          },
                          fieldViewBuilder: (context, controller, focusNode, _) {
                            _typeFieldController = controller;
                            return TextField(
                              controller: controller,
                              focusNode: focusNode,
                              enabled: !_isSaving,
                              onChanged: (value) => setState(() => _typeValue = value),
                              decoration: InputDecoration(
                                labelText: 'Resolution Type',
                                hintText: 'Type or select existing…',
                                border: const OutlineInputBorder(),
                                filled: true,
                                fillColor: Theme.of(context).colorScheme.surface,
                                errorText: _showValidationErrors && _typeValue.trim().isEmpty
                                    ? 'Resolution type is required'
                                    : null,
                              ),
                            );
                          },
                          optionsViewBuilder: (context, onSelected, options) => Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 4,
                              borderRadius: BorderRadius.circular(8),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 200, maxWidth: 320),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: options.length,
                                  itemBuilder: (context, index) {
                                    final option = options.elementAt(index);
                                    return ListTile(
                                      dense: true,
                                      title: Text(option),
                                      onTap: () => onSelected(option),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: titleController,
                          builder: (context, value, _) {
                            final wordCount = value.text.trim().isEmpty
                                ? 0
                                : value.text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
                            return TextField(
                              controller: titleController,
                              enabled: !_isSaving,
                              inputFormatters: [const _WordLimitFormatter(6)],
                              onChanged: (text) {
                                final oldCode = codeController.text;
                                final newCode = _generateCode();
                                if (oldCode != newCode) {
                                  setState(() => codeController.text = newCode);
                                  if (newCode != '-') {
                                    UploadQueueManager().updateDocumentCode(oldCode, newCode);
                                  }
                                }
                              },
                              decoration: InputDecoration(
                                labelText: 'Resolution No. / Title',
                                hintText: 'e.g. Resolution No. 001-2024',
                                border: const OutlineInputBorder(),
                                filled: true,
                                fillColor: Theme.of(context).colorScheme.surface,
                                helperText: '$wordCount/6 words',
                                errorText: _showValidationErrors && value.text.trim().isEmpty
                                    ? 'Resolution No. / Title is required'
                                    : null,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: descriptionController,
                          enabled: !_isSaving,
                          decoration: InputDecoration(
                            labelText: 'Subject / Description',
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                            errorText: _showValidationErrors && descriptionController.text.trim().isEmpty
                                ? 'Description is required'
                                : null,
                          ),
                          maxLines: 3,
                        ),
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: _isSaving ? null : () => _selectDate(context),
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Date',
                              border: const OutlineInputBorder(),
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.surface,
                              errorText: _showValidationErrors && selectedDate == null
                                  ? 'Date is required'
                                  : null,
                              suffixIcon: const Icon(Icons.calendar_today),
                            ),
                            child: Text(
                              selectedDate != null
                                  ? '${selectedDate!.month}/${selectedDate!.day}/${selectedDate!.year}'
                                  : 'Resolution Date',
                              style: TextStyle(
                                color: selectedDate != null
                                    ? Theme.of(context).colorScheme.onSurface
                                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: codeController,
                          readOnly: true,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                          decoration: InputDecoration(
                            labelText: 'Document Code',
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Attachments
                Card(
                  elevation: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
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
                        const SizedBox(height: 16),
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
                                    allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'pdf'],
                                    allowMultiple: true,
                                    withData: true,
                                  );
                                  if (result != null && result.files.isNotEmpty) {
                                    int imagesAdded = 0, docsAdded = 0;
                                    for (final file in result.files) {
                                      String? filePath;
                                      if (kIsWeb) {
                                        if (file.bytes != null) {
                                          filePath = 'web_file_${DateTime.now().millisecondsSinceEpoch}_${file.name}';
                                          _webFileBytes[filePath] = file.bytes!;
                                        }
                                      } else {
                                        filePath = file.path;
                                      }
                                      if (filePath != null && filePath.isNotEmpty) {
                                        if (_isImage(file.name)) {
                                          if (_selectedImagePaths.length >= 20) {
                                            SnackbarUtils.showErrorSnackBar(context, 'Only 20 image files allowed');
                                            continue;
                                          }
                                          _selectedImagePaths.add(filePath);
                                          imagesAdded++;
                                          UploadQueueManager().addToQueue(
                                            documentCode: codeController.text,
                                            filePath: filePath,
                                            isImage: true,
                                            localPath: filePath,
                                            bytes: kIsWeb ? _webFileBytes[filePath] : null,
                                          );
                                        } else if (_isDocument(file.name)) {
                                          _selectedDocumentPaths.add(filePath);
                                          docsAdded++;
                                          UploadQueueManager().addToQueue(
                                            documentCode: codeController.text,
                                            filePath: filePath,
                                            isImage: false,
                                            localPath: filePath,
                                            bytes: kIsWeb ? _webFileBytes[filePath] : null,
                                          );
                                        }
                                      }
                                    }
                                    if (mounted) {
                                      setState(() => _isPickingFile = false);
                                      if (imagesAdded > 0) SnackbarUtils.showSuccessSnackBar(context, '$imagesAdded image(s) added');
                                      if (docsAdded > 0) SnackbarUtils.showSuccessSnackBar(context, '$docsAdded document(s) added');
                                    }
                                  } else {
                                    if (mounted) setState(() => _isPickingFile = false);
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
                        if (_isPickingImage || _isPickingFile) ...[
                          const SizedBox(height: 12),
                          const Row(
                            children: [
                              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2)),
                              SizedBox(width: 12),
                              Text('Processing...'),
                            ],
                          ),
                        ],
                        if (_selectedImagePaths.isNotEmpty || _selectedDocumentPaths.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.cloud_upload_outlined, color: Colors.green.shade600, size: 18),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${_selectedImagePaths.length + _selectedDocumentPaths.length} file(s) queued for upload',
                                      style: TextStyle(fontWeight: FontWeight.w600, color: Colors.green.shade700, fontSize: 13),
                                    ),
                                  ],
                                ),
                                if (_selectedImagePaths.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text('${_selectedImagePaths.length} image(s)', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                                  if (_selectedImagePaths.where(_isImage).length > 10) ...[
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.amber.shade300),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.lightbulb_outline, size: 15, color: Colors.amber.shade700),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              'You have ${_selectedImagePaths.where(_isImage).length} images — saving as PDF keeps them in one file.',
                                              style: TextStyle(fontSize: 11, color: Colors.amber.shade800),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 6),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: (_isSaving || _isMergingPdf) ? null : _mergeImagesToPdf,
                                      icon: _isMergingPdf
                                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                          : const Icon(Icons.picture_as_pdf_outlined, size: 16),
                                      label: Text(_isMergingPdf ? 'Converting...' : 'Save as PDF instead'),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                        foregroundColor: Colors.deepOrange,
                                        side: BorderSide(color: Colors.deepOrange.shade300),
                                        textStyle: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  ),
                                ],
                                if (_selectedDocumentPaths.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: _selectedDocumentPaths.map((path) {
                                      final fileName = path.split('\\').last.split('/').last;
                                      final isPdf = fileName.toLowerCase().endsWith('.pdf');
                                      return Chip(
                                        avatar: Icon(
                                          isPdf ? Icons.picture_as_pdf : Icons.description,
                                          size: 16,
                                          color: isPdf ? Colors.red.shade400 : Colors.blue.shade400,
                                        ),
                                        label: Text(
                                          fileName.length > 20 ? '${fileName.substring(0, 17)}...' : fileName,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        onDeleted: _isSaving ? null : () {
                                          UploadQueueManager().removeFromQueue(codeController.text, path);
                                          setState(() => _selectedDocumentPaths.remove(path));
                                        },
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextField(
                          controller: referenceLinkController,
                          enabled: !_isSaving,
                          decoration: InputDecoration(
                            labelText: 'Drive Link (optional)',
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                          ),
                        ),
                        const SizedBox(height: 12),
                        CabinetLocationPicker(
                          initialValue: _selectedCabinet,
                          enabled: !_isSaving,
                          onChanged: (v) => setState(() => _selectedCabinet = v),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: folderTitleController,
                          enabled: !_isSaving,
                          decoration: InputDecoration(
                            labelText: 'Folder / Details (optional)',
                            hintText: 'e.g. Blue folder, Top drawer, Binder 2024',
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                            prefixIcon: const Icon(Icons.folder_outlined, size: 20),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: heldByController,
                          enabled: !_isSaving,
                          decoration: InputDecoration(
                            labelText: 'Held by (optional)',
                            hintText: 'Person currently holding this document',
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                            prefixIcon: const Icon(Icons.person_pin_outlined, size: 20),
                          ),
                          textCapitalization: TextCapitalization.words,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: heldByFolderController,
                          enabled: !_isSaving,
                          decoration: InputDecoration(
                            labelText: "Holder's Folder / Details (optional)",
                            hintText: "e.g. Maria's blue binder, On desk, Drawer 2",
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                            prefixIcon: const Icon(Icons.folder_outlined, size: 20),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: remarksController,
                          enabled: !_isSaving,
                          decoration: InputDecoration(
                            labelText: 'Remarks',
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                          ),
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _isSaving
                      ? null
                      : () async {
                          final typeText = (_typeFieldController?.text ?? _typeValue).trim();
                          setState(() {
                            _typeValue = typeText;
                            _showValidationErrors = true;
                          });
                          if (typeText.isEmpty || titleController.text.trim().isEmpty || selectedDate == null || descriptionController.text.trim().isEmpty || personController.text.trim().isEmpty) return;

                          final code = codeController.text;
                          final description = descriptionController.text.trim();
                          final resolutionTitle = titleController.text.trim();
                          final dateStr = '${selectedDate!.month}/${selectedDate!.day}/${selectedDate!.year}';

                          final doc = Document(
                            code: code,
                            title: resolutionTitle.isNotEmpty ? resolutionTitle : description,
                            description: description,
                            referenceLink: referenceLinkController.text.trim().isNotEmpty
                                ? referenceLinkController.text.trim()
                                : null,
                            type: typeText,
                            fromOrTo: dateStr,
                            mode: 'Resolutions',
                            assignedTo: personController.text,
                            filePath: null,
                            remarks: remarksController.text,
                            person: personController.text,
                            incoming: false,
                            cabinetLocation: _selectedCabinet,
                            folderTitle: folderTitleController.text.trim().isNotEmpty ? folderTitleController.text.trim() : null,
                            heldBy: heldByController.text.trim().isNotEmpty ? heldByController.text.trim() : null,
                            heldByFolder: heldByFolderController.text.trim().isNotEmpty ? heldByFolderController.text.trim() : null,
                            status: 'Completed',
                            imageUrls: [],
                            fileUrls: [],
                            localImagePaths: _selectedImagePaths,
                            localFilePaths: _selectedDocumentPaths,
                            category: typeText,
                            createdAt: getPhilippineTime(),
                          );

                          final navigator = Navigator.of(context);
                          setState(() => _isSaving = true);
                          try {
                            await CachedDocumentService().createDocument(doc);
                            CachedDocumentService().processPendingUploads();
                            _saved = true;
                            navigator.pop();
                          } catch (e) {
                            if (mounted) {
                              SnackbarUtils.showErrorSnackBar(context, 'Failed to save resolution: $e');
                              setState(() => _isSaving = false);
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 4,
                    backgroundColor: const Color(0xFF9C27B0),
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  child: _isSaving
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                            SizedBox(width: 12),
                            Text('Saving...'),
                          ],
                        )
                      : const Text('Save Resolution'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WordLimitFormatter extends TextInputFormatter {
  final int maxWords;
  const _WordLimitFormatter(this.maxWords);

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final words = newValue.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length <= maxWords) return newValue;
    final truncated = words.take(maxWords).join(' ');
    return newValue.copyWith(
      text: truncated,
      selection: TextSelection.collapsed(offset: truncated.length),
    );
  }
}
