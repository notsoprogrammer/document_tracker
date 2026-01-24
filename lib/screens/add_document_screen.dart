import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/document.dart';
import '../services/cached_document_service.dart';
import '../services/google_drive_service.dart';
import '../services/upload_queue_manager.dart';
import '../services/auth_service.dart';
import '../utils/snackbar_utils.dart';

class AddDocumentScreen extends StatefulWidget {
  final bool incoming;

  const AddDocumentScreen({super.key, required this.incoming});

  @override
  State<AddDocumentScreen> createState() => _AddDocumentScreenState();
}

class _AddDocumentScreenState extends State<AddDocumentScreen> {
  final ImagePicker _picker = ImagePicker();
  final GoogleDriveService _driveService = GoogleDriveService();
  final codeController = TextEditingController();
  final titleController = TextEditingController();
  String? selectedType;
  final fromToController = TextEditingController();
  String? selectedFrom;
  bool isCustomFrom = false;
  String? selectedMode;
  final assignedToController = TextEditingController();
  String? selectedStatus;
  DateTime? selectedDeadline;
  String? selectedFilePath;
  final remarksController = TextEditingController();
  final personController = TextEditingController();

  // File handling
  List<String> _selectedImagePaths = [];
  List<String> _selectedDocumentPaths = [];
  List<String> _uploadedImageUrls = [];
  List<String> _uploadedDocumentUrls = [];
  bool _isUploadingImages = false;
  bool _isPickingImage = false;
  bool _isPickingFile = false;
  bool _isSaving = false;
  String _uploadStatus = '';
  int _totalUploads = 0;
  int _completedUploads = 0;

