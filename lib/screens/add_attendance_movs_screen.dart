import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/document.dart';
import '../services/cached_document_service.dart';
import '../services/document_scanner_service.dart';
import '../services/google_drive_service.dart';
import '../services/mlkit_scanner_service.dart';
import '../services/pdf_export_service.dart';
import '../services/upload_queue_manager.dart';
import '../services/auth_service.dart';
import '../utils/snackbar_utils.dart';
import '../utils/date_time_utils.dart';
import '../constants/document_types.dart';
import '../widgets/cabinet_location_picker.dart';
class AddAttendanceMovScreen extends StatefulWidget {
  const AddAttendanceMovScreen({super.key});

  @override
  State<AddAttendanceMovScreen> createState() => _AddAttendanceMovScreenState();
}

class _AddAttendanceMovScreenState extends State<AddAttendanceMovScreen> {
  final ImagePicker _picker = ImagePicker();
  final GoogleDriveService _driveService = GoogleDriveService();
  final codeController = TextEditingController();
  String? selectedType;
  DateTime? selectedDate;
  final descriptionController = TextEditingController();
  final referenceLinkController = TextEditingController();
  final remarksController = TextEditingController();
  final personController = TextEditingController();
  final heldByController = TextEditingController();
  final folderTitleController = TextEditingController();

  // File handling
  List<String> _selectedImagePaths = [];
  List<String> _selectedDocumentPaths = [];
  List<List<int>?> _selectedImageBytes = []; // For web camera images
  final Map<String, List<int>> _webFileBytes = {}; // For web file picker files
  List<String> _uploadedImageUrls = [];
  List<String> _uploadedDocumentUrls = [];
  bool _isUploadingImages = false;
  bool _isPickingImage = false;
  bool _isPickingFile = false;
  bool _isMergingPdf = false;
  String _uploadStatus = '';
  int _totalUploads = 0;
  int _completedUploads = 0;

  bool _isImage(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp','heic'].contains(ext);
  }

  bool _isDocument(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return ['pdf', 'jpg', 'jpeg', 'png'].contains(ext);
  }

  // Validation flags
  String? _selectedCabinet;
  bool _showValidationErrors = false;
  bool _isSaving = false;

  List<String> get allOptions => [...coreFunctions, ...strategicFunctions, ...supportFunctions];

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

  @override
  void initState() {
    super.initState();
    selectedDate = DateTime.now().toUtc().add(const Duration(hours: 8));
    codeController.text = _generateCode();
    _setupUploadListener();
    _loadUsername();
  }

  Future<void> _loadUsername() async {
    final username = await AuthService.getUsername();
    if (username != null && username.isNotEmpty) {
      setState(() {
        personController.text = username;
      });
    }
  }

  bool _saved = false;

  @override
  void dispose() {
    UploadQueueManager().removeListener(_onUploadStatusChanged);
    if (!_saved) UploadQueueManager().removeAllForDocument(codeController.text);
    super.dispose();
  }

  void _setupUploadListener() {
    final queueManager = UploadQueueManager();
    queueManager.addListener(_onUploadStatusChanged);
  }

  void _onUploadStatusChanged() {
    if (!mounted) return;

    final queueManager = UploadQueueManager();
    final pendingUploads = queueManager.getPendingUploads(codeController.text);
    final uploadingUploads = queueManager.getAllItems().where((item) =>
      item['documentCode'] == codeController.text && item['status'] == 'uploading'
    ).toList();
    final completedUploads = queueManager.getAllItems().where((item) =>
      item['documentCode'] == codeController.text && item['status'] == 'completed'
    ).toList();

    setState(() {
      _totalUploads = _selectedImagePaths.length + _selectedDocumentPaths.length;
      _completedUploads = completedUploads.length;
      _uploadStatus = uploadingUploads.isNotEmpty
        ? 'Uploading ${uploadingUploads.length} file(s)...'
        : pendingUploads.isEmpty
          ? 'All uploads completed'
          : 'Preparing uploads...';
    });

  }

