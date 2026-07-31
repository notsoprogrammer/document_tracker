import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/document.dart';
import '../services/cached_document_service.dart';
import '../services/document_scanner_service.dart';
import '../services/mlkit_scanner_service.dart';
import '../services/pdf_export_service.dart';
import '../services/google_drive_service.dart';
import '../services/upload_queue_manager.dart';
import '../services/auth_service.dart';
import '../utils/snackbar_utils.dart';
import '../constants/document_types.dart';
import '../services/supabase_service.dart';
import '../services/notification_service.dart';
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
  DateTime? selectedCalendarEndDate;
  DateTime? selectedReceivingDate;
  String? selectedFilePath;
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
  bool _isUploadingImages = false;
  bool _isPickingImage = false;
  bool _isPickingFile = false;
  bool _isMergingPdf = false;
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
    return ['pdf', 'docx'].contains(ext);
  }

  // Outgoing multi-select assignees
  List<String> _selectedAssignees = [];
  List<String> _availableUsers = [];

  // Validation flags
  bool _showValidationErrors = false;



  final List<String> documentTypes = [
    'Action Slip',
    'Endorsement',
    'Executive Order',
    'Letter',
    'Leave',
    'Memo',
    'Report',
    'Resolution',
    'Request',
    'Ordinance',
    'Travel',
    'Transmittal',
    'Voucher/OBR',
    'Others'
  ];

  final List<String> modeOptions = [
    'Hand-carry / Hard copy',
    'Email / Soft copy',
    'Courier'
  ];

  final List<String> offices = [
    'N/A',
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
  ];
  final List<String> statusOptions = [
    'Received','Delivered', 'Returned', 'Completed', 'Urgent', 'For Follow-up'
  ];

  final List<String> otherDocumentTypes = [
    "AIP",
    "Annual Accomplishment Report",
    "Annual Budget",
    "Barangay – AIP",
    "Barangay – GAD",
    "Cash Advance",
    "CDC – Attendance",
    "CDC – Minutes",
    "CDC – Resolution",
    "Certificate/Attendance",
    "Clean-up Drives",
    "CLUP Zoning Reclassification",
    "CSOs",
    "Dept. Heads Meeting",
    "DTR",
    "Earthquake Drills",
    "Ecological Profile",
    "L&D/IDP/DNA",
    "Liquidation/Reimbursement",
    "Locational Clearance",
    "Man. Com",
    "Monthly Accomplishment Report",
    "Monthly Staff Meeting",
    "OPCR",
    "PFMAR/PFMIP",
    "PR/PPMP",
    "Quarterly Accomplishment Report",
    "Research/Studies/Trainings",
    "Sectoral Plans",
    "Tree Planting",
    "Zoning Certification",
    "Zoning Clearance"
  ];

  @override
  void initState() {
    super.initState();
    selectedReceivingDate = DateTime.now().toUtc().add(const Duration(hours: 8));
    codeController.text = _generateCode(widget.incoming, null);
    _setupUploadListener();
    _loadUsername();
    if (widget.incoming) _loadAvailableUsers();
  }

  Future<void> _loadAvailableUsers() async {
    final users = await SupabaseService().fetchAllUsernames();
    if (mounted) setState(() => _availableUsers = users);
  }

  Future<void> _showAssigneePicker() async {
    final temp = List<String>.from(_selectedAssignees);
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (ctx, setS) {
            final sorted = List<String>.from(_availableUsers)..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
            final filtered = query.isEmpty
                ? sorted
                : sorted
                    .where((u) => u.toLowerCase().contains(query.toLowerCase()))
                    .toList();
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.6,
              minChildSize: 0.4,
              maxChildSize: 0.85,
              builder: (_, scrollController) => Column(
                children: [
                  // Handle bar
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Row(
                      children: [
                        Icon(Icons.people_outline,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 10),
                        Text(
                          'Assign Personnel',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const Spacer(),
                        if (temp.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${temp.length} selected',
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Search field
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      autofocus: false,
                      decoration: InputDecoration(
                        hintText: 'Search personnel...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      ),
                      onChanged: (v) => setS(() => query = v),
                    ),
                  ),
                  const Divider(height: 1),
                  // Pinned N/A option
                  Builder(builder: (_) {
                    final naSelected = temp.contains('N/A');
                    return CheckboxListTile(
                      title: const Text('N/A', style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic)),
                      subtitle: const Text('Not applicable / no specific assignee', style: TextStyle(fontSize: 11)),
                      value: naSelected,
                      activeColor: Colors.grey.shade600,
                      secondary: CircleAvatar(
                        radius: 16,
                        backgroundColor: naSelected ? Colors.grey.shade600 : Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: Icon(Icons.block, size: 15, color: naSelected ? Colors.white : Colors.grey.shade400),
                      ),
                      onChanged: (checked) => setS(() {
                        if (checked == true) {
                          temp
                            ..clear()
                            ..add('N/A');
                        } else {
                          temp.remove('N/A');
                        }
                      }),
                    );
                  }),
                  const Divider(height: 1),
                  // List
                  Expanded(
                    child: _availableUsers.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : filtered.isEmpty
                            ? Center(
                                child: Text(
                                  'No match for "$query"',
                                  style: TextStyle(color: Colors.grey.shade500),
                                ),
                              )
                            : ListView.builder(
                                controller: scrollController,
                                itemCount: filtered.length,
                                itemBuilder: (_, i) {
                                  final user = filtered[i];
                                  final selected = temp.contains(user);
                                  return CheckboxListTile(
                                    title: Text(user,
                                        style: const TextStyle(fontSize: 14)),
                                    value: selected,
                                    activeColor:
                                        Theme.of(context).colorScheme.primary,
                                    secondary: CircleAvatar(
                                      radius: 16,
                                      backgroundColor: selected
                                          ? Theme.of(context).colorScheme.primary
                                          : Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHighest,
                                      child: Text(
                                        user[0].toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: selected
                                              ? Colors.white
                                              : Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                    onChanged: (checked) => setS(() {
                                      if (checked == true) {
                                        temp
                                          ..remove('N/A')
                                          ..add(user);
                                      } else {
                                        temp.remove(user);
                                      }
                                    }),
                                  );
                                },
                              ),
                  ),
                  const Divider(height: 1),
                  // Actions
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        16, 12, 16, 12 + MediaQuery.of(ctx).viewInsets.bottom),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.pop(ctx, temp),
                            child: const Text('Confirm'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (result != null) {
      setState(() {
        _selectedAssignees = result;
        assignedToController.text = result.join(', ');
      });
    }
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

    // If all uploads are done and we were saving, pop the screen
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
    // Android: delegate to the ML Kit native scanner (multi-page, auto-detect).
    // Falls back to the camera + custom CV pipeline when ML Kit is unavailable.
    if (!kIsWeb && Platform.isAndroid) {
      await _scanWithMlKit();
      return;
    }

    // Web / iOS: let user choose Camera or Gallery before capturing.
    final ImageSource? source = await _chooseWebScanSource();
    if (source == null || !mounted) return;

    final int currentImageCount = _selectedImagePaths.where(_isImage).length;
    if (currentImageCount >= 20) {
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

    // Run the full document-scanning pipeline; fall back to the raw capture on failure
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

  /// Android-only: launches the ML Kit Document Scanner native UI.
  /// Prompts the user to choose Image or PDF output before scanning.
  /// Supports multi-page capture, automatic edge detection and perspective
  /// correction. Falls back to camera + CV pipeline on error.
  Future<void> _scanWithMlKit() async {
    final int remaining = 20 - _selectedImagePaths.where(_isImage).length;
    if (remaining <= 0) {
      SnackbarUtils.showErrorSnackBar(context, 'Maximum 20 images allowed');
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
      final int currentImageCount = _selectedImagePaths.where(_isImage).length;
      if (currentImageCount >= 20) {
        SnackbarUtils.showErrorSnackBar(context, 'Maximum 20 images allowed');
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

  String _generateCode(bool incoming, String? docType) {
    final nowUtc = DateTime.now().toUtc();
    final phTime = nowUtc.add(const Duration(hours: 8));

    final year = phTime.year;
    final month = phTime.month.toString().padLeft(2, '0');
    final day = phTime.day.toString().padLeft(2, '0');
    final hour = phTime.hour.toString().padLeft(2, '0');
    final minute = phTime.minute.toString().padLeft(2, '0');
    final second = phTime.second.toString().padLeft(2, '0');

    final prefix = incoming ? 'IDL' : 'ODL';

    String typeCode = '';
    if (docType != null && docType.isNotEmpty) {
      if (typeMapping.containsKey(docType)) {
        typeCode = typeMapping[docType]!;
      } else {
        // Use 'OTH' for custom types not in the mapping
        typeCode = 'OTH';
      }
      typeCode = '-$typeCode';
    }

    return '$prefix$typeCode-$year$month$day-$hour$minute$second';
  }

  void _viewSelectedFiles(BuildContext context) async {
    if (_selectedImagePaths.isNotEmpty) {
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
                            if (_selectedImagePaths.isNotEmpty) {
                              final currentIndex = _pageController.page?.round() ?? 0;
                              final removedPath = _selectedImagePaths[currentIndex];
                              // Remove from upload queue
                              final queueManager = UploadQueueManager();
                              queueManager.removeFromQueue(codeController.text, removedPath);
                              setState(() {
                                _selectedImagePaths.removeAt(currentIndex);
                              });
                              setStateDialog(() {
                                // Trigger rebuild
                              });
                              if (_selectedImagePaths.isEmpty) {
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
                        itemCount: _selectedImagePaths.length,
                        itemBuilder: (context, index) {
                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              InteractiveViewer(
                                child: Image.file(
                                  File(_selectedImagePaths[index]),
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
                              if (index < _selectedImagePaths.length - 1)
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

    for (final filePath in _selectedDocumentPaths) {
      final normalizedPath = filePath.replaceAll('\\', '/');
      final uri = Uri.file(normalizedPath);
      if (await launchUrl(uri)) {
        // Successfully launched
      } else {
        SnackbarUtils.showErrorSnackBar(context, 'Could not open file: ${filePath.split('\\').last.split('/').last}');
      }
    }

    if (_selectedImagePaths.isEmpty && _selectedDocumentPaths.isEmpty) {
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
                                    : (value) {
                                        setState(() {
                                          selectedType = value;
                                          // Update code when type changes
                                          String? docType = selectedType;
                                          if (selectedType == 'Others') {
                                            String custom = customTypeController.text.trim();
                                            docType = custom.isNotEmpty ? custom : 'Others';
                                          }
                                          codeController.text = _generateCode(widget.incoming, docType);
                                          if (selectedType == 'Others') {
                                            WidgetsBinding.instance.addPostFrameCallback((_) {
                                              
                                            });
                                          }
                                        });
                                      },
                              ),
                            ),
                          ],
                        ),

                        if (selectedType == 'Others') ...[
                          const SizedBox(height: 16),
                          Autocomplete<String>(
                            optionsBuilder: (TextEditingValue textEditingValue) {
                              if (textEditingValue.text.isEmpty) {
                                return otherDocumentTypes;
                              }
                              return otherDocumentTypes.where((String option) {
                                return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                              });
                            },
                            onSelected: (String selection) {
                              customTypeController.text = selection;
                              if (selectedType == 'Others') {
                                setState(() {
                                  codeController.text = _generateCode(widget.incoming, selection.trim());
                                });
                              }
                            },
                            fieldViewBuilder: (BuildContext context, TextEditingController fieldTextEditingController, FocusNode fieldFocusNode, VoidCallback onFieldSubmitted) {
                              fieldTextEditingController.text = customTypeController.text;
                              return TextField(
                                controller: fieldTextEditingController,
                                focusNode: fieldFocusNode,
                                enabled: !_isSaving,
                                decoration: InputDecoration(
                                  labelText: "Specify Document Type",
                                  hintText: "Type or select from list",
                                  border: OutlineInputBorder(),
                                  filled: true,
                                  fillColor: Theme.of(context).colorScheme.surface,
                                  errorText: _showValidationErrors &&
                                          customTypeController.text.trim().isEmpty
                                      ? "Custom document type is required"
                                      : null,
                                ),
                                onChanged: (value) {
                                  customTypeController.text = value;
                                  // Update code when custom type changes
                                  if (selectedType == 'Others') {
                                    setState(() {
                                      codeController.text = _generateCode(widget.incoming, value.trim());
                                    });
                                  }
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
                        ],
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5EFE6), // soft background
                            border: Border.all(
                              color: _showValidationErrors && selectedReceivingDate == null
                                  ? Colors.red
                                  : const Color(0xFF6D94C5), // pastel blue border or red if error
                              width: 1.2,
                            ),
                            borderRadius: BorderRadius.circular(8), // subtle, not too round
                          ),
                          child: InkWell(
                            onTap: _isSaving ? null : () async {
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
                            child: Row(
                              children: [
                                Icon(
                                  Icons.event,
                                  color: _showValidationErrors && selectedReceivingDate == null
                                      ? Colors.red
                                      : const Color(0xFF6D94C5),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        selectedReceivingDate != null
                                            ? "Receiving Date: ${DateFormat('MM/dd/yy hh:mm a').format(selectedReceivingDate!)}"
                                            : "Set Receiving Date",
                                        style: TextStyle(
                                          color: _showValidationErrors && selectedReceivingDate == null
                                              ? Colors.red
                                              : const Color(0xFF6D94C5),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        'Tap to change if needed',
                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_showValidationErrors && selectedReceivingDate == null) ...[
                          const SizedBox(height: 4),
                          const Text(
                            "Receiving date is required",
                            style: TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        ]
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
                                return offices; // Show all options on tap
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
                          InkWell(
                            onTap: _isSaving ? null : _showAssigneePicker,
                            borderRadius: BorderRadius.circular(8),
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: "Delivered / Addressed to",
                                border: const OutlineInputBorder(),
                                filled: true,
                                fillColor: Theme.of(context).colorScheme.surface,
                                prefixIcon: const Icon(Icons.people_outline, size: 20),
                                suffixIcon: Icon(
                                  Icons.arrow_drop_down,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                              ),
                              child: _selectedAssignees.isEmpty
                                  ? Text(
                                      'Tap to select personnel',
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                                        fontStyle: FontStyle.italic,
                                        fontSize: 14,
                                      ),
                                    )
                                  : Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: _selectedAssignees
                                          .map((a) {
                                            final isNA = a == 'N/A';
                                            return Chip(
                                              avatar: CircleAvatar(
                                                backgroundColor: isNA ? Colors.grey.shade500 : Theme.of(context).colorScheme.primary,
                                                child: isNA
                                                    ? const Icon(Icons.block, size: 12, color: Colors.white)
                                                    : Text(
                                                        a[0].toUpperCase(),
                                                        style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                                                      ),
                                              ),
                                              label: Text(a, style: TextStyle(fontSize: 12, fontStyle: isNA ? FontStyle.italic : FontStyle.normal)),
                                              backgroundColor: isNA ? Colors.grey.shade200 : Theme.of(context).colorScheme.primaryContainer,
                                              labelStyle: TextStyle(color: isNA ? Colors.grey.shade700 : Theme.of(context).colorScheme.onPrimaryContainer),
                                              padding: const EdgeInsets.symmetric(horizontal: 4),
                                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            );
                                          })
                                          .toList(),
                                    ),
                            ),
                          ),
                        ] else ...[
                          TextField(
                            controller: assignedToController,
                            enabled: !_isSaving,
                            decoration: InputDecoration(
                              labelText: "Delivered / Addressed to",
                              hintText: "Enter recipient name",
                              border: const OutlineInputBorder(),
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
                                          if (!_selectedImagePaths.contains(filePath)) {
                                            _selectedImagePaths.add(filePath);
                                            imagesAdded++;
                                          }
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
                                          if (!_selectedDocumentPaths.contains(filePath)) {
                                            _selectedDocumentPaths.add(filePath);
                                            documentsAdded++;
                                          }
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

                    if (titleController.text.trim().isNotEmpty &&
                        selectedType != null &&
                        (selectedType != 'Others' || customTypeController.text.trim().isNotEmpty) &&
                        selectedMode != null &&
                        personController.text.trim().isNotEmpty &&
                        fromToController.text.trim().isNotEmpty &&
                        selectedReceivingDate != null){

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
                        calendarDeadlineEnd: selectedCalendarEndDate,
                        calendarAdded: selectedCalendarDate != null,
                        receivingDate: selectedReceivingDate,
                        referenceLink: referenceLinkController.text.trim().isNotEmpty ? referenceLinkController.text.trim() : null,
                        history: widget.incoming ? [
                          HistoryEntry(
                            action: 'Document Received',
                            person: person,
                            timestamp: selectedReceivingDate ?? DateTime.now(),
                          )
                        ] : [],
                      );

                      final navigator = Navigator.of(context);
                      final messenger = ScaffoldMessenger.of(context);
                      setState(() => _isSaving = true);
                      try {
                        await CachedDocumentService().createDocument(doc);
                        CachedDocumentService().processPendingUploads();
                        // Schedule a 1-hour-before reminder if this document has a calendar deadline.
                        NotificationService().scheduleDocumentReminder(doc);
                        final notifyAssignees = _selectedAssignees.where((a) => a != 'N/A').toList();
                        if (widget.incoming && notifyAssignees.isNotEmpty) {
                          try {
                            await SupabaseService().scheduleAssignmentNotification(
                              doc.code,
                              doc.title ?? 'Document',
                              notifyAssignees,
                            );
                          } catch (e) {
                            messenger.showSnackBar(SnackBar(
                              content: Text('Notification scheduling failed: $e'),
                              backgroundColor: Colors.red,
                            ));
                          }
                        }
                        _saved = true;
                        navigator.pop();
                      } catch (e) {
                        messenger.showSnackBar(SnackBar(
                          content: Text('Failed to save document: $e'),
                          backgroundColor: Colors.red,
                        ));
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
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.withValues(alpha: 0.22)),
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
                                    : 'Saving document...',
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
                              backgroundColor: Colors.blue.withValues(alpha: 0.15),
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
