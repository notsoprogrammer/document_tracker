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
import 'package:intl/intl.dart';

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
  final customTypeController = TextEditingController();
  final fromToController = TextEditingController();
  String? selectedFrom;
  bool isCustomFrom = false;
  String? selectedMode;
  final assignedToController = TextEditingController();
  String? selectedStatus;
  DateTime? selectedCalendarDate;
  DateTime? selectedReceivingDate;
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
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp','heif','heic'].contains(ext);
  }

  bool _isDocument(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp','docx', 'pdf'].contains(ext);
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
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.incoming ? "Add Incoming Document" : "Add Outgoing Document"),
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

                        // Document Code + Receiving Date
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
                                initialDate: selectedReceivingDate ?? DateTime.now(),
                                firstDate: DateTime(2025),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                              );
                              if (date != null) {
                                final time = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay.now(),
                                );
                                if (time != null) {
                                  setState(() {
                                    selectedReceivingDate = DateTime(
                                      date.year, date.month,date.day,
                                      time.hour, time.minute,
                                    );
                                  });
                                }
                              }
                            },
                            
                            label: Text(
                              selectedReceivingDate != null
                                  ? " ${DateFormat('MM/dd/yy hh:mm a').format(selectedReceivingDate!)}"
                                  : "Set Receiving Date",
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: selectedReceivingDate != null
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

                        // Document Type + Add to Calendar
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: selectedType,
                                decoration: InputDecoration(
                                  labelText: "Document Type",
                                  border: OutlineInputBorder(),
                                  filled: true,
                                  fillColor: Theme.of(context).colorScheme.surface,
                                  errorText: _showValidationErrors && selectedType == null
                                      ? "Document type is required"
                                      : null,
                                ),
                                items: documentTypes
                                    .map((type) =>
                                        DropdownMenuItem(value: type, child: Text(type)))
                                    .toList(),
                                onChanged: _isSaving
                                    ? null
                                    : (value) => setState(() => selectedType = value),
                              ),
                            ),
                          ],
                        ),

                        if (selectedType == 'Others') ...[
                          const SizedBox(height: 16),
                          TextField(
                            controller: customTypeController,
                            enabled: !_isSaving,
                            decoration: InputDecoration(
                              labelText: "Specify Document Type",
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.surface,
                              errorText: _showValidationErrors &&
                                      customTypeController.text.trim().isEmpty
                                  ? "Custom document type is required"
                                  : null,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5EFE6), // soft background
                            border: Border.all(
                              color: const Color(0xFF6D94C5), // pastel blue border
                              width: 1.2,
                            ),
                            borderRadius: BorderRadius.circular(8), // subtle, not too round
                          ),
                          child: InkWell(
                            onTap: _isSaving ? null : () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: selectedCalendarDate ?? DateTime.now(),
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                              );
                              if (date != null) {
                              final time = await showTimePicker(
                                context: context,
                                initialTime: const TimeOfDay(hour: 8, minute: 0), // 👈 defaults to 8:00 AM
                              );
                                if (time != null) {
                                  setState(() {
                                    selectedCalendarDate = DateTime(
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
                            child: Row(
                              children: [
                                const Icon(Icons.event, color: Color(0xFF6D94C5)),
                                const SizedBox(width: 8),
                                Text(
                                  selectedCalendarDate != null
                                      ? "Set to Calendar: ${selectedCalendarDate!.toLocal().toString().substring(0,16)}"
                                      : "Set to Calendar",
                                  style: TextStyle(
                                    color: const Color(0xFF6D94C5),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
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
                                enabled: !_isSaving,
                                decoration: InputDecoration(
                                  labelText: "From (Office/Agency/Person)",
                                  hintText: "Start typing to see suggestions",
                                  border: OutlineInputBorder(),
                                  filled: true,
                                  fillColor: Theme.of(context).colorScheme.surface,
                                    hintStyle: TextStyle(
                                      color: Colors.grey.shade500,   // softer hint text
                                      fontStyle: FontStyle.italic,   // optional subtlety
                                    ),

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
                                enabled: !_isSaving,
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
                          onChanged: _isSaving ? null : (value) => setState(() => selectedMode = value),
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
                                enabled: !_isSaving,
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
                            enabled: !_isSaving,
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
                          onChanged: _isSaving ? null : (value) {
                            setState(() {
                              selectedStatus = value;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
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
                                onPressed: (_isUploadingImages || _isPickingFile || _isSaving) ? null : () async {
                                  setState(() => _isPickingFile = true);
                                  FilePickerResult? result = await FilePicker.platform.pickFiles(
                                    type: FileType.custom,
                                    allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp','docx', 'pdf'],
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

                    if (titleController.text.trim().isNotEmpty &&
                        selectedType != null &&
                        (selectedType != 'Others' || customTypeController.text.trim().isNotEmpty) &&
                        selectedMode != null &&
                        personController.text.trim().isNotEmpty &&
                        fromToController.text.trim().isNotEmpty){

                      final String code = codeController.text ?? '';
                      final String title = titleController.text ?? '';
                      final String fromOrTo = fromToController.text ?? '';
                      final String assignedTo = assignedToController.text.trim().isNotEmpty ? assignedToController.text.trim() : 'N/A';
                      final String remarks = remarksController.text ?? '';
                      final String person = personController.text ?? '';

                      final doc = Document(
                        code: code,
                        title: title,
                        type: selectedType == 'Others' ? customTypeController.text.trim() : selectedType!,
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
                        fileNames: [],
                        localImagePaths: _selectedImagePaths,
                        localFilePaths: _selectedDocumentPaths,
                        calendarDeadline: selectedCalendarDate,
                        calendarAdded: selectedCalendarDate != null,
                        attachments: [..._selectedImagePaths, ..._selectedDocumentPaths],
                        receivingDate: selectedReceivingDate,
                        history: widget.incoming ? [
                          HistoryEntry(
                            action: 'Document Received',
                            person: person,
                            timestamp: selectedReceivingDate ?? DateTime.now(),
                          )
                        ] : [],
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
      ),
    );
  }
}
