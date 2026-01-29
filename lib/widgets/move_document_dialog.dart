import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../models/document.dart';
import '../services/cached_document_service.dart';
import '../services/auth_service.dart';
import '../utils/date_time_utils.dart';
import '../utils/snackbar_utils.dart';
import '../services/upload_queue_manager.dart';

class MoveDocumentDialog extends StatefulWidget {
  final Document document;
  final String moveAction; // 'Move to Outgoing' or 'Move to Incoming'
  final VoidCallback onDocumentMoved;

  const MoveDocumentDialog({
    super.key,
    required this.document,
    required this.moveAction,
    required this.onDocumentMoved,
  });

  @override
  State<MoveDocumentDialog> createState() => _MoveDocumentDialogState();
}

class _MoveDocumentDialogState extends State<MoveDocumentDialog> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _remarksController = TextEditingController();
  List<String> _selectedImagePaths = [];
  List<String> _selectedFilePaths = [];
  bool _isLoading = false;
  String? _username;

  @override
  void initState() {
    super.initState();
    _loadUsername();
  }

  Future<void> _loadUsername() async {
    final username = await AuthService.getUsername();
    if (mounted) {
      setState(() {
        _username = username;
      });
    }
  }

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.camera);
      if (image != null && mounted) {
        setState(() {
          _selectedImagePaths.add(image.path);
        });
      }
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showErrorSnackBar(context, 'Failed to capture image');
      }
    }
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'pdf', 'docx'],
        allowMultiple: true,
      );
      if (result != null && result.files.isNotEmpty && mounted) {
        setState(() {
          _selectedFilePaths.addAll(result.files.map((file) => file.path!).where((path) => path.isNotEmpty));
        });
      }
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showErrorSnackBar(context, 'Failed to pick files');
      }
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImagePaths.removeAt(index);
    });
  }

  void _removeFile(int index) {
    setState(() {
      _selectedFilePaths.removeAt(index);
    });
  }

  Future<void> _moveDocument() async {
    if (_remarksController.text.trim().isEmpty) {
      SnackbarUtils.showErrorSnackBar(context, 'Remarks are required');
      return;
    }

    if (_username == null || _username!.isEmpty) {
      SnackbarUtils.showErrorSnackBar(context, 'User not authenticated');
      return;
    }

    // Check if there are any pending uploads for this document
    final queueManager = UploadQueueManager();
    final pendingUploads = queueManager.getPendingUploads(widget.document.code);
    final uploadingUploads = queueManager.getAllItems().where((item) => item['documentCode'] == widget.document.code && item['status'] == 'uploading').toList();

    if (pendingUploads.isNotEmpty || uploadingUploads.isNotEmpty) {
      SnackbarUtils.showErrorSnackBar(context, 'Cannot move document while uploads are pending. Please wait for all uploads to complete.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Create updated document with new remarks and images
      final updatedRemarksList = List<String>.from(widget.document.remarksList)
        ..add('Remark ${widget.document.remarksList.length + 1}: ${_remarksController.text.trim()}');

      final updatedImageUrls = List<String>.from(widget.document.imageUrls);
      final updatedFileUrls = List<String>.from(widget.document.fileUrls);
      final updatedFileNames = List<String>.from(widget.document.fileNames);
      final updatedLocalImagePaths = List<String>.from(widget.document.localImagePaths)
        ..addAll(_selectedImagePaths);
      final updatedLocalFilePaths = List<String>.from(widget.document.localFilePaths)
        ..addAll(_selectedFilePaths);

      // Update flow stage
      String newFlowStage;
      if (widget.moveAction == 'Move to Outgoing') {
        newFlowStage = 'outgoing';
      } else {
        newFlowStage = 'incoming';
      }

      final updatedDocument = widget.document.copyWith(
        remarksList: updatedRemarksList,
        localImagePaths: updatedLocalImagePaths,
        localFilePaths: updatedLocalFilePaths,
        flowStage: newFlowStage,
      );

      // Add history entry for the move
      updatedDocument.addHistoryEntry(
        widget.moveAction.replaceFirst('Move to', 'Moved to'),
        _username!,
        notes: 'Remarks: ${_remarksController.text.trim()}',
      );

      // Add history entry for added remark
      updatedDocument.addHistoryEntry(
        'Added Remark ${updatedRemarksList.length}',
        _username!,
      );

      // Update document in database
      final documentService = CachedDocumentService();
      await documentService.updateDocument(widget.document.code, {
        'flow_stage': newFlowStage,
        'remarks_list': updatedRemarksList,
        'local_image_paths': updatedLocalImagePaths,
        'local_file_paths': updatedLocalFilePaths,
      });

      // Add history entries
      for (var entry in updatedDocument.history.where((h) => !widget.document.history.contains(h))) {
        await documentService.addHistoryEntry(widget.document.code, entry);
      }

      if (mounted) {
        SnackbarUtils.showSuccessSnackBar(context, 'Document moved successfully');
        Navigator.of(context).pop();
        widget.onDocumentMoved();
      }
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showErrorSnackBar(context, 'Failed to move document: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: SingleChildScrollView(
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.swap_horiz,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.moveAction,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Document: ${widget.document.type} - ${widget.document.title}',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _remarksController,
                decoration: InputDecoration(
                  labelText: 'Remarks *',
                  hintText: 'Enter remarks for this move',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                maxLines: 3,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _pickImage,
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Take Photo'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _pickFile,
                      icon: const Icon(Icons.attach_file),
                      label: const Text('Pick Files'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              if (_selectedImagePaths.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'New Images: ${_selectedImagePaths.length}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _selectedImagePaths.asMap().entries.map((entry) {
                    final index = entry.key;
                    final path = entry.value;
                    final fileName = path.split('/').last.split('\\').last;
                    return Chip(
                      label: Text(fileName, style: const TextStyle(fontSize: 12)),
                      onDeleted: _isLoading ? null : () => _removeImage(index),
                    );
                  }).toList(),
                ),
              ],
              if (_selectedFilePaths.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'New Files: ${_selectedFilePaths.length}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _selectedFilePaths.asMap().entries.map((entry) {
                    final index = entry.key;
                    final path = entry.value;
                    final fileName = path.split('/').last.split('\\').last;
                    return Chip(
                      label: Text(fileName, style: const TextStyle(fontSize: 12)),
                      onDeleted: _isLoading ? null : () => _removeFile(index),
                    );
                  }).toList(),
                ),
              ],
              if (widget.document.imageUrls.isNotEmpty || widget.document.fileUrls.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Existing Attachments',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.blue.shade700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Images: ${widget.document.imageUrls.length}, Files: ${widget.document.fileUrls.length}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'All existing attachments will be preserved.',
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: Colors.blue.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _moveDocument,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(widget.moveAction),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
