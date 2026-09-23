import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../config/supabase_config.dart';
import '../models/document.dart';
import '../services/auth_service.dart';
import '../services/cached_document_service.dart';
import '../services/document_scanner_service.dart';
import '../services/google_drive_service.dart';
import 'scrollable_image_viewer.dart';
import '../services/mlkit_scanner_service.dart';
import '../services/upload_queue_manager.dart';
import '../utils/snackbar_utils.dart';

/// Add-only attachment entry point.
///
/// Anyone may contribute images/files to a document they did not create — the
/// uploader is recorded per file when the upload completes, and only that
/// person can remove what they added (see [Document.canModifyAttachment]).
/// This deliberately offers no edit/remove, so contributors never touch the
/// original inputter's attachments.
class AddAttachmentButton extends StatefulWidget {
  final Document document;

  /// Called once files have been queued, so the host screen can refresh.
  final VoidCallback? onQueued;

  /// Compact icon button (document rows) vs. a labelled button.
  final bool iconOnly;

  const AddAttachmentButton({
    super.key,
    required this.document,
    this.onQueued,
    this.iconOnly = true,
  });

  @override
  State<AddAttachmentButton> createState() => _AddAttachmentButtonState();
}

class _AddAttachmentButtonState extends State<AddAttachmentButton> {
  static const int _maxBytes = 50 * 1024 * 1024;
  static const int _maxImages = 20;
  final ImagePicker _picker = ImagePicker();
  bool _picking = false;
  String? _username;
  /// URLs ticked for bulk deletion in the sheet.
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    AuthService.getUsername().then((name) {
      if (mounted) setState(() => _username = name);
    });
  }

  /// Rough headroom against the 20-image cap, based on what is already saved.
  int get _remainingImages => _maxImages - widget.document.imageUrls.length;

  /// Attachments on this document that the signed-in user uploaded, and may
  /// therefore remove. Everyone else's — including the original inputter's —
  /// are never listed here.
  List<({String url, bool isImage, String name})> get _myAttachments {
    final doc = widget.document;
    final mine = <({String url, bool isImage, String name})>[];

    for (var i = 0; i < doc.imageUrls.length; i++) {
      final url = doc.imageUrls[i];
      if (!doc.canModifyAttachment(url, _username)) continue;
      mine.add((
        url: url,
        isImage: true,
        name: i < doc.fileNames.length ? doc.fileNames[i] : 'Image ${i + 1}',
      ));
    }
    for (var i = 0; i < doc.fileUrls.length; i++) {
      final url = doc.fileUrls[i];
      if (!doc.canModifyAttachment(url, _username)) continue;
      final nameIndex = doc.imageUrls.length + i;
      mine.add((
        url: url,
        isImage: false,
        name: nameIndex < doc.fileNames.length ? doc.fileNames[nameIndex] : 'File ${i + 1}',
      ));
    }
    return mine;
  }

  /// Removes one of the user's own attachments from the document and Drive.
  Future<void> _removeAttachment(String url, bool isImage) async {
    final doc = widget.document;
    if (!doc.canModifyAttachment(url, _username)) return;

    final images = [...doc.imageUrls];
    final files = [...doc.fileUrls];
    final names = [...doc.fileNames];
    String removedName = isImage ? 'image' : 'file';

    if (isImage) {
      final i = images.indexOf(url);
      if (i < 0) return;
      images.removeAt(i);
      if (i < names.length) removedName = names.removeAt(i);
    } else {
      final i = files.indexOf(url);
      if (i < 0) return;
      // File names are stored after the image names
      final nameIndex = doc.imageUrls.length + i;
      files.removeAt(i);
      if (nameIndex < names.length) removedName = names.removeAt(nameIndex);
    }

    final uploaders = Map<String, String>.from(doc.attachmentUploaders)
      ..remove(Document.attachmentKey(url));

    try {
      await CachedDocumentService().updateDocument(doc.code, {
        'image_urls': images,
        'file_urls': files,
        'file_names': names,
        'attachment_uploaders': uploaders,
      });
      await CachedDocumentService().deleteAttachmentFromDrive(url);

      // Keep the in-memory document in step so the row updates immediately
      doc.imageUrls
        ..clear()
        ..addAll(images);
      doc.fileUrls
        ..clear()
        ..addAll(files);
      doc.fileNames
        ..clear()
        ..addAll(names);
      doc.attachmentUploaders
        ..clear()
        ..addAll(uploaders);

      // Record the removal in the document history
      try {
        await CachedDocumentService().addHistoryEntry(
          doc.code,
          HistoryEntry(
            action: isImage ? 'Image Removed' : 'File Removed',
            person: _username ?? 'Unknown',
            timestamp: DateTime.now(),
            notes: removedName,
          ),
        );
      } catch (e) {
        // History is best-effort
      }

      if (!mounted) return;
      setState(() => _selected.remove(url));
      widget.onQueued?.call();
    } catch (e) {
      if (mounted) SnackbarUtils.showErrorSnackBar(context, 'Could not remove attachment');
    }
  }

  bool _isImage(String name) {
    final n = name.toLowerCase();
    return n.endsWith('.jpg') || n.endsWith('.jpeg') || n.endsWith('.png') ||
        n.endsWith('.gif') || n.endsWith('.bmp') || n.endsWith('.webp');
  }

  /// Queues one captured/scanned image, handling the web-vs-native split.
  Future<void> _queueImageBytes(List<int> bytes, String label) async {
    if (kIsWeb) {
      final fileName = '${label}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      UploadQueueManager().addWebCameraImageToQueue(
        documentCode: widget.document.code,
        filePath: fileName,
        bytes: bytes,
      );
    } else {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/${label}_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(bytes);
      UploadQueueManager().addToQueue(
        documentCode: widget.document.code,
        filePath: tempFile.path,
        isImage: true,
        localPath: tempFile.path,
      );
    }
  }

  void _reportQueued(int count) {
    if (!mounted || count <= 0) return;
    SnackbarUtils.showSuccessSnackBar(
      context,
      '$count attachment(s) uploading — only you can remove them',
    );
    // Start immediately rather than leaving the files for whichever screen the
    // user opens next, or the five-minute auto-sync tick. The snackbar says
    // "uploading", so it had better be true.
    CachedDocumentService().processPendingUploads();
    widget.onQueued?.call();
  }

  /// ML Kit multi-page document scanner (Android only), same as the add/edit
  /// screens. Falls back to a plain camera capture if the scanner is missing.
  Future<void> _scanWithMlKit() async {
    final remaining = _remainingImages;
    if (remaining <= 0) {
      SnackbarUtils.showErrorSnackBar(context, 'Maximum $_maxImages images allowed');
      return;
    }

    setState(() => _picking = true);
    try {
      ScannerOutput? output;
      try {
        output = await MlKitScannerService.scanDocument(
          maxPages: remaining,
          format: ScanOutputFormat.image,
        );
      } catch (_) {
        output = null;
      }

      if (output == null) {
        // Scanner unavailable — fall back to the camera
        await _capturePhoto(ImageSource.camera, alreadyBusy: true);
        return;
      }
      if (output.wasCancelled) return;

      for (final image in output.images) {
        await _queueImageBytes(image, 'mlkit');
      }
      _reportQueued(output.images.length);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  /// Camera / gallery capture, run through the auto-crop scanner on native.
  Future<void> _capturePhoto(ImageSource source, {bool alreadyBusy = false}) async {
    if (_remainingImages <= 0) {
      SnackbarUtils.showErrorSnackBar(context, 'Maximum $_maxImages images allowed');
      return;
    }
    if (!alreadyBusy) setState(() => _picking = true);
    try {
      final image = await _picker.pickImage(source: source, imageQuality: 85, maxWidth: 1920, maxHeight: 1920);
      if (image == null) return;

      final rawBytes = await image.readAsBytes();
      final scannedBytes = kIsWeb
          ? rawBytes
          : (await DocumentScannerService.processImage(rawBytes) ?? rawBytes);

      await _queueImageBytes(scannedBytes, 'scanned');
      _reportQueued(1);
    } catch (e) {
      if (mounted) SnackbarUtils.showErrorSnackBar(context, 'Could not capture image');
    } finally {
      if (!alreadyBusy && mounted) setState(() => _picking = false);
    }
  }

  /// Thumbnail (or file icon) with a delete badge, used in the sheet's
  /// "Your attachments" strip. Tapping an image opens the full-screen viewer.
  Widget _attachmentTile(
    ({String url, bool isImage, String name}) item, {
    required VoidCallback onRemoved,
  }) {
    final preview = item.isImage
        ? CachedNetworkImage(
            imageUrl: GoogleDriveService.generateProxyUrl(
              GoogleDriveService.normalizeFileId(item.url),
            ),
            httpHeaders: {'Authorization': 'Bearer ${SupabaseConfig.supabaseAnonKey}'},
            width: double.infinity,
            height: 200,
            fit: BoxFit.cover,
            placeholder: (_, _) => const SizedBox(
              height: 200,
              child: Center(
                child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ),
            errorWidget: (_, _, _) => SizedBox(
              height: 200,
              child: Center(child: Icon(Icons.broken_image_outlined, color: Colors.grey[400], size: 32)),
            ),
          )
        : SizedBox(
            height: 90,
            child: Center(
              child: Icon(
                item.name.toLowerCase().endsWith('.pdf')
                    ? Icons.picture_as_pdf_outlined
                    : Icons.description_outlined,
                size: 40,
                color: Colors.blueGrey,
              ),
            ),
          );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: item.isImage
                ? () => ScrollableImageViewer.show(context, imageUrls: [item.url])
                : null,
            child: preview,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
            child: Row(
              children: [
                // Tick to include this one in a bulk delete
                Checkbox(
                  value: _selected.contains(item.url),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (checked) {
                    setState(() {
                      if (checked == true) {
                        _selected.add(item.url);
                      } else {
                        _selected.remove(item.url);
                      }
                    });
                    onRemoved(); // refresh the sheet
                  },
                ),
                Expanded(
                  child: Text(
                    item.name,
                    style: const TextStyle(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _confirmRemove([item], onRemoved),
                  icon: const Icon(Icons.delete_outline, size: 17),
                  label: const Text('Delete', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Typed "y" confirmation, matching how deleting a document works elsewhere.
  /// Handles one attachment or a whole selection.
  Future<void> _confirmRemove(
    List<({String url, bool isImage, String name})> items,
    VoidCallback onRemoved,
  ) async {
    if (items.isEmpty) return;
    final controller = TextEditingController();
    bool confirmed = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final canConfirm = controller.text.trim().toLowerCase() == 'y';
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.delete_forever, color: Colors.red[700]),
                const SizedBox(width: 8),
                const Text('Confirm Deletion'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  items.length == 1
                      ? 'Are you sure you want to delete "${items.first.name}"?'
                      : 'Are you sure you want to delete these ${items.length} attachments?',
                  style: const TextStyle(fontSize: 15),
                ),
                if (items.length > 1) ...[
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 120),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: items
                            .map((i) => Text('• ${i.name}',
                                style: const TextStyle(fontSize: 12, color: Colors.grey)))
                            .toList(),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Type "y" to confirm, "n" to cancel',
                    border: OutlineInputBorder(),
                    helperText: 'Also deleted from Google Drive — cannot be undone',
                  ),
                  maxLength: 1,
                  autofocus: true,
                  onChanged: (_) => setDialogState(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: canConfirm
                    ? () {
                        confirmed = true;
                        Navigator.pop(ctx);
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[700],
                  foregroundColor: Colors.white,
                ),
                child: Text(items.length == 1 ? 'Confirm Delete' : 'Delete ${items.length}'),
              ),
            ],
          );
        },
      ),
    );

    if (!confirmed) return;
    for (final item in items) {
      await _removeAttachment(item.url, item.isImage);
    }
    if (mounted) {
      SnackbarUtils.showSuccessSnackBar(
        context,
        items.length == 1 ? 'Attachment removed' : '${items.length} attachments removed',
      );
    }
    onRemoved();
  }

  Future<void> _chooseSource() async {
    final canScan = !kIsWeb && Platform.isAndroid;
    _selected.clear();
    final choice = await showModalBottomSheet<String>(
      context: context,
      // Scrollable sheet: the options plus the attachment strip can outgrow a
      // small screen, especially in landscape
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      // StatefulBuilder so removing a thumbnail refreshes the strip in place
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
        final mine = _myAttachments;
        return SafeArea(
        child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Add image / file',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
            if (canScan)
              ListTile(
                leading: const Icon(Icons.document_scanner_outlined, color: Colors.teal),
                title: const Text('Scan document'),
                subtitle: const Text('Auto-crop, multiple pages'),
                onTap: () => Navigator.pop(ctx, 'scan'),
              ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: Colors.blue),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: Colors.purple),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file, color: Colors.orange),
              title: const Text('Choose files'),
              subtitle: const Text('PDF, DOCX or images'),
              onTap: () => Navigator.pop(ctx, 'files'),
            ),
            // Only what this user uploaded can be removed here
            if (mine.isNotEmpty) ...[
              const Divider(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Your attachments (${mine.length}) — tap an image to enlarge',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                    // Bulk delete for everything ticked
                    if (_selected.isNotEmpty)
                      TextButton.icon(
                        onPressed: () => _confirmRemove(
                          mine.where((i) => _selected.contains(i.url)).toList(),
                          () => setSheetState(() {}),
                        ),
                        icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                        label: Text('Delete ${_selected.length}',
                            style: const TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ],
                ),
              ),
              // Vertical list of large previews — the sheet itself scrolls,
              // so this just lays out and never nests two scrollables
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: mine.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _attachmentTile(
                  mine[i],
                  onRemoved: () => setSheetState(() {}),
                ),
              ),
            ],
            const SizedBox(height: 12),
          ],
        ),
        ),
        );
        },
      ),
    );

    if (choice == null || !mounted) return;

    switch (choice) {
      case 'scan':
        await _scanWithMlKit();
        break;
      case 'camera':
        await _capturePhoto(ImageSource.camera);
        break;
      case 'gallery':
        await _capturePhoto(ImageSource.gallery);
        break;
      case 'files':
        await _pickAndQueue();
        break;
    }
  }

  Future<void> _pickAndQueue() async {
    if (_picking) return;
    setState(() => _picking = true);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'docx', 'pdf'],
        allowMultiple: true,
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty) return;

      final queue = UploadQueueManager();
      final skipped = <String>[];
      int queued = 0;

      for (final file in result.files) {
        String? filePath;
        int size = 0;
        List<int>? bytes;

        if (kIsWeb) {
          if (file.bytes == null) continue;
          bytes = file.bytes!;
          size = bytes.length;
          filePath = 'web_file_${DateTime.now().millisecondsSinceEpoch}_${file.name}';
        } else {
          filePath = file.path;
          if (filePath == null || filePath.isEmpty) continue;
          size = File(filePath).lengthSync();
        }

        if (size <= 0) continue;
        if (size > _maxBytes) {
          skipped.add(file.name);
          continue;
        }

        queue.addToQueue(
          documentCode: widget.document.code,
          filePath: filePath,
          isImage: _isImage(file.name),
          localPath: filePath,
          bytes: bytes,
        );
        queued++;
      }

      if (!mounted) return;
      if (skipped.isNotEmpty) {
        SnackbarUtils.showErrorSnackBar(
          context,
          'Skipped (over 50MB): ${skipped.join(', ')}',
        );
      }
      _reportQueued(queued);
    } catch (e) {
      if (mounted) SnackbarUtils.showErrorSnackBar(context, 'Could not add attachment');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.iconOnly) {
      return IconButton(
        icon: _picking
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add_photo_alternate_outlined, size: 20),
        tooltip: 'Add image / file',
        onPressed: _picking ? null : _chooseSource,
      );
    }
    return ElevatedButton.icon(
      onPressed: _picking ? null : _chooseSource,
      icon: _picking
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.add_photo_alternate_outlined, size: 18),
      label: const Text('Add image / file'),
    );
  }
}
