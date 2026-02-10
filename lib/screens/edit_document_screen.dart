import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/document.dart';
import '../services/cached_document_service.dart';
import '../services/google_drive_service.dart';
import '../services/upload_queue_manager.dart';
import '../services/auth_service.dart';
import '../utils/snackbar_utils.dart';
import '../config/supabase_config.dart';

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

                        // Document Code (read-only)
                        Text(
                          widget.document.code,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),

                        const Divider(height: 14),

                        // Title
                        TextField(
                          controller: titleController,
                          enabled: !_isSaving,
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
                        ),

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
                        if (_currentImageUrls.isNotEmpty || _currentFileUrls.isNotEmpty) ...[
                          Text(
                            "Existing Attachments:",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          ..._currentImageUrls.asMap().entries.map((entry) {
                            final index = entry.key;
                            final url = entry.value;
                            final fileName = index < _currentFileNames.length
                                ? _currentFileNames[index]
                                : 'Image ${index + 1}';
                            return ListTile(
                              leading: Icon(Icons.image),
                              title: Text(fileName),
                              onTap: () => _viewExistingImage(context, widget.document, index),
                              trailing: IconButton(
                                icon: Icon(Icons.remove),
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Remove Attachment'),
                                      content: Text('Are you sure you want to remove "$fileName"? This will delete it from Google Drive as well.'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, false),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, true),
                                          child: const Text('Remove'),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (confirm == true) {
                                    setState(() {
                                      _currentImageUrls.removeAt(index);
                                      if (index < _currentFileNames.length) {
                                        _currentFileNames.removeAt(index);
                                      }
                                    });

                                    // Delete from Google Drive and update databases
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
                          }),
                          ..._currentFileUrls.asMap().entries.map((entry) {
                            final index = entry.key;
                            final url = entry.value;
                            final fileName = (_currentFileNames.length > _currentImageUrls.length + index)
                                ? _currentFileNames[_currentImageUrls.length + index]
                                : 'Document ${index + 1}';
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
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, false),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, true),
                                          child: const Text('Remove'),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (confirm == true) {
                                    setState(() {
                                      _currentFileUrls.removeAt(index);
                                      final nameIndex = _currentImageUrls.length + index;
                                      if (nameIndex < _currentFileNames.length) {
                                        _currentFileNames.removeAt(nameIndex);
                                      }
                                    });

                                    // Delete from Google Drive and update databases
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
                          }),
                          const SizedBox(height: 16),
                        ],

                        // Add New Attachments
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: (_isUploadingImages || _isPickingImage || _isSaving) ? null : () async {
                                  int currentImageCount = _selectedImagePaths.where(_isImage).length;
                                  if (currentImageCount >= 10) {
                                    SnackbarUtils.showErrorSnackBar(context, 'Only 10 image files allowed');
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
                                        documentCode: widget.document.code,
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
                                          documentCode: widget.document.code,
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
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 30),
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
                    icon: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 30),
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
