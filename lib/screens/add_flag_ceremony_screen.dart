import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/document.dart';
import '../services/google_drive_service.dart';

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
  String? selectedPerson;
  bool isCustomPerson = false;

  // File handling
  List<String> _selectedImagePaths = [];
  List<String> _selectedDocumentPaths = [];
  List<String> _uploadedImageUrls = [];
  List<String> _uploadedDocumentUrls = [];
  bool _isUploadingImages = false;

  bool _isImage(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext);
  }

  bool _isDocument(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return ['pdf', 'jpg', 'jpeg', 'png'].contains(ext);
  }

  // Validation flags
  bool _showValidationErrors = false;

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
  }

  String _generateCode() {
    if (selectedCeremonyType == null || selectedDate == null) return '-'; // Default format

    final month = selectedDate!.month.toString().padLeft(2, '0');
    final day = selectedDate!.day.toString().padLeft(2, '0');
    final year = selectedDate!.year.toString();

    final prefix = selectedCeremonyType == 'Flag Raising' ? 'FR' : 'FL';

    return '$prefix-$month-$day-$year';
  }

  void _viewSelectedFiles(BuildContext context) async {
    final imageFiles = _selectedImagePaths.where((path) {
      final parts = path.split('.');
      if (parts.length <= 1) return false;
      final extension = parts.last.toLowerCase();
      return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(extension);
    }).toList();

    final otherFiles = _selectedImagePaths.where((path) {
      final parts = path.split('.');
      if (parts.length <= 1) return true;
      final extension = parts.last.toLowerCase();
      return !['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(extension);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file: ${filePath.split('\\').last.split('/').last}')),
        );
      }
    }

    if (imageFiles.isEmpty && otherFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No files selected to view')),
      );
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
    return Scaffold(
      appBar: AppBar(
        title: const Text("Add Flag Ceremony Document"),
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
                          onChanged: _onCeremonyTypeChanged,
                        ),
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: () => _selectDate(context),
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
                                onPressed: _isUploadingImages ? null : () async {
                                  int currentImageCount = _selectedImagePaths.where(_isImage).length;
                                  if (currentImageCount >= 10) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Only 10 image files allowed')),
                                    );
                                    return;
                                  }
                                  final XFile? image = await _picker.pickImage(source: ImageSource.camera);
                                  if (image != null && image.path.isNotEmpty) {
                                    setState(() => _selectedImagePaths.add(image.path));
                                    // ScaffoldMessenger.of(context).showSnackBar(
                                    //   SnackBar(content: Text('Image added: ${image.path.split('\\').last}')),
                                    // );
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('No image captured or path empty')),
                                    );
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
                                onPressed: _isUploadingImages ? null : () async {
                                  FilePickerResult? result = await FilePicker.platform.pickFiles(
                                    type: FileType.custom,
                                    allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
                                    allowMultiple: false,
                                    withData: true,
                                  );
                                  if (result != null && result.files.isNotEmpty) {
                                    final file = result.files.first;
                                    String? filePath = file.path;
                                    if (filePath == null || filePath.isEmpty) {
                                      if (file.bytes != null) {
                                        final tempDir = Directory.systemTemp;
                                        final tempFile = File('${tempDir.path}/${file.name}');
                                        await tempFile.writeAsBytes(file.bytes!);
                                        filePath = tempFile.path;
                                      }
                                    }

                                    if (filePath != null && filePath.isNotEmpty) {
                                      final fileSize = File(filePath).lengthSync();
                                      if (fileSize > 50 * 1024 * 1024) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('${file.name} exceeds 50MB limit')),
                                        );
                                      } else {
                                        setState(() => _selectedDocumentPaths.add(filePath!));
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('File added: ${file.name}')),
                                        );
                                      }
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Unable to access file')),
                                      );
                                    }
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('No file selected')),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.attach_file),
                                label: const Text("Pick File"),
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
                        Autocomplete<String>(
                          optionsBuilder: (TextEditingValue textEditingValue) {
                            if (textEditingValue.text == '') {
                              return const Iterable<String>.empty();
                            }
                            return cpdcoStaff.where((String option) {
                              return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                            });
                          },
                          onSelected: (String selection) {
                            personController.text = selection;
                          },
                          fieldViewBuilder: (BuildContext context, TextEditingController fieldTextEditingController, FocusNode fieldFocusNode, VoidCallback onFieldSubmitted) {
                            fieldTextEditingController.text = personController.text;
                            return TextField(
                              controller: fieldTextEditingController,
                              focusNode: fieldFocusNode,
                              decoration: InputDecoration(
                                labelText: "Recorded by",
                                hintText: "Start typing to see suggestions",
                                border: OutlineInputBorder(),
                                filled: true,
                                fillColor: Theme.of(context).colorScheme.surface,
                                errorText: _showValidationErrors && personController.text.trim().isEmpty ? "This field is required" : null,
                              ),
                              onChanged: (value) {
                                personController.text = value;
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _isUploadingImages ? null : () async {
                    setState(() {
                      _showValidationErrors = true;
                    });
 {

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

                      Navigator.pop(context, doc);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  child: _isUploadingImages
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("Save Flag Ceremony Document", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
