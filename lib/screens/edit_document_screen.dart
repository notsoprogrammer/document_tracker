import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/document.dart';
import '../services/cached_document_service.dart';
import '../services/document_scanner_service.dart';
import '../services/mlkit_scanner_service.dart';
import '../services/google_drive_service.dart';
import '../services/upload_queue_manager.dart';
import '../services/auth_service.dart';
import '../utils/snackbar_utils.dart';
import '../config/supabase_config.dart';
import 'package:intl/intl.dart';

class EditDocumentScreen extends StatefulWidget {
  final Document document;

  const EditDocumentScreen({super.key, required this.document});

  @override
  State<EditDocumentScreen> createState() => _EditDocumentScreenState();
}

class _EditDocumentScreenState extends State<EditDocumentScreen> {
  final ImagePicker _picker = ImagePicker();
  final GoogleDriveService _driveService = GoogleDriveService();
  final titleController = TextEditingController();
  final descriptionController = TextEditingController();
  final remarksController = TextEditingController();
  final referenceLinkController = TextEditingController();
  final personController = TextEditingController();

  // File handling
  List<String> _selectedImagePaths = [];
  List<String> _selectedDocumentPaths = [];
  List<List<int>?> _selectedImageBytes = []; // For web camera images
  final Map<String, List<int>> _webFileBytes = {}; // For web file picker files
  List<String> _uploadedImageUrls = [];
  List<String> _uploadedDocumentUrls = [];

  // Current attachments (for editing)
  List<String> _currentImageUrls = [];
  List<String> _currentFileUrls = [];
  List<String> _currentFileNames = [];

  bool _isUploadingImages = false;
  bool _isPickingImage = false;
  bool _isPickingFile = false;
  bool _isSaving = false;
  String _uploadStatus = '';
  int _totalUploads = 0;
  int _completedUploads = 0;

  // Validation flags
  bool _showValidationErrors = false;
  String? _currentUsername;
  bool _isCreator = false;
  DateTime? selectedCalendarDate;
  DateTime? selectedCalendarEndDate;

  @override
  void initState() {
    super.initState();
    _loadUsername();
    _setupUploadListener();
    _initializeFields();
  }

  Future<void> _loadUsername() async {
    final username = await AuthService.getUsername();
    setState(() {
      _currentUsername = username;
      _isCreator = username == widget.document.person;
    });
  }

  void _initializeFields() {
    titleController.text = widget.document.title ?? '';
    descriptionController.text = widget.document.description ?? '';
    remarksController.text = widget.document.remarks;
    referenceLinkController.text = widget.document.referenceLink ?? '';
    personController.text = widget.document.person;
    selectedCalendarDate = widget.document.calendarDeadline;
    selectedCalendarEndDate = widget.document.calendarDeadlineEnd;

    // Initialize current attachments
    _currentImageUrls = List.from(widget.document.imageUrls);
    _currentFileUrls = List.from(widget.document.fileUrls);
    _currentFileNames = List.from(widget.document.fileNames);
  }

  void _setupUploadListener() {
    final queueManager = UploadQueueManager();
    queueManager.addListener(_onUploadStatusChanged);
  }

  @override
  void dispose() {
    final queueManager = UploadQueueManager();
    queueManager.removeListener(_onUploadStatusChanged);
    super.dispose();
  }

