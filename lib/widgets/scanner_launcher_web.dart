import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../services/document_scanner_service.dart';

/// A button widget that captures an image, runs the full document-scanning
/// pipeline, shows a preview, and returns the processed JPEG bytes via
/// [onScanned].
///
/// On web: opens the system file picker (camera is unavailable).
/// On mobile: lets the user choose between camera and gallery.
///
/// Usage:
/// ```dart
/// ScannerLauncherWeb(
///   onScanned: (bytes) {
///     // bytes is a high-resolution, CamScanner-quality JPEG
///   },
/// )
/// ```
class ScannerLauncherWeb extends StatefulWidget {
  /// Called with the final processed JPEG bytes after user acceptance.
  final void Function(Uint8List bytes)? onScanned;

  /// Optional label override. Defaults to 'Scan Document'.
  final String? label;

  /// Optional icon override. Defaults to [Icons.document_scanner].
  final IconData? icon;

  const ScannerLauncherWeb({
    super.key,
    this.onScanned,
    this.label,
    this.icon,
  });

  @override
  State<ScannerLauncherWeb> createState() => _ScannerLauncherWebState();
}

class _ScannerLauncherWebState extends State<ScannerLauncherWeb> {
  bool _processing = false;

  // ─── Public entry point ───────────────────────────────────────────────────

  Future<void> _launch() async {
    final Uint8List? raw = kIsWeb ? await _pickWeb() : await _pickNative();
    if (raw == null || !mounted) return;

    setState(() => _processing = true);
    try {
      final Uint8List processed = kIsWeb
          ? raw
          : (await DocumentScannerService.processImage(raw) ?? raw);
      if (!mounted) return;
      await _showPreview(processed);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  // ─── Image acquisition ────────────────────────────────────────────────────

  Future<Uint8List?> _pickWeb() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    return result?.files.firstOrNull?.bytes;
  }

  Future<Uint8List?> _pickNative() async {
    final source = await _chooseSource();
    if (source == null) return null;

    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: source,
      imageQuality: 100, // no lossy pre-compression
    );
    return file == null ? null : await file.readAsBytes();
  }

  Future<ImageSource?> _chooseSource() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Select image source',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photo Library'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ─── Preview dialog ───────────────────────────────────────────────────────

  Future<void> _showPreview(Uint8List bytes) async {
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PreviewDialog(bytes: bytes),
    );
    if (accepted == true) widget.onScanned?.call(bytes);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: _processing ? null : _launch,
      icon: _processing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(widget.icon ?? Icons.document_scanner),
      label: Text(_processing ? 'Scanning…' : (widget.label ?? 'Scan Document')),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Preview dialog
// ─────────────────────────────────────────────────────────────────────────────

class _PreviewDialog extends StatelessWidget {
  final Uint8List bytes;

  const _PreviewDialog({required this.bytes});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ─────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.document_scanner, color: Colors.white),
                const SizedBox(width: 8),
                const Text(
                  'Scan Preview',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context, false),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

          // ── Scanned image ───────────────────────────────────────────────
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.55,
            ),
            child: InteractiveViewer(
              minScale: 1.0,
              maxScale: 5.0,
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
              ),
            ),
          ),

          // ── Hint ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(
              'Pinch to zoom • Tap Accept to use this scan',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ),

          const Divider(height: 1),

          // ── Actions ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retake'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.check),
                    label: const Text('Accept'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
