import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/document.dart';
import '../services/cached_document_service.dart';
import '../services/google_drive_service.dart';
import '../services/upload_queue_manager.dart';
import '../services/auth_service.dart';
import '../utils/snackbar_utils.dart';
class AddFlagCeremonyScreen extends StatefulWidget {
  const AddFlagCeremonyScreen({super.key});

  @override
  State<AddFlagCeremonyScreen> createState() => _AddFlagCeremonyScreenState();
}

class _AddFlagCeremonyScreenState extends State<AddFlagCeremonyScreen> {
  final ImagePicker _picker = ImagePicker();
  final GoogleDriveService _driveService = GoogleDriveService();
  final codeController = TextEditingController();
  String? selectedCeremonyType;
  DateTime? selectedDate;
  final remarksController = TextEditingController();
  final personController = TextEditingController();

  // File handling
  List<String> _selectedImagePaths = [];
  List<String> _selectedDocumentPaths = [];
  List<List<int>?> _selectedImageBytes = []; // For web camera images
  List<String> _uploadedImageUrls = [];
  List<String> _uploadedDocumentUrls = [];
  bool _isUploadingImages = false;
  bool _isPickingImage = false;
  bool _isPickingFile = false;
  String _uploadStatus = '';
  int _totalUploads = 0;
  int _completedUploads = 0;

  bool _isImage(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp','heic'].contains(ext);
  }

  bool _isDocument(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return ['pdf', 'docx'].contains(ext);
  }

  // Validation flags
  bool _showValidationErrors = false;
  bool _isSaving = false;

  final List<String> ceremonyTypes = [
    'Flag Raising',
    'Flag Lowering',
  ];

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

