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
  final Function(String) syncDocument;

  const MoveDocumentDialog({
    super.key,
    required this.document,
    required this.moveAction,
    required this.onDocumentMoved,
    required this.syncDocument,
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

  bool _isImage(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp','heif','heic'].contains(ext);
  }

  bool _isDocument(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp','docx', 'pdf'].contains(ext);
  }

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
        allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp','docx', 'pdf'],
        allowMultiple: true,
        withData: false,
      );
      if (result != null && result.files.isNotEmpty && mounted) {
        int imagesAdded = 0;
        int documentsAdded = 0;
        List<String> skippedFiles = [];
        for (final file in result.files) {
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
            } else if (_isDocument(file.name)) {
              if (fileSize > 50 * 1024 * 1024) {
                skippedFiles.add(file.name);
                continue;
              }
              int currentTotalSize = _selectedFilePaths.fold(0, (sum, path) => sum + File(path).lengthSync());
              if (currentTotalSize + fileSize > 50 * 1024 * 1024) {
                SnackbarUtils.showErrorSnackBar(context, '${file.name} would exceed 50MB total limit. Consider using Drive Link instead.');
                continue;
              }
              _selectedFilePaths.add(filePath);
              documentsAdded++;
            }
          }
        }
        setState(() {});
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

    setState(() {
      _isLoading = true;
    });

    List<String> googleDriveFileNames = [];

    try {
      // First, add newly selected files to upload queue
      final queueManager = UploadQueueManager();
      for (final imagePath in _selectedImagePaths) {
        queueManager.addToQueue(
          documentCode: widget.document.code,
          filePath: imagePath,
          isImage: true,
          localPath: imagePath,
        );
      }
      for (final filePath in _selectedFilePaths) {
        queueManager.addToQueue(
          documentCode: widget.document.code,
          filePath: filePath,
          isImage: false,
          localPath: filePath,
        );
      }

      // Then process all pending uploads (including newly added ones)
      final documentService = CachedDocumentService();
      await documentService.processPendingUploads();

      // Wait a bit for uploads to complete and check status
      await Future.delayed(const Duration(seconds: 2));

      // Check if there are still any pending uploads for this document
      final pendingUploads = queueManager.getPendingUploads(widget.document.code);
      final uploadingUploads = queueManager.getAllItems().where((item) => item['documentCode'] == widget.document.code && item['status'] == 'uploading').toList();

      if (pendingUploads.isNotEmpty || uploadingUploads.isNotEmpty) {
        SnackbarUtils.showErrorSnackBar(context, 'Cannot move document while uploads are pending. Please wait for all uploads to complete.');
        return;
      }

      // Fetch the updated document to get the Google Drive file names
      final allDocs = await documentService.fetchDocuments();
      final updatedDoc = allDocs.firstWhere((doc) => doc.code == widget.document.code);
      final newAttachmentCount = _selectedImagePaths.length + _selectedFilePaths.length;
      // Safety check to prevent negative start index
      final startIndex = updatedDoc.fileNames.length - newAttachmentCount;
      googleDriveFileNames = startIndex >= 0 ? updatedDoc.fileNames.sublist(startIndex) : [];
    } catch (e) {
      SnackbarUtils.showErrorSnackBar(context, 'Failed to upload files: $e');
      return;
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }

    try {
      // Create updated document with new remarks and images
      String remarkText = 'Remark ${widget.document.remarksList.length + 1}: ${_remarksController.text.trim()}';
      if (googleDriveFileNames.isNotEmpty) {
        final attachmentNames = googleDriveFileNames.join(', ');
        remarkText += '\nAttachment: $attachmentNames';
      }
      final updatedRemarksList = List<String>.from(widget.document.remarksList)
        ..add(remarkText);

      final updatedImageUrls = List<String>.from(widget.document.imageUrls);
      final updatedFileUrls = List<String>.from(widget.document.fileUrls);
      final updatedFileNames = List<String>.from(widget.document.fileNames)
        ..addAll(_selectedImagePaths.map((p) => p.split('/').last.split('\\').last))
        ..addAll(_selectedFilePaths.map((p) => p.split('/').last.split('\\').last));
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

      // Add history entry for added remark
      updatedDocument.addHistoryEntry(
        'Added Remark ${updatedRemarksList.length}',
        _username!,
      );

      // Update the local document's history immediately for UI update
      for (var entry in updatedDocument.history.where((h) => !widget.document.history.contains(h))) {
        widget.document.history.add(entry);
      }

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
            // Add history entry for the move
      String moveNotes = 'Remarks: ${_remarksController.text.trim()}';
      updatedDocument.addHistoryEntry(
        widget.moveAction.replaceFirst('Move to', 'Moved to'),
        _username!,
        notes: moveNotes,
      );

      // Sync the document before completing the move
      await widget.syncDocument(widget.document.code);

      if (mounted) {
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