  Future<ImageSource?> _chooseWebScanSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
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
                subtitle: const Text('Scan with device camera'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery'),
                subtitle: const Text('Choose from photo library'),
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
    // Web / iOS: let user choose Camera or Gallery before capturing.
    final ImageSource? source = await _chooseWebScanSource();
    if (source == null || !mounted) return;
    final int count = _selectedImagePaths.where(_isImage).length;
    if (count >= 20) {
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
        documentCode: codeController.text,
        filePath: fileName,
        bytes: scannedBytes,
      );
    } else {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tempDir.path}/scanned_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(scannedBytes);
      if (!mounted) return;
      setState(() {
        _selectedImagePaths.add(tempFile.path);
        _selectedImageBytes.add(null);
        _isPickingImage = false;
      });
      UploadQueueManager().addToQueue(
        documentCode: codeController.text,
        filePath: tempFile.path,
        isImage: true,
        localPath: tempFile.path,
      );
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
    if (output == null) {
      setState(() => _isPickingImage = false);
      if (_selectedImagePaths.where(_isImage).length >= 20) {
        SnackbarUtils.showWarningSnackBar(context, 'Maximum 20 images allowed');
        return;
      }
      setState(() => _isPickingImage = true);
      final XFile? image = await _picker.pickImage(source: ImageSource.camera);
      if (image == null) {
        if (!mounted) return;
        setState(() => _isPickingImage = false);
        SnackbarUtils.showErrorSnackBar(context, 'No image captured');
        return;
      }
      final rawBytes = await image.readAsBytes();
      final scannedBytes = kIsWeb ? rawBytes : (await DocumentScannerService.processImage(rawBytes) ?? rawBytes);
      if (!mounted) return;
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/scanned_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(scannedBytes);
      if (!mounted) return;
      setState(() { _selectedImagePaths.add(tempFile.path); _selectedImageBytes.add(null); _isPickingImage = false; });
      UploadQueueManager().addToQueue(documentCode: codeController.text, filePath: tempFile.path, isImage: true, localPath: tempFile.path);
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
        UploadQueueManager().addToQueue(documentCode: codeController.text, filePath: tempFile.path, isImage: true, localPath: tempFile.path);
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
      for (final path in imageOnlyPaths) { UploadQueueManager().removeFromQueue(codeController.text, path); }
      if (kIsWeb) {
        final pdfFileName = 'merged_${DateTime.now().millisecondsSinceEpoch}.pdf';
        if (!mounted) return;
        setState(() { _selectedImagePaths.removeWhere(_isImage); _selectedImageBytes.clear(); _selectedDocumentPaths.add(pdfFileName); });
        _webFileBytes[pdfFileName] = pdfBytes;
        UploadQueueManager().addToQueue(documentCode: codeController.text, filePath: pdfFileName, isImage: false, localPath: pdfFileName, bytes: pdfBytes);
      } else {
        final pdfFile = File('${(await getTemporaryDirectory()).path}/merged_${DateTime.now().millisecondsSinceEpoch}.pdf');
        await pdfFile.writeAsBytes(pdfBytes);
        if (!mounted) return;
        setState(() { _selectedImagePaths.removeWhere(_isImage); _selectedImageBytes.clear(); _selectedDocumentPaths.add(pdfFile.path); });
        UploadQueueManager().addToQueue(documentCode: codeController.text, filePath: pdfFile.path, isImage: false, localPath: pdfFile.path);
      }
      if (mounted) SnackbarUtils.showSuccessSnackBar(context, '${imageOnlyPaths.length} image(s) merged into PDF');
    } catch (e) {
      if (mounted) SnackbarUtils.showErrorSnackBar(context, 'Failed to merge PDF: $e');
    } finally {
      if (mounted) setState(() => _isMergingPdf = false);
    }
  }

  Future<bool> _onWillPop() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Exit'),
        content: const Text('Do you want to exit?'),
        actions: [
          TextButton(

            onPressed: () => Navigator.of(context).pop(false), // Continue Adding
            child: const Text('No'),
          ),
          TextButton(

            onPressed: () => Navigator.of(context).pop(true), // Cancel
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  String _generateCode() {
    final nowUtc = DateTime.now().toUtc();
    final phTime = nowUtc.add(const Duration(hours: 8)); // force UTC+8

    // For FL/FR, use activity date for the date portion so the code reflects when the event happened
    final bool isFlagCeremony = selectedType == 'Flag Raising' || selectedType == 'Flag Lowering';
    final dateSource = (isFlagCeremony && selectedDate != null) ? selectedDate! : phTime;

    final year = dateSource.year;
    final month = dateSource.month.toString().padLeft(2, '0');
    final day = dateSource.day.toString().padLeft(2, '0');
    final hour = phTime.hour.toString().padLeft(2, '0');
    final minute = phTime.minute.toString().padLeft(2, '0');
    final second = phTime.second.toString().padLeft(2, '0');

    String prefix;
    if (coreFunctions.contains(selectedType)) {
      prefix = 'CF';
    } else if (strategicFunctions.contains(selectedType)) {
      prefix = 'StF';
    } else if (supportFunctions.contains(selectedType)) {
      prefix = 'SuF';
    } else {
      prefix = 'DOC';
    }

    String typeCode = typeMapping[selectedType] ?? 'DOC';

    return '$prefix-$typeCode-$month$day$year-$hour$minute$second';
  }

  void _viewSelectedFiles(BuildContext context) async {
    final imageFiles = _selectedImagePaths.where((path) {
      final parts = path.split('.');
      if (parts.length <= 1) return false;
      final extension = parts.last.toLowerCase();
      return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp','heic'].contains(extension);
    }).toList();

    final otherFiles = _selectedImagePaths.where((path) {
      final parts = path.split('.');
      if (parts.length <= 1) return true;
      final extension = parts.last.toLowerCase();
      return !['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp','heic'].contains(extension);
    }).toList();

    if (imageFiles.isNotEmpty) {
      showDialog(
        context: context,
        builder: (_) => Dialog(
          insetPadding: EdgeInsets.all(16),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            height: MediaQuery.of(context).size.height * 0.7,
            child: StatefulBuilder(
              builder: (context, setStateDialog) {
                final PageController _pageController = PageController();

                return Column(
                  children: [
                    // Top row with Delete (left) and Close (right)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            if (imageFiles.isNotEmpty) {
                              final currentIndex = _pageController.page?.round() ?? 0;
                              setState(() {
                                // Remove from upload queue
                                final queueManager = UploadQueueManager();
                                queueManager.removeFromQueue(codeController.text, imageFiles[currentIndex]);
                                _selectedImagePaths.remove(imageFiles[currentIndex]);
                                _webFileBytes.remove(imageFiles[currentIndex]);
                              });
                              setStateDialog(() {
                                imageFiles.removeAt(currentIndex);
                              });
                              if (imageFiles.isEmpty) {
                                Navigator.pop(context);
                              }
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: imageFiles.length,
                        itemBuilder: (context, index) {
                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              InteractiveViewer(
                                child: () {
                                  final path = imageFiles[index];
                                  final webBytes = _webFileBytes[path];
                                  if (kIsWeb && webBytes != null) {
                                    return Image.memory(
                                      Uint8List.fromList(webBytes),
                                      fit: BoxFit.contain,
                                      errorBuilder: (context, error, stackTrace) {
                                        return const Center(child: Text('Failed to load image'));
                                      },
                                    );
                                  } else if (kIsWeb) {
                                    return const Center(child: Text('Preview unavailable'));
                                  } else {
                                    return Image.file(
                                      File(path),
                                      fit: BoxFit.contain,
                                      errorBuilder: (context, error, stackTrace) {
                                        return const Center(child: Text('Failed to load image'));
                                      },
                                    );
                                  }
                                }(),
                              ),
                              // Left arrow
                              if (index > 0)
                                Positioned(
                                  left: 10,
                                  child: IconButton(
                                    icon: const Icon(Icons.arrow_back_ios, color: Colors.black54),
                                    onPressed: () {
                                      _pageController.previousPage(
                                        duration: const Duration(milliseconds: 300),
                                        curve: Curves.easeInOut,
                                      );
                                    },
                                  ),
                                ),
                              // Right arrow
                              if (index < imageFiles.length - 1)
                                Positioned(
                                  right: 10,
                                  child: IconButton(
                                    icon: const Icon(Icons.arrow_forward_ios, color: Colors.black54),
                                    onPressed: () {
                                      _pageController.nextPage(
                                        duration: const Duration(milliseconds: 300),
                                        curve: Curves.easeInOut,
                                      );
                                    },
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
    }

    for (final filePath in otherFiles) {
      final normalizedPath = filePath.replaceAll('\\', '/');
      final uri = Uri.file(normalizedPath);
      if (await launchUrl(uri)) {
        // Successfully launched
      } else {
        SnackbarUtils.showErrorSnackBar(context, 'Could not open file: ${filePath.split('\\').last.split('/').last}');
      }
    }

    if (imageFiles.isEmpty && otherFiles.isEmpty) {
      SnackbarUtils.showErrorSnackBar(context, 'No files selected to view');
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
        codeController.text = _generateCode();
      });
    }
  }

  void _onTypeChanged(String? value) {
    setState(() {
      selectedType = value;
      codeController.text = _generateCode();
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Add Certs/MOVs"),
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFB3E5FC), Color(0xFF81D4FA), Color.fromARGB(255, 98, 195, 240)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          foregroundColor: const Color.fromARGB(255, 28, 28, 28),
        ),
        body: Container(
        decoration: BoxDecoration(
        ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  elevation: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Basic Information",
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),

                        const SizedBox(height: 12),
                        Autocomplete<String>(
                          optionsBuilder: (TextEditingValue textEditingValue) {
                            if (textEditingValue.text.isEmpty) {
                              return allOptions;
                            }
                            return allOptions.where((option) =>
                              option.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                          },
                          onSelected: (String selection) {
                            setState(() {
                              selectedType = selection;
                              codeController.text = _generateCode();
                            });
                          },
                          fieldViewBuilder: (BuildContext context, TextEditingController textEditingController, FocusNode focusNode, VoidCallback onFieldSubmitted) {
                            return TextField(
                              controller: textEditingController,
                              focusNode: focusNode,
                              enabled: !_isSaving,
                              decoration: InputDecoration(
                                labelText: "Type",
                                border: OutlineInputBorder(),
                                filled: true,
                                fillColor: Theme.of(context).colorScheme.surface,
                                errorText: _showValidationErrors && selectedType == null ? "Select only from the dropdown" : null,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: descriptionController,
                          enabled: !_isSaving,
                          decoration: InputDecoration(
                            labelText: "Description${selectedType == 'Others' ? ' *' : ''}",
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                            errorText: _showValidationErrors && selectedType == 'Others' && descriptionController.text.trim().isEmpty ? "Description is required for Others" : null,
                          ),
                          maxLines: 3,
                        ),
                        const SizedBox(height: 12),
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: _isSaving ? null : () => _selectDate(context),
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: "Date",
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.surface,
                              errorText: _showValidationErrors && selectedDate == null ? "Date is required" : null,
                              helperText: 'Auto-set to today – tap to change if needed',
                              suffixIcon: const Icon(Icons.calendar_today),
                            ),
                            child: Text(
                              selectedDate != null
                                  ? "${selectedDate!.month}/${selectedDate!.day}/${selectedDate!.year}"
                                  : "Receiving/Activity Date",
                              style: TextStyle(
                                color: selectedDate != null
                                    ? Theme.of(context).colorScheme.onSurface
                                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: codeController,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                          decoration: InputDecoration(
                            labelText: "Document Code",
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                          ),
                          readOnly: true,
                        ),
                      ],
                    ),
                  ),
                ),
                Card(
                  elevation: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Attachments",
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
                                onPressed: (_isUploadingImages || _isPickingImage || _isSaving) ? null : _takePicture,
                                icon: const Icon(Icons.camera_alt),
                                label: const Text("Take Picture"),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: (_isUploadingImages || _isPickingFile ||_selectedDocumentPaths.isNotEmpty || _isSaving) ? null : () async {
                                  setState(() => _isPickingFile = true);
                                  FilePickerResult? result = await FilePicker.platform.pickFiles(
                                    type: FileType.custom,
                                    allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp','docx', 'pdf'],
                                    allowMultiple: true,
                                    withData: true, // Need bytes for web
                                  );
                                  if (result != null && result.files.isNotEmpty) {
                                    int imagesAdded = 0;
                                    int documentsAdded = 0;
                                    List<String> skippedFiles = [];
                                    for (final file in result.files) {
                                      String? filePath;
                                      int fileSize = 0;

                                      if (kIsWeb) {
                                        // On web, use file.bytes directly
                                        if (file.bytes != null) {
                                          fileSize = file.bytes!.length;
                                          filePath = 'web_file_${DateTime.now().millisecondsSinceEpoch}_${file.name}';
                                          _webFileBytes[filePath] = file.bytes!;
                                        }
                                      } else {
                                        // On mobile/desktop, use file.path
                                        filePath = file.path;
                                        if (filePath != null && filePath.isNotEmpty) {
                                          fileSize = File(filePath).lengthSync();
                                        }
                                      }

                                      if (filePath != null && filePath.isNotEmpty && fileSize > 0) {
                                        if (_isImage(file.name)) {
                                          if (_selectedImagePaths.length >= 20) {
                                            SnackbarUtils.showErrorSnackBar(context, 'Only 20 image files allowed');
                                            continue;
                                          }
                                          if (fileSize > 50 * 1024 * 1024) {
                                            skippedFiles.add(file.name);
                                            continue;
                                          }
                                          _selectedImagePaths.add(filePath);
                                          imagesAdded++;
                                          // Queue for upload
                                          final queueManager = UploadQueueManager();
                                          queueManager.addToQueue(
                                            documentCode: codeController.text,
                                            filePath: filePath,
                                            isImage: true,
                                            localPath: filePath,
                                            bytes: kIsWeb && _webFileBytes.containsKey(filePath) ? _webFileBytes[filePath] : null,
                                          );
                                        } else if (_isDocument(file.name)) {
                                          if (fileSize > 50 * 1024 * 1024) {
                                            skippedFiles.add(file.name);
                                            continue;
                                          }
                                          int currentTotalSize = _selectedDocumentPaths.fold(0, (sum, path) {
                                            if (kIsWeb && _webFileBytes.containsKey(path)) {
                                              return sum + _webFileBytes[path]!.length;
                                            } else if (!kIsWeb) {
                                              return sum + File(path).lengthSync();
                                            }
                                            return sum;
                                          });
                                          if (currentTotalSize + fileSize > 50 * 1024 * 1024) {
                                            SnackbarUtils.showErrorSnackBar(context, '${file.name} would exceed 50MB total limit. Consider using Drive Link instead.');
                                            continue;
                                          }
                                          _selectedDocumentPaths.add(filePath);
                                          documentsAdded++;
                                          // Queue for upload
                                          final queueManager = UploadQueueManager();
                                          queueManager.addToQueue(
                                            documentCode: codeController.text,
                                            filePath: filePath,
                                            isImage: false,
                                            localPath: filePath,
                                            bytes: kIsWeb && _webFileBytes.containsKey(filePath) ? _webFileBytes[filePath] : null,
                                          );
                                        }
                                      }
                                    }
                                    setState(() => _isPickingFile = false);
                                    if (skippedFiles.isNotEmpty) {
                                      SnackbarUtils.showErrorSnackBar(context, 'Files skipped due to size >50MB: ${skippedFiles.join(', ')}');
                                    }
                                    if (imagesAdded > 0) {
                                      SnackbarUtils.showSuccessSnackBar(context, '$imagesAdded image(s) added');
                                    }
                                    if (documentsAdded > 0) {
                                      SnackbarUtils.showSuccessSnackBar(context, '$documentsAdded document(s) added');
                                    }
                                    if (imagesAdded == 0 && documentsAdded == 0 && skippedFiles.isEmpty) {
                                      SnackbarUtils.showErrorSnackBar(context, 'No valid files added');
                                    }
                                  } else {
                                    setState(() => _isPickingFile = false);
                                    SnackbarUtils.showErrorSnackBar(context, 'No file selected');
                                  }
                                },
                                icon: const Icon(Icons.attach_file),
                                label: const Text("Pick Files"),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (kIsWeb) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.info_outline, size: 14, color: Colors.amber.shade800),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'On web, use "Pick Files" and select Camera to capture photos.',
                                  style: TextStyle(fontSize: 12, color: Colors.amber.shade800),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextField(
                          controller: referenceLinkController,
                          enabled: !_isSaving,
                          decoration: InputDecoration(
                            labelText: "Drive Link (optional)",
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                          ),
                        ),
                        // Picking state indicators
                        if (_isPickingImage) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.07),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.blue.withOpacity(0.25)),
                            ),
                            child: const Row(
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2.2),
                                ),
                                SizedBox(width: 12),
                                Icon(Icons.camera_alt_outlined, size: 18, color: Colors.blue),
                                SizedBox(width: 8),
                                Text(
                                  "Processing scan...",
                                  style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (_isPickingFile) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.07),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.blue.withOpacity(0.25)),
                            ),
                            child: const Row(
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2.2),
                                ),
                                SizedBox(width: 12),
                                Icon(Icons.folder_open_outlined, size: 18, color: Colors.blue),
                                SizedBox(width: 8),
                                Text(
                                  "Selecting files...",
                                  style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // Selected files summary panel
                        if (_selectedImagePaths.isNotEmpty || _selectedDocumentPaths.isNotEmpty) ...[
                          const SizedBox(height: 12),
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
                                Row(
                                  children: [
                                    Icon(Icons.cloud_upload_outlined, color: Colors.green.shade600, size: 18),
                                    const SizedBox(width: 6),
                                    Text(
                                      "${_selectedImagePaths.length + _selectedDocumentPaths.length} file(s) queued for upload",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Colors.green.shade700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                                if (_selectedImagePaths.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(Icons.image_outlined, size: 15, color: Colors.grey.shade600),
                                      const SizedBox(width: 4),
                                      Text(
                                        "${_selectedImagePaths.length} image(s)",
                                        style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                                      ),
                                      const Spacer(),
                                      TextButton.icon(
                                        onPressed: _isSaving ? null : () => _viewSelectedFiles(context),
                                        icon: const Icon(Icons.visibility_outlined, size: 14),
                                        label: const Text("View", style: TextStyle(fontSize: 13)),
                                        style: TextButton.styleFrom(
                                          minimumSize: Size.zero,
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_selectedImagePaths.where(_isImage).length > 10) ...[
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade300)),
                                      child: Row(children: [Icon(Icons.lightbulb_outline, size: 15, color: Colors.amber.shade700), const SizedBox(width: 6), Expanded(child: Text('You have ${_selectedImagePaths.where(_isImage).length} images — saving as PDF keeps them in one file.', style: TextStyle(fontSize: 11, color: Colors.amber.shade800)))]),
                                    ),
                                  ],
                                  const SizedBox(height: 6),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: (_isSaving || _isMergingPdf) ? null : _mergeImagesToPdf,
                                      icon: _isMergingPdf ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.picture_as_pdf_outlined, size: 16),
                                      label: Text(_isMergingPdf ? 'Converting...' : 'Save as PDF instead'),
                                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 8), foregroundColor: Colors.deepOrange, side: BorderSide(color: Colors.deepOrange.shade300), textStyle: const TextStyle(fontSize: 13)),
                                    ),
                                  ),
                                ],
                                if (_selectedDocumentPaths.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(Icons.description_outlined, size: 15, color: Colors.grey.shade600),
                                      const SizedBox(width: 4),
                                      Text(
                                        "${_selectedDocumentPaths.length} document(s)",
                                        style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                                      ),
                                    ],
                                  ),
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
                                          final queueManager = UploadQueueManager();
                                          queueManager.removeFromQueue(codeController.text, path);
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

                        if (_isUploadingImages) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.07),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.orange.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.orange),
                                ),
                                const SizedBox(width: 12),
                                Icon(Icons.cloud_upload, size: 18, color: Colors.orange.shade700),
                                const SizedBox(width: 8),
                                Text(
                                  "Uploading to Google Drive...",
                                  style: TextStyle(color: Colors.orange.shade700, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        ],
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
                          controller: remarksController,
                          enabled: !_isSaving,
                          decoration: InputDecoration(
                            labelText: "Remarks",
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                          ),
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _isSaving ? null : () async {
                    setState(() {
                      _showValidationErrors = true;
                    });

                    if (selectedType != null && allOptions.contains(selectedType) && selectedDate != null && personController.text.trim().isNotEmpty && (selectedType != 'Others' || descriptionController.text.trim().isNotEmpty)) {
                      final String code = codeController.text;
                      final String description = descriptionController.text.trim();
                      final String referenceLink = referenceLinkController.text.trim();
                      final String dateStr = "${selectedDate!.month}/${selectedDate!.day}/${selectedDate!.year}";
                      final String remarks = remarksController.text;
                      final String person = personController.text;

                      final doc = Document(
                        code: code,
                        title: description,
                        description: description,
                        referenceLink: referenceLink.isNotEmpty ? referenceLink : null,
                        type: selectedType!,
                        fromOrTo: dateStr,
                        mode: 'Office Function MOVs',
                        assignedTo: person,
                        filePath: null,
                        remarks: remarks,
                        person: person,
                        incoming: false,
                        cabinetLocation: _selectedCabinet,
                        folderTitle: folderTitleController.text.trim().isNotEmpty ? folderTitleController.text.trim() : null,
                        heldBy: heldByController.text.trim().isNotEmpty ? heldByController.text.trim() : null,
                        status: 'Completed',
                        imageUrls: _uploadedImageUrls,
                        fileUrls: _uploadedDocumentUrls,
                        localImagePaths: _selectedImagePaths,
                        localFilePaths: _selectedDocumentPaths,
                        category: selectedType,
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
                        SnackbarUtils.showErrorSnackBar(context, 'Failed to save document: $e');
                        if (mounted) setState(() => _isSaving = false);
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12), // smooth rounded corners
                    ),
                    elevation: 4, // subtle shadow for depth
                    backgroundColor: Color(0xFF81D4FA), // pastel modern accent
                    foregroundColor: Colors.black87, // readable text color
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  child: _isSaving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("Save Certs/MOVs Record", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                if (_isSaving) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.withOpacity(0.22)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2.2),
                            ),
                            const SizedBox(width: 10),
                            Icon(Icons.cloud_upload, color: Colors.blue.shade400, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _totalUploads > 0
                                    ? 'Uploading files to Google Drive...'
                                    : 'Saving record...',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blue.shade700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_totalUploads > 0) ...[
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: _completedUploads / _totalUploads,
                              minHeight: 8,
                              backgroundColor: Colors.blue.withOpacity(0.15),
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.check_circle_outline, size: 14, color: Colors.green.shade600),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$_completedUploads uploaded',
                                    style: TextStyle(fontSize: 12, color: Colors.green.shade600, fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  Icon(Icons.hourglass_bottom, size: 14, color: Colors.orange.shade700),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${_totalUploads - _completedUploads} remaining',
                                    style: TextStyle(fontSize: 12, color: Colors.orange.shade700, fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                              Text(
                                '${(_completedUploads / _totalUploads * 100).round()}%',
                                style: TextStyle(fontSize: 12, color: Colors.blue.shade700, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ],
                        if (_uploadStatus.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            _uploadStatus,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}