  void _onUploadStatusChanged() {
    if (!mounted) return;
    final queueManager = UploadQueueManager();
    final pendingUploads = queueManager.getPendingUploads(widget.document.code);
    final uploadingUploads = queueManager.getAllItems().where((item) =>
      item['documentCode'] == widget.document.code && item['status'] == 'uploading'
    ).toList();
    final completedUploads = queueManager.getAllItems().where((item) =>
      item['documentCode'] == widget.document.code && item['status'] == 'completed'
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

    // If all uploads are done and we were saving, pop the screen
    if (_isSaving && pendingUploads.isEmpty && uploadingUploads.isEmpty) {
      _isSaving = false;
      if (mounted) {
        Navigator.pop(context, null); // Document was updated
      }
    }
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

    final ImageSource? source = await _chooseWebScanSource();
    if (source == null || !mounted) return;

    final int currentImageCount = _selectedImagePaths.where(_isImage).length;
    if (currentImageCount >= 10) {
      SnackbarUtils.showErrorSnackBar(context, 'Only 10 image files allowed');
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
    final scannedBytes = await DocumentScannerService.processImage(rawBytes) ?? rawBytes;

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
    final int remaining = 10 - _selectedImagePaths.where(_isImage).length;
    if (remaining <= 0) {
      SnackbarUtils.showErrorSnackBar(context, 'Only 10 image files allowed');
      return;
    }

    final ScanOutputFormat? format = await _chooseScanFormat();
    if (format == null || !mounted) return;

    setState(() => _isPickingImage = true);

    ScannerOutput? output;
    try {
      output = await MlKitScannerService.scanDocument(
        maxPages: format == ScanOutputFormat.pdf ? 20 : remaining,
        format: format,
      );
    } catch (_) {
      output = null;
    }

    if (!mounted) return;

    if (output == null) {
      setState(() => _isPickingImage = false);
      final int currentImageCount = _selectedImagePaths.where(_isImage).length;
      if (currentImageCount >= 10) {
        SnackbarUtils.showErrorSnackBar(context, 'Only 10 image files allowed');
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
      final scannedBytes = await DocumentScannerService.processImage(rawBytes) ?? rawBytes;
      if (!mounted) return;
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
      return;
    }

    if (output.wasCancelled) {
      setState(() => _isPickingImage = false);
      return;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      if (output.hasPdf) {
        final tempFile = File('${tempDir.path}/scanned_${DateTime.now().millisecondsSinceEpoch}.pdf');
        await tempFile.writeAsBytes(output.pdf!);
        if (!mounted) return;
        setState(() => _selectedDocumentPaths.add(tempFile.path));
        UploadQueueManager().addToQueue(
          documentCode: widget.document.code,
          filePath: tempFile.path,
          isImage: false,
          localPath: tempFile.path,
        );
      } else {
        for (var i = 0; i < output.images.length; i++) {
          final tempFile = File('${tempDir.path}/mlkit_${DateTime.now().millisecondsSinceEpoch}_$i.jpg');
          await tempFile.writeAsBytes(output.images[i]);
          if (!mounted) return;
          setState(() {
            _selectedImagePaths.add(tempFile.path);
            _selectedImageBytes.add(null);
          });
          UploadQueueManager().addToQueue(
            documentCode: widget.document.code,
            filePath: tempFile.path,
            isImage: true,
            localPath: tempFile.path,
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isPickingImage = false);
    }
  }

  Future<ScanOutputFormat?> _chooseScanFormat() {
    return showModalBottomSheet<ScanOutputFormat>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Save scan as…',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(ctx, ScanOutputFormat.image),
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('Image'),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(ctx, ScanOutputFormat.pdf),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('PDF'),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    ),
                  ),
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
        content: const Text('Do you want to exit without saving?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false), // Continue Editing
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

  void _viewSelectedFiles(BuildContext context) async {
    final imageFiles = _selectedImagePaths.where((path) {
      final parts = path.split('.');
      if (parts.length <= 1) return false;
      final extension = parts.last.toLowerCase();
      return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp','heic','heif'].contains(extension);
    }).toList();

    final otherFiles = _selectedImagePaths.where((path) {
      final parts = path.split('.');
      if (parts.length <= 1) return true;
      final extension = parts.last.toLowerCase();
      return !['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp','heic','heif'].contains(extension);
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
                                queueManager.removeFromQueue(widget.document.code, imageFiles[currentIndex]);
                                _selectedImagePaths.remove(imageFiles[currentIndex]);
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
                                child: Image.file(
                                  File(imageFiles[index]),
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Center(child: Text('Failed to load image'));
                                  },
                                ),
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
      SnackbarUtils.showInfoSnackBar(context, 'No files selected to view');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCreator) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("View Document"),
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
        body: Center(
          child: Text(
            "Only the creator can edit this document.",
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Edit Document"),
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
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
            ],
          ),
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

                        // Document Code
                        Text(
                          widget.document.code,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Start date row
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _isSaving ? null : () async {
                                  final date = await showDatePicker(
                                    context: context,
                                    initialDate: selectedCalendarDate ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                                  );
                                  if (date == null) return;
                                  if (!mounted) return;
                                  final time = await showTimePicker(
                                    context: context,
                                    initialTime: TimeOfDay.fromDateTime(
                                      selectedCalendarDate ?? DateTime(date.year, date.month, date.day, 8, 0),
                                    ),
                                  );
                                  if (time != null) {
                                    setState(() {
                                      selectedCalendarDate = DateTime(
                                        date.year, date.month, date.day,
                                        time.hour, time.minute,
                                      );
                                      if (selectedCalendarEndDate != null &&
                                          !selectedCalendarEndDate!.isAfter(selectedCalendarDate!)) {
                                        selectedCalendarEndDate = null;
                                      }
                                    });
                                  }
                                },
                                icon: const Icon(Icons.calendar_today, size: 15),
                                label: Text(
                                  selectedCalendarDate != null
                                      ? DateFormat('MM/dd/yy hh:mm a').format(selectedCalendarDate!)
                                      : "Set to Calendar",
                                  overflow: TextOverflow.ellipsis,
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: selectedCalendarDate != null
                                      ? Colors.green
                                      : Theme.of(context).colorScheme.primary,
                                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                                ),
                              ),
                            ),
                            if (selectedCalendarDate != null)
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                tooltip: 'Clear calendar',
                                onPressed: () => setState(() {
                                  selectedCalendarDate = null;
                                  selectedCalendarEndDate = null;
                                }),
                              ),
                          ],
                        ),
                        // End date row (visible only when start is set)
                        if (selectedCalendarDate != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _isSaving ? null : () async {
                                    final date = await showDatePicker(
                                      context: context,
                                      initialDate: selectedCalendarEndDate ??
                                          selectedCalendarDate!.add(const Duration(days: 1)),
                                      firstDate: selectedCalendarDate!,
                                      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                                    );
                                    if (date == null) return;
                                    if (!mounted) return;
                                    // ignore: use_build_context_synchronously
                                    final time = await showTimePicker(
                                      context: context,
                                      initialTime: TimeOfDay.fromDateTime(
                                        selectedCalendarEndDate ??
                                            DateTime(date.year, date.month, date.day, 17, 0),
                                      ),
                                    );
                                    if (time != null) {
                                      setState(() {
                                        selectedCalendarEndDate = DateTime(
                                          date.year, date.month, date.day,
                                          time.hour, time.minute,
                                        );
                                      });
                                    }
                                  },
                                  icon: Icon(
                                    Icons.event_available,
                                    size: 15,
                                    color: selectedCalendarEndDate != null ? Colors.green : null,
                                  ),
                                  label: Text(
                                    selectedCalendarEndDate != null
                                        ? "End: ${DateFormat('MM/dd/yy hh:mm a').format(selectedCalendarEndDate!)}"
                                        : "Set End Date (optional)",
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: selectedCalendarEndDate != null ? Colors.green : null,
                                    ),
                                  ),
                                ),
                              ),
                              if (selectedCalendarEndDate != null)
                                IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  tooltip: 'Clear end date',
                                  onPressed: () => setState(() => selectedCalendarEndDate = null),
                                ),
                            ],
                          ),
                        ],

                        const Divider(height: 14),

                        // Title
                        Builder(builder: (context) {
                          final locked = ['Locational & Zoning', 'Reclassification', 'SP Documents'].contains(widget.document.mode);
                          final label = widget.document.mode == 'SP Documents'
                              ? 'Ordinance/Resolution Number'
                              : locked ? 'Applicant Name' : 'Document Title';
                          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            TextField(
                              controller: titleController,
                              enabled: locked ? false : !_isSaving,
                              inputFormatters: locked ? [] : [_WordLimitFormatter(20)],
                              decoration: InputDecoration(
                                labelText: label,
                                border: OutlineInputBorder(),
                                filled: true,
                                fillColor: Theme.of(context).colorScheme.surface,
                                suffixIcon: locked ? const Icon(Icons.lock_outline, size: 18, color: Colors.grey) : null,
                                errorText: !locked && _showValidationErrors && titleController.text.trim().isEmpty
                                    ? "Document title is required"
                                    : null,
                              ),
                              buildCounter: locked ? null : (context, {required currentLength, required isFocused, maxLength}) {
                                final words = titleController.text.trim().isEmpty ? 0 : titleController.text.trim().split(RegExp(r'\s+')).length;
                                return Text('$words / 20 words', style: TextStyle(fontSize: 12, color: words >= 20 ? Colors.orange[700] : Colors.grey));
                              },
                            ),
                            if (locked) ...[
                              const SizedBox(height: 4),
                              Row(children: [
                                Icon(Icons.info_outline, size: 13, color: Colors.grey.shade500),
                                const SizedBox(width: 4),
                                Text('This field cannot be changed after the document is created.', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                              ]),
                            ],
                          ]);
                        }),

                        const SizedBox(height: 16),

                        // Document Type (read-only)
                        DropdownButtonFormField<String>(
                          value: widget.document.type,
                          decoration: InputDecoration(
                            labelText: "Document Type (Locked)",
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface.withOpacity(0.5),
                          ),
                          items: [widget.document.type]
                              .map((type) =>
                                  DropdownMenuItem(value: type, child: Text(type)))
                              .toList(),
                          onChanged: null, // Disabled
                        ),

                        const SizedBox(height: 16),

                        // Description
                        TextField(
                          controller: descriptionController,
                          enabled: !_isSaving,
                          decoration: InputDecoration(
                            labelText: "Description",
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

                        // Existing Attachments
                        if (_currentImageUrls.isNotEmpty) ...[
                          Text(
                            "Existing Images:",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            height: 300,
                            child: StatefulBuilder(
                              builder: (context, setStateDialog) {
                                final PageController pageController = PageController();
                                return Stack(
                                  children: [
                                    PageView.builder(
                                      controller: pageController,
                                      itemCount: _currentImageUrls.length,
                                      itemBuilder: (context, index) {
                                        String fileName = index < _currentFileNames.length ? _currentFileNames[index] : 'Image ${index + 1}';
                                        String imageUrl = _currentImageUrls[index];
                                        String proxyUrl = GoogleDriveService.generateProxyUrl(imageUrl.contains('drive.google.com/uc?id=') ? Uri.parse(imageUrl).queryParameters['id'] ?? imageUrl : imageUrl);
                                        return Column(
                                          children: [
                                            Padding(
                                              padding: const EdgeInsets.all(8.0),
                                              child: Text(fileName, style: TextStyle(fontWeight: FontWeight.bold)),
                                            ),
                                            Expanded(
                                              child: InteractiveViewer(
                                                child: CachedNetworkImage(
                                                  imageUrl: proxyUrl,
                                                  httpHeaders: {'Authorization': 'Bearer ${SupabaseConfig.supabaseAnonKey}'},
                                                  fit: BoxFit.contain,
                                                  placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                                                  errorWidget: (context, url, error) => const Center(child: Text('Failed to load image')),
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
                                        icon: Icon(Icons.delete, color: Colors.red),
                                        onPressed: () async {
                                          final currentIndex = pageController.page?.round() ?? 0;
                                          final fileName = currentIndex < _currentFileNames.length ? _currentFileNames[currentIndex] : 'Image ${currentIndex + 1}';
                                          final confirm = await showDialog<bool>(
                                            context: context,
                                            builder: (context) => AlertDialog(
                                              title: const Text('Remove Attachment'),
                                              content: Text('Are you sure you want to remove "$fileName"? This will delete it from Google Drive as well.'),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
                                              ],
                                            ),
                                          );
                                          if (confirm == true) {
                                            final url = _currentImageUrls[currentIndex];
                                            setState(() {
                                              _currentImageUrls.removeAt(currentIndex);
                                              if (currentIndex < _currentFileNames.length) _currentFileNames.removeAt(currentIndex);
                                            });
                                            setStateDialog(() {}); // to update the PageView
                                            final success = await CachedDocumentService().deleteAttachmentFromDrive(url);
                                            if (success) {
                                              SnackbarUtils.showSuccessSnackBar(context, 'Attachment removed successfully');
                                            } else {
                                              SnackbarUtils.showErrorSnackBar(context, 'Failed to remove attachment from Google Drive');
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
                                          icon: Icon(Icons.arrow_back_ios, color: Colors.white),
                                          onPressed: () {
                                            if (pageController.page! > 0) {
                                              pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                                            }
                                          },
                                        ),
                                      ),
                                      Positioned(
                                        right: 10,
                                        bottom: 10,
                                        child: IconButton(
                                          icon: Icon(Icons.arrow_forward_ios, color: Colors.white),
                                          onPressed: () {
                                            if (pageController.page! < _currentImageUrls.length - 1) {
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
                          const SizedBox(height: 16),
                        ],
                        if (_currentFileUrls.isNotEmpty) ...[
                          Text(
                            "Existing Documents:",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 200,
                            child: ListView.builder(
                              itemCount: _currentFileUrls.length,
                              itemBuilder: (context, index) {
                                final url = _currentFileUrls[index];
                                final fileName = (_currentFileNames.length > _currentImageUrls.length + index) ? _currentFileNames[_currentImageUrls.length + index] : 'Document ${index + 1}';
                                return ListTile(
                                  leading: Icon(Icons.attach_file),
                                  title: Text(fileName),
                                  onTap: () => _viewExistingFile(context, url),
                                  trailing: IconButton(
                                    icon: Icon(Icons.remove),
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: const Text('Remove Attachment'),
                                          content: Text('Are you sure you want to remove "$fileName"? This will delete it from Google Drive as well.'),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        setState(() {
                                          _currentFileUrls.removeAt(index);
                                          final nameIndex = _currentImageUrls.length + index;
                                          if (nameIndex < _currentFileNames.length) _currentFileNames.removeAt(nameIndex);
                                        });
                                        final success = await CachedDocumentService().deleteAttachmentFromDrive(url);
                                        if (success) {
                                          SnackbarUtils.showSuccessSnackBar(context, 'Attachment removed successfully');
                                        } else {
                                          SnackbarUtils.showErrorSnackBar(context, 'Failed to remove attachment from Google Drive');
                                        }
                                      }
                                    },
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Add New Attachments
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
                                            documentCode: widget.document.code,
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
                                            documentCode: widget.document.code,
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
                        if (_isPickingImage) ...[
                          const SizedBox(height: 8),
                          const LinearProgressIndicator(),
                          const Text("Capturing image..."),
                        ],
                        if (_isPickingFile) ...[
                          const SizedBox(height: 8),
                          const LinearProgressIndicator(),
                          const Text("Selecting document..."),
                        ],
                        if (_selectedImagePaths.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: _isSaving ? null : () => _viewSelectedFiles(context),
                            child: Text(
                              "View Selected Images (${_selectedImagePaths.length})",
                              style: TextStyle(
                                fontSize: 14,
                                fontStyle: FontStyle.italic,
                                color: Theme.of(context).colorScheme.primary,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                        if (_selectedDocumentPaths.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            "${_selectedDocumentPaths.length} document(s) selected",
                            style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _selectedDocumentPaths.asMap().entries.map((entry) {
                              final index = entry.key;
                              final path = entry.value;
                              final fileName = path.split('\\').last.split('/').last;
                              return Chip(
                                label: Text(fileName),
                                onDeleted: _isSaving ? null : () {
                                  // Remove from upload queue
                                  final queueManager = UploadQueueManager();
                                  queueManager.removeFromQueue(widget.document.code, path);
                                  setState(() => _selectedDocumentPaths.remove(path));
                                },
                              );
                            }).toList(),
                          ),
                        ],

                        if (_isUploadingImages) ...[
                          const SizedBox(height: 8),
                          const LinearProgressIndicator(),
                          const Text("Uploading images to Google Drive..."),
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

                    if (titleController.text.trim().isNotEmpty){

                      final updates = {
                        'title': titleController.text.trim(),
                        'description': descriptionController.text.trim().isNotEmpty ? descriptionController.text.trim() : null,
                        'remarks': remarksController.text.trim(),
                        'reference_link': referenceLinkController.text.trim().isNotEmpty ? referenceLinkController.text.trim() : null,
                        'image_urls': _currentImageUrls,
                        'file_urls': _currentFileUrls,
                        'file_names': _currentFileNames,
                        'local_image_paths': _selectedImagePaths,
                        'local_file_paths': _selectedDocumentPaths,
                        'calendar_deadline': selectedCalendarDate?.toIso8601String(),
                        'calendar_deadline_end': selectedCalendarEndDate?.toIso8601String(),
                        'calendar_added': selectedCalendarDate != null,
                      };

                      setState(() => _isSaving = true);
                      try {
                        // Update document
                        await CachedDocumentService().updateDocument(widget.document.code, updates);

                        // Process pending uploads (files were already queued when selected)
                        final documentService = CachedDocumentService();
                        await documentService.processPendingUploads();

                        // Wait a bit for uploads to complete and check status
                        await Future.delayed(const Duration(seconds: 2));

                        // Check if there are still any pending uploads for this document
                        final queueManager = UploadQueueManager();
                        final pendingUploads = queueManager.getPendingUploads(widget.document.code);
                        final uploadingUploads = queueManager.getAllItems().where((item) =>
                          item['documentCode'] == widget.document.code && item['status'] == 'uploading'
                        ).toList();

                        if (pendingUploads.isNotEmpty || uploadingUploads.isNotEmpty) {
                          SnackbarUtils.showInfoSnackBar(context, 'Some files are still uploading. Please wait a moment.');
                          return;
                        }

                        // Fetch the updated document to get the Google Drive file names
                        final allDocs = await documentService.fetchDocuments();
                        final updatedDoc = allDocs.firstWhere((doc) => doc.code == widget.document.code);
                        final newAttachmentCount = _selectedImagePaths.length + _selectedDocumentPaths.length;
                        // Safety check to prevent negative start index
                        final startIndex = updatedDoc.fileNames.length - newAttachmentCount;
                        final googleDriveFileNames = startIndex >= 0 ? updatedDoc.fileNames.sublist(startIndex) : [];

                        // Add history entry for edit
                        final username = await AuthService.getUsername();
                        if (username != null) {
                          await documentService.addHistoryEntry(
                            widget.document.code,
                            HistoryEntry(
                              action: 'Document edited',
                              person: username,
                              timestamp: DateTime.now(),
                              notes: googleDriveFileNames.isNotEmpty ? 'Added ${googleDriveFileNames.length} attachment(s): ${googleDriveFileNames.join(', ')}' : null,
                            ),
                          );
                        }

                        // Sync the document
                        await documentService.syncSpecificDocument(widget.document.code);

                        if (mounted) {
                          Navigator.pop(context);
                        }
                      } catch (e) {
                        SnackbarUtils.showErrorSnackBar(context, 'Failed to update document: $e');
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
                      : const Text("Save Changes", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                if (_isSaving) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _totalUploads > 0 ? _completedUploads / _totalUploads : null,
                  ),
                  const SizedBox(height: 4),
                  Text(_uploadStatus, textAlign: TextAlign.center),
                ],
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  bool _isImage(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp','heif','heic'].contains(ext);
  }

  bool _isDocument(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return ['pdf', 'docx'].contains(ext);
  }

  void _viewExistingImage(BuildContext context, Document document, int index) {
    final PageController pageController = PageController(initialPage: index);
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (_) => Dialog(
        backgroundColor: Colors.black.withOpacity(0.8),
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox.expand(
          child: Stack(
            children: [
              PageView.builder(
                controller: pageController,
                itemCount: document.imageUrls.length,
                itemBuilder: (context, index) {
                  String fileName = index < document.fileNames.length ? document.fileNames[index] : 'Image ${index + 1}';

                  // Handle both fileId and Google Drive URL formats
                  String imageUrl = document.imageUrls[index];
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

                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          fileName,
                          style: const TextStyle(
                            color: Colors.white,
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
                                        color: Colors.white,
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
              if (document.imageUrls.length > 1) ...[
                Positioned(
                  left: 10,
                  top: MediaQuery.of(context).size.height * 0.4 - 25,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF0992C2), size: 30),
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
                  top: MediaQuery.of(context).size.height * 0.4 - 25,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, color: Color(0xFF0992C2), size: 30),
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

  void _viewExistingFile(BuildContext context, String url) async {
    // Handle Google Drive file IDs and URLs
    String urlToLaunch;
    if (url.contains('drive.google.com') || url.startsWith('http')) {
      // If it's already a full URL, check if it's a direct download URL
      if (url.contains('drive.google.com/uc?id=')) {
        // Extract file ID from download URL and generate proxy URL
        final uri = Uri.parse(url);
        final fileId = uri.queryParameters['id'];
        if (fileId != null && fileId.isNotEmpty) {
          urlToLaunch = GoogleDriveService.generateProxyUrl(fileId);
        } else {
          urlToLaunch = url;
        }
      } else {
        // Other Google Drive URLs - use as is
        urlToLaunch = url;
      }
    } else {
      // Assume it's a file ID and generate proxy URL
      // Validate that it looks like a Google Drive file ID (alphanumeric with hyphens)
      if (RegExp(r'^[a-zA-Z0-9_-]{20,}$').hasMatch(url)) {
        urlToLaunch = GoogleDriveService.generateProxyUrl(url);
      } else {
        // Not a valid file ID, try to launch directly
        urlToLaunch = url;
      }
    }

    final uri = Uri.parse(urlToLaunch);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      SnackbarUtils.showErrorSnackBar(context, 'Could not open file');
    }
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
