import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../models/document.dart';
import '../services/cached_document_service.dart';
import '../services/document_scanner_service.dart';
import '../services/mlkit_scanner_service.dart';
import '../services/upload_queue_manager.dart';
import '../services/auth_service.dart';
import '../utils/snackbar_utils.dart';
import '../utils/date_time_utils.dart';
import '../constants/document_types.dart';

class AddCdcScreen extends StatefulWidget {
  const AddCdcScreen({super.key});

  @override
  State<AddCdcScreen> createState() => _AddCdcScreenState();
}

class _AddCdcScreenState extends State<AddCdcScreen> {
  final ImagePicker _picker = ImagePicker();
  final titleController = TextEditingController();
  final codeController = TextEditingController();
  String? selectedType;
  DateTime? selectedDate;
  DateTime? selectedCalendarDate;
  DateTime? selectedCalendarEndDate;
  final descriptionController = TextEditingController();
  final referenceLinkController = TextEditingController();
  final remarksController = TextEditingController();
  final personController = TextEditingController();

  List<String> _selectedImagePaths = [];
  List<String> _selectedDocumentPaths = [];
  List<List<int>?> _selectedImageBytes = [];
  final Map<String, List<int>> _webFileBytes = {};
  List<String> _uploadedImageUrls = [];
  List<String> _uploadedDocumentUrls = [];
  bool _isUploadingImages = false;
  bool _isPickingImage = false;
  bool _isPickingFile = false;
  int _totalUploads = 0;
  int _completedUploads = 0;
  String _uploadStatus = '';

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
    codeController.text = _generateCode();
    _setupUploadListener();
    _loadUsername();
  }

  Future<void> _loadUsername() async {
    final username = await AuthService.getUsername();
    if (username != null && username.isNotEmpty) {
      setState(() => personController.text = username);
    }
  }

  void _setupUploadListener() {
    UploadQueueManager().addListener(_onUploadStatusChanged);
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

  @override
  void dispose() {
    UploadQueueManager().removeListener(_onUploadStatusChanged);
    codeController.dispose();
    descriptionController.dispose();
    referenceLinkController.dispose();
    remarksController.dispose();
    personController.dispose();
    super.dispose();
  }

  String _generateCode() {
    final nowUtc = DateTime.now().toUtc();
    final phTime = nowUtc.add(const Duration(hours: 8));
    final month = phTime.month.toString().padLeft(2, '0');
    final day = phTime.day.toString().padLeft(2, '0');
    final year = phTime.year;
    final hour = phTime.hour.toString().padLeft(2, '0');
    final minute = phTime.minute.toString().padLeft(2, '0');
    final second = phTime.second.toString().padLeft(2, '0');
    final typeCode = typeMapping[selectedType] ?? 'CDCA';
    return 'CF-$typeCode-$month$day$year-$hour$minute$second';
  }

  void _onTypeChanged(String? value) {
    setState(() {
      selectedType = value;
      codeController.text = _generateCode();
    });
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
              const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 4), child: Text('Scan Document', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
              ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Camera'), onTap: () => Navigator.pop(context, ImageSource.camera)),
              ListTile(leading: const Icon(Icons.photo_library), title: const Text('Gallery'), onTap: () => Navigator.pop(context, ImageSource.gallery)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _takePicture() async {
    if (!kIsWeb && Platform.isAndroid) { await _scanWithMlKit(); return; }
    final ImageSource? source = await _chooseWebScanSource();
    if (source == null || !mounted) return;
    final int count = _selectedImagePaths.where(_isImage).length;
    if (count >= 10) { SnackbarUtils.showWarningSnackBar(context, 'Only 10 image files allowed'); return; }
    setState(() => _isPickingImage = true);
    final XFile? image = await _picker.pickImage(source: source);
    if (image == null) { if (!mounted) return; setState(() => _isPickingImage = false); SnackbarUtils.showErrorSnackBar(context, 'No image captured'); return; }
    final rawBytes = await image.readAsBytes();
    final scannedBytes = kIsWeb ? rawBytes : (await DocumentScannerService.processImage(rawBytes) ?? rawBytes);
    if (!mounted) return;
    if (kIsWeb) {
      final fileName = 'scanned_${DateTime.now().millisecondsSinceEpoch}.jpg';
      setState(() { _selectedImagePaths.add(fileName); _selectedImageBytes.add(scannedBytes); _isPickingImage = false; });
      UploadQueueManager().addWebCameraImageToQueue(documentCode: codeController.text, filePath: fileName, bytes: scannedBytes);
    } else {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/scanned_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(scannedBytes);
      if (!mounted) return;
      setState(() { _selectedImagePaths.add(tempFile.path); _selectedImageBytes.add(null); _isPickingImage = false; });
      UploadQueueManager().addToQueue(documentCode: codeController.text, filePath: tempFile.path, isImage: true, localPath: tempFile.path);
    }
  }

  Future<void> _scanWithMlKit() async {
    final int remaining = 10 - _selectedImagePaths.where(_isImage).length;
    if (remaining <= 0) { SnackbarUtils.showWarningSnackBar(context, 'Only 10 image files allowed'); return; }
    final ScanOutputFormat? format = await _chooseScanFormat();
    if (format == null || !mounted) return;
    setState(() => _isPickingImage = true);
    ScannerOutput? output;
    try { output = await MlKitScannerService.scanDocument(maxPages: format == ScanOutputFormat.pdf ? 20 : remaining, format: format); } catch (_) { output = null; }
    if (!mounted) return;
    if (output == null) {
      setState(() => _isPickingImage = false);
      if (_selectedImagePaths.where(_isImage).length >= 10) { SnackbarUtils.showWarningSnackBar(context, 'Only 10 image files allowed'); return; }
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
      UploadQueueManager().addToQueue(documentCode: codeController.text, filePath: tempFile.path, isImage: true, localPath: tempFile.path);
      return;
    }
    if (output.wasCancelled) { setState(() => _isPickingImage = false); return; }
    try {
      final tempDir = await getTemporaryDirectory();
      if (output.hasPdf) {
        final tempFile = File('${tempDir.path}/scanned_${DateTime.now().millisecondsSinceEpoch}.pdf');
        await tempFile.writeAsBytes(output.pdf!);
        if (!mounted) return;
        setState(() => _selectedDocumentPaths.add(tempFile.path));
        UploadQueueManager().addToQueue(documentCode: codeController.text, filePath: tempFile.path, isImage: false, localPath: tempFile.path);
      } else {
        for (var i = 0; i < output.images.length; i++) {
          final tempFile = File('${tempDir.path}/mlkit_${DateTime.now().millisecondsSinceEpoch}_$i.jpg');
          await tempFile.writeAsBytes(output.images[i]);
          if (!mounted) return;
          setState(() { _selectedImagePaths.add(tempFile.path); _selectedImageBytes.add(null); });
          UploadQueueManager().addToQueue(documentCode: codeController.text, filePath: tempFile.path, isImage: true, localPath: tempFile.path);
        }
      }
    } finally { if (mounted) setState(() => _isPickingImage = false); }
  }

  Future<ScanOutputFormat?> _chooseScanFormat() {
    return showModalBottomSheet<ScanOutputFormat>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Save scan as…', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: OutlinedButton.icon(onPressed: () => Navigator.pop(ctx, ScanOutputFormat.image), icon: const Icon(Icons.image_outlined), label: const Text('Image'), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)))),
                  const SizedBox(width: 12),
                  Expanded(child: FilledButton.icon(onPressed: () => Navigator.pop(ctx, ScanOutputFormat.pdf), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('PDF'), style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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

  void _viewSelectedFiles(BuildContext context) async {
    final imageFiles = _selectedImagePaths.where((path) {
      final parts = path.split('.');
      if (parts.length <= 1) return false;
      return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'heic'].contains(parts.last.toLowerCase());
    }).toList();
    if (imageFiles.isNotEmpty) {
      showDialog(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: SizedBox(
            width: MediaQuery.of(context).size.width * 0.9,
            height: MediaQuery.of(context).size.height * 0.7,
            child: StatefulBuilder(
              builder: (context, setStateDialog) {
                final pageController = PageController();
                return Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () { if (imageFiles.isNotEmpty) { final currentIndex = pageController.page?.round() ?? 0; setState(() { UploadQueueManager().removeFromQueue(codeController.text, imageFiles[currentIndex]); _selectedImagePaths.remove(imageFiles[currentIndex]); _webFileBytes.remove(imageFiles[currentIndex]); }); setStateDialog(() => imageFiles.removeAt(currentIndex)); if (imageFiles.isEmpty) Navigator.pop(context); } }),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: pageController,
                        itemCount: imageFiles.length,
                        itemBuilder: (context, index) {
                          final path = imageFiles[index];
                          final webBytes = _webFileBytes[path];
                          Widget imageWidget;
                          if (kIsWeb && webBytes != null) {
                            imageWidget = Image.memory(Uint8List.fromList(webBytes), fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Center(child: Text('Failed to load image')));
                          } else if (kIsWeb) {
                            imageWidget = const Center(child: Text('Preview unavailable'));
                          } else {
                            imageWidget = Image.file(File(path), fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Center(child: Text('Failed to load image')));
                          }
                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              InteractiveViewer(child: imageWidget),
                              if (index > 0) Positioned(left: 10, child: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.black54), onPressed: () => pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut))),
                              if (index < imageFiles.length - 1) Positioned(right: 10, child: IconButton(icon: const Icon(Icons.arrow_forward_ios, color: Colors.black54), onPressed: () => pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut))),
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
    } else {
      SnackbarUtils.showErrorSnackBar(context, 'No images selected to view');
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Add CDC Document"),
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFFCCBC), Color(0xFFFF8A65), Color(0xFFFF5722)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          foregroundColor: const Color.fromARGB(255, 28, 28, 28),
        ),
        body: Padding(
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
                        Text("Basic Information", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                        const SizedBox(height: 12),

                        // Document Code + Set to Calendar
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            codeController.text,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          trailing: ElevatedButton.icon(
                            onPressed: _isSaving ? null : () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: selectedCalendarDate ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                              );
                              if (date != null && mounted) {
                                final time = await showTimePicker(
                                  context: context,
                                  initialTime: const TimeOfDay(hour: 8, minute: 0),
                                );
                                if (time != null && mounted) {
                                  final startDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                                  // Ask for optional end date
                                  final endDate = await showDatePicker(
                                    context: context,
                                    initialDate: date,
                                    firstDate: date,
                                    lastDate: date.add(const Duration(days: 365)),
                                    helpText: 'Set end date (optional — cancel to skip)',
                                  );
                                  setState(() {
                                    selectedCalendarDate = startDateTime;
                                    selectedCalendarEndDate = endDate != null
                                        ? DateTime(endDate.year, endDate.month, endDate.day, 23, 59)
                                        : null;
                                  });
                                }
                              }
                            },

                            label: Text(
                              selectedCalendarDate != null
                                  ? selectedCalendarEndDate != null
                                      ? "${DateFormat('MM/dd').format(selectedCalendarDate!)} – ${DateFormat('MM/dd').format(selectedCalendarEndDate!)}"
                                      : " ${DateFormat('MM/dd/yy hh:mm a').format(selectedCalendarDate!)}"
                                  : "Set to Calendar",
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: selectedCalendarDate != null
                                  ? Colors.green
                                  : Theme.of(context).colorScheme.secondary,
                              foregroundColor: Theme.of(context).colorScheme.onSecondary,
                            ),
                          ),

                          ),

                        const Divider(height: 14),

                        // Title
                        TextField(
                          controller: titleController,
                          enabled: !_isSaving,
                          inputFormatters: [_WordLimitFormatter(20)],
                          decoration: InputDecoration(
                            labelText: "Document Title",
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                            errorText: _showValidationErrors &&
                                    titleController.text.trim().isEmpty
                                ? "Document title is required"
                                : null,
                          ),
                          buildCounter: (context, {required currentLength, required isFocused, maxLength}) {
                            final words = titleController.text.trim().isEmpty
                                ? 0
                                : titleController.text.trim().split(RegExp(r'\s+')).length;
                            return Text(
                              '$words / 20 words',
                              style: TextStyle(
                                fontSize: 12,
                                color: words >= 20 ? Colors.orange[700] : Colors.grey,
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value: selectedType,
                          decoration: InputDecoration(
                            labelText: "Type *",
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                            errorText: _showValidationErrors && selectedType == null ? "Please select a document type" : null,
                          ),
                          items: cdcTypes.map((type) => DropdownMenuItem<String>(value: type, child: Text(type))).toList(),
                          onChanged: _isSaving ? null : _onTypeChanged,
                        ),
                        const SizedBox(height: 12),
                        TextField(controller: descriptionController, enabled: !_isSaving, decoration: InputDecoration(labelText: "Description (optional)", border: const OutlineInputBorder(), filled: true, fillColor: Theme.of(context).colorScheme.surface), maxLines: 3),
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: _isSaving ? null : () => _selectDate(context),
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: "Receiving Date *",
                              border: const OutlineInputBorder(),
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.surface,
                              errorText: _showValidationErrors && selectedDate == null ? "Date is required" : null,
                              suffixIcon: const Icon(Icons.calendar_today),
                            ),
                            child: Text(
                              selectedDate != null ? "${selectedDate!.month}/${selectedDate!.day}/${selectedDate!.year}" : "Select date",
                              style: TextStyle(color: selectedDate != null ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
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
                        Text("Attachments", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: ElevatedButton.icon(onPressed: (_isUploadingImages || _isPickingImage || _isSaving) ? null : _takePicture, icon: const Icon(Icons.camera_alt), label: const Text("Take Picture"), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16)))),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: (_isUploadingImages || _isPickingFile || _isSaving) ? null : () async {
                                  setState(() => _isPickingFile = true);
                                  FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'docx', 'pdf'], allowMultiple: true, withData: true);
                                  if (result != null && result.files.isNotEmpty) {
                                    int imagesAdded = 0, documentsAdded = 0;
                                    final skippedFiles = <String>[];
                                    for (final file in result.files) {
                                      String? filePath;
                                      int fileSize = 0;
                                      if (kIsWeb) {
                                        if (file.bytes != null) { fileSize = file.bytes!.length; filePath = 'web_file_${DateTime.now().millisecondsSinceEpoch}_${file.name}'; _webFileBytes[filePath] = file.bytes!; }
                                      } else {
                                        filePath = file.path;
                                        if (filePath != null && filePath.isNotEmpty) fileSize = File(filePath).lengthSync();
                                      }
                                      if (filePath != null && filePath.isNotEmpty && fileSize > 0) {
                                        if (_isImage(file.name)) {
                                          if (_selectedImagePaths.length >= 20) { SnackbarUtils.showErrorSnackBar(context, 'Only 20 image files allowed'); continue; }
                                          if (fileSize > 50 * 1024 * 1024) { skippedFiles.add(file.name); continue; }
                                          _selectedImagePaths.add(filePath); imagesAdded++;
                                          UploadQueueManager().addToQueue(documentCode: codeController.text, filePath: filePath, isImage: true, localPath: filePath, bytes: kIsWeb && _webFileBytes.containsKey(filePath) ? _webFileBytes[filePath] : null);
                                        } else if (_isDocument(file.name)) {
                                          if (fileSize > 50 * 1024 * 1024) { skippedFiles.add(file.name); continue; }
                                          int currentTotalSize = _selectedDocumentPaths.fold(0, (sum, path) { if (kIsWeb && _webFileBytes.containsKey(path)) return sum + _webFileBytes[path]!.length; else if (!kIsWeb) return sum + File(path).lengthSync(); return sum; });
                                          if (currentTotalSize + fileSize > 50 * 1024 * 1024) { SnackbarUtils.showErrorSnackBar(context, '${file.name} would exceed 50MB total limit.'); continue; }
                                          _selectedDocumentPaths.add(filePath); documentsAdded++;
                                          UploadQueueManager().addToQueue(documentCode: codeController.text, filePath: filePath, isImage: false, localPath: filePath, bytes: kIsWeb && _webFileBytes.containsKey(filePath) ? _webFileBytes[filePath] : null);
                                        }
                                      }
                                    }
                                    setState(() => _isPickingFile = false);
                                    if (skippedFiles.isNotEmpty) SnackbarUtils.showErrorSnackBar(context, 'Files skipped (>50MB): ${skippedFiles.join(', ')}');
                                    if (imagesAdded > 0) SnackbarUtils.showSuccessSnackBar(context, '$imagesAdded image(s) added');
                                    if (documentsAdded > 0) SnackbarUtils.showSuccessSnackBar(context, '$documentsAdded document(s) added');
                                    if (imagesAdded == 0 && documentsAdded == 0 && skippedFiles.isEmpty) SnackbarUtils.showErrorSnackBar(context, 'No valid files added');
                                  } else { setState(() => _isPickingFile = false); }
                                },
                                icon: const Icon(Icons.attach_file),
                                label: const Text("Pick Files"),
                                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16)),
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
                        TextField(controller: referenceLinkController, enabled: !_isSaving, decoration: InputDecoration(labelText: "Drive Link (optional)", border: const OutlineInputBorder(), filled: true, fillColor: Theme.of(context).colorScheme.surface)),
                        if (_isPickingImage) ...[
                          const SizedBox(height: 12),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), decoration: BoxDecoration(color: Colors.blue.withOpacity(0.07), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue.withOpacity(0.25))), child: const Row(children: [SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2)), SizedBox(width: 12), Icon(Icons.camera_alt_outlined, size: 18, color: Colors.blue), SizedBox(width: 8), Text("Processing scan...", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w500))])),
                        ],
                        if (_isPickingFile) ...[
                          const SizedBox(height: 12),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), decoration: BoxDecoration(color: Colors.blue.withOpacity(0.07), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue.withOpacity(0.25))), child: const Row(children: [SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2)), SizedBox(width: 12), Icon(Icons.folder_open_outlined, size: 18, color: Colors.blue), SizedBox(width: 8), Text("Selecting files...", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w500))])),
                        ],
                        if (_selectedImagePaths.isNotEmpty || _selectedDocumentPaths.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: Colors.green.withOpacity(0.05), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.green.withOpacity(0.3))),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [Icon(Icons.cloud_upload_outlined, color: Colors.green.shade600, size: 18), const SizedBox(width: 6), Text("${_selectedImagePaths.length + _selectedDocumentPaths.length} file(s) queued for upload", style: TextStyle(fontWeight: FontWeight.w600, color: Colors.green.shade700, fontSize: 13))]),
                                if (_selectedImagePaths.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Row(children: [Icon(Icons.image_outlined, size: 15, color: Colors.grey.shade600), const SizedBox(width: 4), Text("${_selectedImagePaths.length} image(s)", style: TextStyle(fontSize: 13, color: Colors.grey.shade700)), const Spacer(), TextButton.icon(onPressed: _isSaving ? null : () => _viewSelectedFiles(context), icon: const Icon(Icons.visibility_outlined, size: 14), label: const Text("View", style: TextStyle(fontSize: 13)), style: TextButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), tapTargetSize: MaterialTapTargetSize.shrinkWrap))]),
                                ],
                                if (_selectedDocumentPaths.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Row(children: [Icon(Icons.description_outlined, size: 15, color: Colors.grey.shade600), const SizedBox(width: 4), Text("${_selectedDocumentPaths.length} document(s)", style: TextStyle(fontSize: 13, color: Colors.grey.shade700))]),
                                  const SizedBox(height: 6),
                                  Wrap(spacing: 6, runSpacing: 6, children: _selectedDocumentPaths.map((path) { final fileName = path.split('\\').last.split('/').last; final isPdf = fileName.toLowerCase().endsWith('.pdf'); return Chip(avatar: Icon(isPdf ? Icons.picture_as_pdf : Icons.description, size: 16, color: isPdf ? Colors.red.shade400 : Colors.blue.shade400), label: Text(fileName.length > 20 ? '${fileName.substring(0, 17)}...' : fileName, style: const TextStyle(fontSize: 12)), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, onDeleted: _isSaving ? null : () { UploadQueueManager().removeFromQueue(codeController.text, path); setState(() => _selectedDocumentPaths.remove(path)); }); }).toList()),
                                ],
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextField(controller: remarksController, enabled: !_isSaving, decoration: InputDecoration(labelText: "Remarks", border: const OutlineInputBorder(), filled: true, fillColor: Theme.of(context).colorScheme.surface), maxLines: 3),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _isSaving ? null : () async {
                    setState(() => _showValidationErrors = true);
                    if (selectedType != null && selectedDate != null && personController.text.trim().isNotEmpty) {
                      final String code = codeController.text;
                      final String description = descriptionController.text.trim();
                      final String referenceLink = referenceLinkController.text.trim();
                      final String dateStr = "${selectedDate!.month}/${selectedDate!.day}/${selectedDate!.year}";
                      final String remarks = remarksController.text;
                      final String person = personController.text;
                      final doc = Document(
                        code: code,
                        title: titleController.text.trim().isNotEmpty ? titleController.text.trim() : selectedType,
                        description: description.isNotEmpty ? description : null,
                        referenceLink: referenceLink.isNotEmpty ? referenceLink : null,
                        type: selectedType!,
                        fromOrTo: dateStr,
                        mode: 'CDC Documents',
                        assignedTo: person,
                        filePath: null,
                        remarks: remarks,
                        person: person,
                        incoming: false,
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
                        navigator.pop();
                      } catch (e) {
                        SnackbarUtils.showErrorSnackBar(context, 'Failed to save: $e');
                        if (mounted) setState(() => _isSaving = false);
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 4, backgroundColor: const Color(0xFFFF8A65), foregroundColor: Colors.black87, textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                  child: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text("Save Record", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                if (_isSaving) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.blue.withOpacity(0.07), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.withOpacity(0.22))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2)), const SizedBox(width: 10), Icon(Icons.cloud_upload, color: Colors.blue.shade400, size: 20), const SizedBox(width: 8), Expanded(child: Text(_totalUploads > 0 ? 'Uploading files to Google Drive...' : 'Saving record...', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.blue.shade700, fontSize: 13)))]),
                        if (_totalUploads > 0) ...[
                          const SizedBox(height: 12),
                          ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: _completedUploads / _totalUploads, minHeight: 8, backgroundColor: Colors.blue.withOpacity(0.15), valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue))),
                          const SizedBox(height: 8),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Row(children: [Icon(Icons.check_circle_outline, size: 14, color: Colors.green.shade600), const SizedBox(width: 4), Text('$_completedUploads uploaded', style: TextStyle(fontSize: 12, color: Colors.green.shade600, fontWeight: FontWeight.w500))]), Row(children: [Icon(Icons.hourglass_bottom, size: 14, color: Colors.orange.shade700), const SizedBox(width: 4), Text('${_totalUploads - _completedUploads} remaining', style: TextStyle(fontSize: 12, color: Colors.orange.shade700, fontWeight: FontWeight.w500))]), Text('${(_completedUploads / _totalUploads * 100).round()}%', style: TextStyle(fontSize: 12, color: Colors.blue.shade700, fontWeight: FontWeight.w600))]),
                        ],
                        if (_uploadStatus.isNotEmpty) ...[const SizedBox(height: 6), Text(_uploadStatus, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey.shade600))],
                      ],
                    ),
                  ),
                ],
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
  _WordLimitFormatter(this.maxWords);

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final words = newValue.text.trim().isEmpty
        ? 0
        : newValue.text.trim().split(RegExp(r'\s+')).length;
    return words > maxWords ? oldValue : newValue;
  }
}