  bool _isImage(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext);
  }

  bool _isDocument(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return ['docx', 'pdf'].contains(ext);
  }

  // Validation flags
  bool _showValidationErrors = false;

  final List<String> documentTypes = [
    'Memo',
    'Travel',
    'Transmittal',
    'Executive Order',
    'Letter',
    'Report',
    'Endorsement',
    'Resolution',
    'Voucher/OBR',
    'Others'
  ];

  final List<String> modeOptions = [
    'Hand-carry / Hard copy',
    'Email / Soft copy',
    'Courier'
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
    'DILG',
    'DSHUD',
    'PSA'
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
  final List<String> statusOptions = [
    'Received','Delivered', 'Returned', 'Completed', 'Urgent', 'For Follow-up'
  ];

  @override
  void initState() {
    super.initState();
    codeController.text = _generateCode(widget.incoming);
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
      if (mounted) {
        Navigator.pop(context, null); // Document was already saved
      }
    }
  }

  String _generateCode(bool incoming) {
    final nowUtc = DateTime.now().toUtc();
    final phTime = nowUtc.add(const Duration(hours: 8)); // force UTC+8

    final year = phTime.year;
    final month = phTime.month.toString().padLeft(2, '0');
    final day = phTime.day.toString().padLeft(2, '0');
    final hour = phTime.hour.toString().padLeft(2, '0');
    final minute = phTime.minute.toString().padLeft(2, '0');
    final second = phTime.second.toString().padLeft(2, '0');
    final prefix = incoming ? 'IDL' : 'ODL';

    return '$prefix$year-$month-$day-$hour$minute$second';
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
          child: Container(
            width: MediaQuery.of(context).size.width * 0.8,
            height: MediaQuery.of(context).size.height * 0.8,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                Expanded(
                  child: PageView.builder(
                    itemCount: imageFiles.length,
                    itemBuilder: (context, index) {
                      return InteractiveViewer(
                        child: Image.file(
                          File(imageFiles[index]),
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(child: Text('Failed to load image'));
                          },
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.incoming ? "Add Incoming Document" : "Add Outgoing Document"),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
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
                        const SizedBox(height: 16),
                        TextField(
                          controller: codeController,
                          decoration: InputDecoration(
                            labelText: "Document Code",
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                          ),
                          readOnly: true,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: titleController,
                          decoration: InputDecoration(
                            labelText: "Document Title",
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                            errorText: _showValidationErrors && titleController.text.trim().isEmpty ? "Document title is required" : null,
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: selectedType,
                          decoration: InputDecoration(
                            labelText: "Document Type",
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                            errorText: _showValidationErrors && selectedType == null ? "Document type is required" : null,
                          ),
                          items: documentTypes.map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
                          onChanged: (value) => setState(() => selectedType = value),
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
                          widget.incoming ? "Sender Information" : "Recipient Information",
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (widget.incoming) ...[
                          Autocomplete<String>(
                            optionsBuilder: (TextEditingValue textEditingValue) {
                              if (textEditingValue.text == '') {
                                return const Iterable<String>.empty();
                              }
                              return offices.where((String option) {
                                return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                              });
                            },
                            onSelected: (String selection) {
                              fromToController.text = selection;
                            },
                            fieldViewBuilder: (BuildContext context, TextEditingController fieldTextEditingController, FocusNode fieldFocusNode, VoidCallback onFieldSubmitted) {
                              fieldTextEditingController.text = fromToController.text;
                              return TextField(
                                controller: fieldTextEditingController,
                                focusNode: fieldFocusNode,
                                decoration: InputDecoration(
                                  labelText: "From (Office/Agency/Person)",
                                  hintText: "Start typing to see suggestions",
                                  border: OutlineInputBorder(),
                                  filled: true,
                                  fillColor: Theme.of(context).colorScheme.surface,
                                  errorText: _showValidationErrors && fromToController.text.trim().isEmpty ? "This field is required" : null,
                                ),
                                onChanged: (value) {
                                  fromToController.text = value;
                                },
                              );
                            },
                          ),
                        ] else ...[
                          Autocomplete<String>(
                            optionsBuilder: (TextEditingValue textEditingValue) {
                              if (textEditingValue.text == '') {
                                return const Iterable<String>.empty();
                              }
                              return offices.where((String option) {
                                return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                              });
                            },
                            onSelected: (String selection) {
                              fromToController.text = selection;
                            },
                            fieldViewBuilder: (BuildContext context, TextEditingController fieldTextEditingController, FocusNode fieldFocusNode, VoidCallback onFieldSubmitted) {
                              fieldTextEditingController.text = fromToController.text;
                              return TextField(
                                controller: fieldTextEditingController,
                                focusNode: fieldFocusNode,
                                decoration: InputDecoration(
                                  labelText: "Recipient (Office/Agency/Person)",
                                  hintText: "Start typing to see suggestions",
                                  border: OutlineInputBorder(),
                                  filled: true,
                                  fillColor: Theme.of(context).colorScheme.surface,
                                  errorText: _showValidationErrors && fromToController.text.trim().isEmpty ? "This field is required" : null,
                                ),
                                onChanged: (value) {
                                  fromToController.text = value;
                                },
                              );
                            },
                          ),
                        ],
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: selectedMode,
                          decoration: InputDecoration(
                            labelText: widget.incoming ? "Mode of Receipt" : "Mode of Release",
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                            errorText: _showValidationErrors && selectedMode == null ? "Mode is required" : null,
                          ),
                          items: modeOptions.map((mode) => DropdownMenuItem(value: mode, child: Text(mode))).toList(),
                          onChanged: (value) => setState(() => selectedMode = value),
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
                          widget.incoming ? "Assignment & Attachment" : "Recipient Details",
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (widget.incoming) ...[
                          RawAutocomplete<String>(
                            optionsBuilder: (TextEditingValue textEditingValue) {
                              if (textEditingValue.text == '') {
                                return const Iterable<String>.empty();
                              }
                              return cpdcoStaff.where((String option) {
                                return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                              });
                            },
                            onSelected: (String selection) {
                              assignedToController.text = selection;
                            },
                            fieldViewBuilder: (BuildContext context, TextEditingController fieldTextEditingController, FocusNode fieldFocusNode, VoidCallback onFieldSubmitted) {
                              fieldTextEditingController.text = assignedToController.text;
                              return TextField(
                                controller: fieldTextEditingController,
                                focusNode: fieldFocusNode,
                                decoration: InputDecoration(
                                  labelText: "Delivered / Addressed to",
                                  hintText: "Enter assigned personnel",
                                  border: OutlineInputBorder(),
                                  filled: true,
                                  fillColor: Theme.of(context).colorScheme.surface,
                                ),
                                onChanged: (value) {
                                  assignedToController.text = value;
                                },
                              );
                            },
                            optionsViewBuilder: (BuildContext context, AutocompleteOnSelected<String> onSelected, Iterable<String> options) {
                              return Align(
                                alignment: Alignment.topLeft,
                                child: Material(
                                  elevation: 4.0,
                                  child: SizedBox(
                                    width: 350,
                                    height: (options.length * 56.0 + 16.0).clamp(0.0, 200.0),
                                    child: ListView.builder(
                                      padding: const EdgeInsets.all(8.0),
                                      itemCount: options.length,
                                      itemBuilder: (BuildContext context, int index) {
                                        final String option = options.elementAt(index);
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
                        ] else ...[
                          TextField(
                            controller: assignedToController,
                            decoration: InputDecoration(
                              labelText: "Delivered / Addressed to",
                              hintText: "Enter recipient personnel",
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.surface,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: selectedStatus,
                          decoration: InputDecoration(
                            labelText: "Status",
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                          ),
                          items: statusOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                          onChanged: (value) {
                            setState(() {
                              selectedStatus = value;
                              if (value != 'For Compliance') {
                                selectedDeadline = null; // Clear deadline if not For Compliance
                              }
                            });
                          },
                        ),
                        if (selectedStatus == 'For Compliance') ...[
                          const SizedBox(height: 12),
                          TextField(
                            readOnly: true,
                            controller: TextEditingController(
                              text: selectedDeadline != null
                                  ? "${selectedDeadline!.month}/${selectedDeadline!.day}/${selectedDeadline!.year} ${selectedDeadline!.hour.toString().padLeft(2, '0')}:${selectedDeadline!.minute.toString().padLeft(2, '0')}"
                                  : '',
                            ),
                            decoration: InputDecoration(
                              labelText: "Compliance Deadline",
                              hintText: "Select date and time",
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.surface,
                              suffixIcon: const Icon(Icons.calendar_today),
                              errorText: _showValidationErrors && selectedDeadline == null ? "Deadline is required for For Compliance" : null,
                            ),
                            onTap: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: selectedDeadline ?? DateTime.now(),
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                              );
                              if (date != null) {
                                final time = await showTimePicker(
                                  context: context,
                                  initialTime: selectedDeadline != null ? TimeOfDay.fromDateTime(selectedDeadline!) : const TimeOfDay(hour: 9, minute: 0),
                                );
                                if (time != null) {
                                  setState(() {
                                    selectedDeadline = DateTime(
                                      date.year,
                                      date.month,
                                      date.day,
                                      time.hour,
                                      time.minute,
                                    );
                                  });
                                }
                              }
                            },
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: (_isUploadingImages || _isPickingImage) ? null : () async {
                                  int currentImageCount = _selectedImagePaths.where(_isImage).length;
                                  if (currentImageCount >= 10) {
                                    SnackbarUtils.showErrorSnackBar(context, 'Only 10 image files allowed');
                                    return;
                                  }
                                  setState(() => _isPickingImage = true);
                                  final XFile? image = await _picker.pickImage(source: ImageSource.camera);
                                  if (image != null && image.path.isNotEmpty) {
                                    setState(() {
                                      _selectedImagePaths.add(image.path);
                                      _isPickingImage = false;
                                    });
                                  } else {
                                    setState(() => _isPickingImage = false);
                                    SnackbarUtils.showErrorSnackBar(context, 'No image captured or path empty');
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
                                onPressed: (_isUploadingImages || _isPickingFile) ? null : () async {
                                  setState(() => _isPickingFile = true);
                                  FilePickerResult? result = await FilePicker.platform.pickFiles(
                                    type: FileType.custom,
                                    allowedExtensions: ['docx', 'pdf'],
                                    allowMultiple: false, // Only one document
                                    withData: true, // Ensure bytes are available
                                  );
                                  if (result != null && result.files.isNotEmpty) {
                                    final file = result.files.first;
                                    String? filePath = file.path;
                                    if (filePath == null || filePath.isEmpty) {
                                      if (file.bytes != null) {
                                        // Create a temporary file for platforms that don't provide paths
                                        final tempDir = Directory.systemTemp;
                                        final tempFile = File('${tempDir.path}/${file.name}');
                                        await tempFile.writeAsBytes(file.bytes!);
                                        filePath = tempFile.path;
                                      }
                                    }

                                    if (filePath != null && filePath.isNotEmpty) {
                                      final fileSize = File(filePath).lengthSync();
                                      if (fileSize > 50 * 1024 * 1024) { // 20MB
                                        setState(() => _isPickingFile = false);
                                        SnackbarUtils.showErrorSnackBar(context, '${file.name} exceeds 50MB limit');
                                      } else {
                                        setState(() {
                                          _selectedDocumentPaths.add(filePath!);
                                          _isPickingFile = false;
                                        });
                                      }
                                    } else {
                                      setState(() => _isPickingFile = false);
                                      SnackbarUtils.showErrorSnackBar(context, 'Unable to access file');
                                    }
                                  } else {
                                    setState(() => _isPickingFile = false);
                                    SnackbarUtils.showErrorSnackBar(context, 'No file selected');
                                  }
                                },
                                icon: const Icon(Icons.attach_file),
                                label: const Text("Pick Document"),
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
                            onTap: () => _viewSelectedFiles(context),
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
                            children: _selectedDocumentPaths.map((path) {
                              final fileName = path.split('\\').last.split('/').last;
                              return Chip(
                                label: Text(fileName),
                                onDeleted: () {
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
                          controller: remarksController,
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
                Card(
                  elevation: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Processing Information",
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: personController,
                          decoration: InputDecoration(
                            labelText: "Recorded by",
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
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _isSaving ? null : () async {
                    setState(() {
                      _showValidationErrors = true;
                    });

                    if (titleController.text.trim().isNotEmpty &&
                        selectedType != null &&
                        selectedMode != null &&
                        personController.text.trim().isNotEmpty &&
                        fromToController.text.trim().isNotEmpty &&
                        (selectedStatus != 'For Compliance' || selectedDeadline != null)) {

                      final String code = codeController.text ?? '';
                      final String title = titleController.text ?? '';
                      final String fromOrTo = fromToController.text ?? '';
                      final String assignedTo = assignedToController.text ?? '';
                      final String remarks = remarksController.text ?? '';
                      final String person = personController.text ?? '';

                      final doc = Document(
                        code: code,
                        title: title,
                        type: selectedType!,
                        fromOrTo: fromOrTo,
                        mode: selectedMode!,
                        assignedTo: assignedTo,
                        filePath: null,
                        remarks: remarks,
                        person: person,
                        incoming: widget.incoming,
                        status: selectedStatus ?? (widget.incoming ? 'Received' : 'Delivered'),
                        imageUrls: _uploadedImageUrls,
                        fileUrls: _uploadedDocumentUrls,
                        localImagePaths: _selectedImagePaths,
                        localFilePaths: _selectedDocumentPaths,
                        complianceDeadline: selectedDeadline,
                      );

                      setState(() => _isSaving = true);
                      try {
                        await CachedDocumentService().createDocument(doc);
                        // If no files to upload, pop immediately
                        if (_selectedImagePaths.isEmpty && _selectedDocumentPaths.isEmpty) {
                          if (mounted) {
                            Navigator.pop(context);
                          }
                        }
                        // Otherwise, wait for uploads to complete
                      } catch (e) {
                        SnackbarUtils.showErrorSnackBar(context, 'Failed to save document: $e');
                        if (mounted) setState(() => _isSaving = false);
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  child: _isSaving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("Save Document", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
    );
  }
}