    // If all uploads are done and we were saving, pop the screen
    if (_isSaving && pendingUploads.isEmpty && uploadingUploads.isEmpty) {
      _isSaving = false;
      Navigator.pop(context, null); // Document was already saved
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
    if (selectedCeremonyType == null || selectedDate == null) return '-';

    // Force PH timezone (UTC+8) if needed
    final nowUtc = DateTime.now().toUtc();
    final phTime = nowUtc.add(const Duration(hours: 8));

    final month = selectedDate!.month.toString().padLeft(2, '0');
    final day = selectedDate!.day.toString().padLeft(2, '0');
    final year = selectedDate!.year.toString();
    final hour = phTime.hour.toString().padLeft(2, '0');
    final minute = phTime.minute.toString().padLeft(2, '0');
    final second = phTime.second.toString().padLeft(2, '0');

    final prefix = selectedCeremonyType == 'Flag Raising' ? 'FR' : 'FL';

    return '$prefix-$month-$day-$year-$hour$minute$second';
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

  void _onCeremonyTypeChanged(String? value) {
    setState(() {
      selectedCeremonyType = value;
      codeController.text = _generateCode();
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Add Flag Ceremony Record"),
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
                        DropdownButtonFormField<String>(
                          value: selectedCeremonyType,
                          decoration: InputDecoration(
                            labelText: "Ceremony Type",
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                            errorText: _showValidationErrors && selectedCeremonyType == null ? "Ceremony type is required" : null,
                          ),
                          items: ceremonyTypes.map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
                          onChanged: _isSaving ? null : _onCeremonyTypeChanged,
                        ),
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: _isSaving ? null : () => _selectDate(context),
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: "Ceremony Date",
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.surface,
                              errorText: _showValidationErrors && selectedDate == null ? "Ceremony date is required" : null,
                              suffixIcon: const Icon(Icons.calendar_today),
                            ),
                            child: Text(
                              selectedDate != null
                                  ? "${selectedDate!.month}/${selectedDate!.day}/${selectedDate!.year}"
                                  : "Select date",
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
                                onPressed: (_isUploadingImages || _isPickingImage || _isSaving) ? null : () async {
                                  int currentImageCount = _selectedImagePaths.where(_isImage).length;
                                  if (currentImageCount >= 10) {
                                    SnackbarUtils.showWarningSnackBar(context, 'Only 10 image files allowed');
                                    return;
                                  }
                                  setState(() => _isPickingImage = true);
                                  final XFile? image = await _picker.pickImage(source: ImageSource.camera);
                                  if (image != null) {
                                    // For web, read bytes; for mobile, use path
                                    if (kIsWeb) {
                                      final bytes = await image.readAsBytes();
                                      final fileName = 'web_image_${DateTime.now().millisecondsSinceEpoch}.jpg';
                                      setState(() {
                                        _selectedImagePaths.add(fileName);
                                        _selectedImageBytes.add(bytes);
                                        _isPickingImage = false;
                                      });
                                      // Queue for upload
                                      final queueManager = UploadQueueManager();
                                      queueManager.addWebCameraImageToQueue(
                                        documentCode: codeController.text,
                                        filePath: fileName,
                                        bytes: bytes,
                                      );
                                    } else {
                                      if (image.path.isNotEmpty) {
                                        setState(() {
                                          _selectedImagePaths.add(image.path);
                                          _selectedImageBytes.add(null); // No bytes for mobile
                                          _isPickingImage = false;
                                        });
                                        // Queue for upload
                                        final queueManager = UploadQueueManager();
                                        queueManager.addToQueue(
                                          documentCode: codeController.text,
                                          filePath: image.path,
                                          isImage: true,
                                          localPath: image.path,
                                        );
                                      } else {
                                        setState(() => _isPickingImage = false);
                                        SnackbarUtils.showErrorSnackBar(context, 'No image captured or path empty');
                                      }
                                    }
                                  } else {
                                    setState(() => _isPickingImage = false);
                                    SnackbarUtils.showErrorSnackBar(context, 'No image captured');
                                  }
                                },
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
                                onPressed: (_isUploadingImages || _isPickingFile || _isSaving) ? null : () async {
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
                                          // Store bytes for web files
                                          // Note: _webFileBytes is not defined in this screen, need to add it
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
                                            bytes: kIsWeb ? null : null, // Web bytes handling not implemented in this screen
                                          );
                                        } else if (_isDocument(file.name)) {
                                          if (fileSize > 50 * 1024 * 1024) {
                                            skippedFiles.add(file.name);
                                            continue;
                                          }
                                          int currentTotalSize = _selectedDocumentPaths.fold(0, (sum, path) {
                                            if (kIsWeb) {
                                              // For web files, we can't easily get size from path, skip size check for now
                                              return 0;
                                            } else {
                                              return sum + File(path).lengthSync();
                                            }
                                          });
                                          if (!kIsWeb && currentTotalSize + fileSize > 50 * 1024 * 1024) {
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
                                            bytes: kIsWeb ? null : null, // Web bytes handling not implemented in this screen
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
                            "${_selectedDocumentPaths.length} file(s) selected",
                            style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _selectedDocumentPaths.map((path) {
                              final fileName = path.split('\\').last.split('/').last;
                              return Chip(
                                label: Text(fileName),
                                onDeleted: _isSaving ? null : () {
                                  setState(() => _selectedDocumentPaths.remove(path));
                                },
                              );
                            }).toList(),
                          ),
                        ],
                        if (_isPickingImage) ...[
                          const SizedBox(height: 8),
                          const LinearProgressIndicator(),
                          const Text("Capturing image..."),
                        ],
                        if (_isPickingFile) ...[
                          const SizedBox(height: 8),
                          const LinearProgressIndicator(),
                          const Text("Selecting file..."),
                        ],
                        if (_isUploadingImages) ...[
                          const SizedBox(height: 8),
                          const LinearProgressIndicator(),
                          const Text("Uploading images to Google Drive..."),
                        ],
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

                    if (selectedCeremonyType != null && selectedDate != null && personController.text.trim().isNotEmpty) {
                      final String code = codeController.text;
                      final String ceremonyType = selectedCeremonyType!;
                      final String dateStr = "${selectedDate!.month}/${selectedDate!.day}/${selectedDate!.year}";
                      final String remarks = remarksController.text;
                      final String person = personController.text;

                      final doc = Document(
                        code: code,
                        type: ceremonyType,
                        fromOrTo: dateStr,
                        mode: 'Flag Ceremony',
                        assignedTo: person,
                        filePath: null,
                        remarks: remarks,
                        person: person,
                        incoming: false, // Flag ceremony is neither incoming nor outgoing
                        status: 'Completed',
                        imageUrls: _uploadedImageUrls,
                        fileUrls: _uploadedDocumentUrls,
                        localImagePaths: _selectedImagePaths,
                        localFilePaths: _selectedDocumentPaths,
                      );

                      setState(() => _isSaving = true);
                      try {
                        // Create document first
                        await CachedDocumentService().createDocument(doc);

                        // Process pending uploads (files were already queued when selected)
                        final documentService = CachedDocumentService();
                        await documentService.processPendingUploads();

                        // Wait a bit for uploads to complete and check status
                        await Future.delayed(const Duration(seconds: 2));

                        // Check if there are still any pending uploads for this document
                        final queueManager = UploadQueueManager();
                        final pendingUploads = queueManager.getPendingUploads(code);
                        final uploadingUploads = queueManager.getAllItems().where((item) =>
                          item['documentCode'] == code && item['status'] == 'uploading'
                        ).toList();

                        if (pendingUploads.isNotEmpty || uploadingUploads.isNotEmpty) {
                          SnackbarUtils.showWarningSnackBar(context, 'Cannot save document while uploads are pending. Please wait for all uploads to complete.');
                          return;
                        }

                        // Fetch the updated document to get the Google Drive file names
                        final allDocs = await documentService.fetchDocuments();
                        final updatedDoc = allDocs.firstWhere((doc) => doc.code == code);
                        final newAttachmentCount = _selectedImagePaths.length + _selectedDocumentPaths.length;
                        // Safety check to prevent negative start index
                        final startIndex = updatedDoc.fileNames.length - newAttachmentCount;
                        final googleDriveFileNames = startIndex >= 0 ? updatedDoc.fileNames.sublist(startIndex) : [];

                        // Update remarks with attachment names if any files were uploaded
                        if (googleDriveFileNames.isNotEmpty) {
                          final attachmentNames = googleDriveFileNames.join(', ');
                          final updatedRemarks = remarks.isNotEmpty
                            ? '$remarks\nAttachment: $attachmentNames'
                            : 'Attachment: $attachmentNames';

                          await documentService.updateDocument(code, {
                            'remarks': updatedRemarks,
                          });
                        }

                        // Add history entry for uploads if files were attached
                        if (googleDriveFileNames.isNotEmpty) {
                          final username = await AuthService.getUsername();
                          if (username != null) {
                            await documentService.addHistoryEntry(
                              code,
                              HistoryEntry(
                                action: 'Files Uploaded',
                                person: username,
                                timestamp: DateTime.now(),
                                notes: 'Uploaded ${googleDriveFileNames.length} file(s): ${googleDriveFileNames.join(', ')}',
                              ),
                            );
                          }
                        }

                        // Sync the document
                        await documentService.syncSpecificDocument(code);

                        if (mounted) {
                          Navigator.pop(context);
                        }
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
                      : const Text("Save Record", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
}
