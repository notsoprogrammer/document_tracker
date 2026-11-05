import 'package:flutter/material.dart';
import '../models/document.dart';
import '../services/auth_service.dart';
import '../services/cached_document_service.dart';
import '../utils/date_time_utils.dart';
import '../utils/document_filters.dart';
import '../utils/snackbar_utils.dart';

/// One destination the Change-folder action offers.
class _FolderTarget {
  final String label;

  /// The `mode` value that puts a document in this folder, or null for
  /// Incoming/Outgoing, which are not mode-based.
  final String? mode;

  /// Set for Incoming/Outgoing, which are selected by `flow_stage`.
  final String? flowStage;

  const _FolderTarget(this.label, {this.mode, this.flowStage});
}

const List<_FolderTarget> _targets = [
  _FolderTarget('Incoming', flowStage: 'incoming'),
  _FolderTarget('Outgoing', flowStage: 'outgoing'),
  _FolderTarget('Function MOVs', mode: 'Office Function MOVs'),
  _FolderTarget('CDC Documents', mode: 'CDC Documents'),
  _FolderTarget('SP Documents', mode: 'SP Documents'),
  _FolderTarget('Other Resolutions', mode: 'Resolutions'),
  _FolderTarget('Reclassification', mode: 'Reclassification'),
  _FolderTarget('Locational & Zoning', mode: 'Locational & Zoning'),
];

/// Modes offered when a document is moved into Incoming or Outgoing, where
/// `mode` means the mode of receipt rather than a folder name.
const List<String> _receiptModes = [
  'Hand-carry / Hard copy',
  'Email / Soft copy',
  'Courier',
];

/// Refiles a document into a different folder.
///
/// A document's folder is decided by [Document.mode] for the six mode-based
/// folders and by `flow_stage` for Incoming/Outgoing, and until now nothing in
/// the app wrote either after creation — a document added from the wrong Add
/// screen was stuck there for good.
class ChangeFolderButton extends StatefulWidget {
  final Document document;

  /// Called after a successful move so the screen can reload; the document's
  /// `mode` is final, so the row cannot be updated in place.
  final VoidCallback? onChanged;

  const ChangeFolderButton({
    super.key,
    required this.document,
    this.onChanged,
  });

  @override
  State<ChangeFolderButton> createState() => _ChangeFolderButtonState();
}

class _ChangeFolderButtonState extends State<ChangeFolderButton> {
  String? _username;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    AuthService.getUsername().then((name) {
      if (mounted) setState(() => _username = name);
    });
  }

  /// The target the document currently sits in, so the dialog can preselect it
  /// and refuse a no-op move.
  _FolderTarget get _current {
    final byMode =
        _targets.where((t) => t.mode != null && t.mode == widget.document.mode);
    if (byMode.isNotEmpty) return byMode.first;
    // Flag Ceremony documents live in the Function MOVs folder alongside
    // 'Office Function MOVs'.
    if (widget.document.mode == 'Flag Ceremony') {
      return _targets.firstWhere((t) => t.label == 'Function MOVs');
    }
    return isIncomingDocument(widget.document) ? _targets.first : _targets[1];
  }

  Future<void> _open() async {
    if (_busy) return;

    final choice = await showDialog<_MoveChoice>(
      context: context,
      builder: (_) => _ChangeFolderDialog(
        document: widget.document,
        current: _current,
      ),
    );
    if (choice == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final updates = <String, dynamic>{};
      if (choice.target.flowStage != null) {
        updates['flow_stage'] = choice.target.flowStage;
        // Incoming/Outgoing reuse `mode` for the mode of receipt, so the
        // folder name it held has to be replaced with a real one.
        updates['mode'] = choice.receiptMode ?? _receiptModes.first;
      } else {
        updates['mode'] = choice.target.mode;
      }

      final service = CachedDocumentService();
      await service.updateDocument(widget.document.code, updates);
      await service.addHistoryEntry(
        widget.document.code,
        HistoryEntry(
          action: 'Moved to ${choice.target.label}',
          person: _username ?? 'Unknown',
          timestamp: getPhilippineTime(),
        ),
      );

      if (!mounted) return;
      setState(() => _busy = false);
      SnackbarUtils.showSuccessSnackBar(
          context, 'Moved to ${choice.target.label}');
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      SnackbarUtils.showErrorSnackBar(context, 'Could not move document: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Change folder',
      child: ElevatedButton(
        onPressed: _busy ? null : _open,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color.fromARGB(255, 108, 117, 134),
          foregroundColor: Colors.white,
          minimumSize: const Size(40, 36),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.drive_file_move_outlined, size: 18),
      ),
    );
  }
}

class _MoveChoice {
  final _FolderTarget target;
  final String? receiptMode;
  const _MoveChoice(this.target, this.receiptMode);
}

class _ChangeFolderDialog extends StatefulWidget {
  final Document document;
  final _FolderTarget current;

  const _ChangeFolderDialog({required this.document, required this.current});

  @override
  State<_ChangeFolderDialog> createState() => _ChangeFolderDialogState();
}

class _ChangeFolderDialogState extends State<_ChangeFolderDialog> {
  late _FolderTarget _selected = widget.current;
  late String _receiptMode = _receiptModes.contains(widget.document.mode)
      ? widget.document.mode
      : _receiptModes.first;

  bool get _needsReceiptMode => _selected.flowStage != null;
  bool get _isNoop => _selected.label == widget.current.label;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change folder'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.document.code} is in ${widget.current.label}.',
                style: const TextStyle(fontSize: 12.5, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              for (final t in _targets)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    t.label == _selected.label
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: t.label == _selected.label
                        ? Theme.of(context).colorScheme.primary
                        : Colors.black38,
                  ),
                  title: Text(t.label, style: const TextStyle(fontSize: 13.5)),
                  onTap: () => setState(() => _selected = t),
                ),
              if (_needsReceiptMode) ...[
                const SizedBox(height: 8),
                const Text(
                  'Mode of receipt',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                // Incoming/Outgoing documents store the mode of receipt in the
                // same field that names a folder, so one has to be chosen.
                DropdownButtonFormField<String>(
                  initialValue: _receiptMode,
                  isDense: true,
                  items: _receiptModes
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _receiptMode = v ?? _receiptMode),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isNoop
              ? null
              : () => Navigator.pop(
                    context,
                    _MoveChoice(
                        _selected, _needsReceiptMode ? _receiptMode : null),
                  ),
          child: const Text('Move'),
        ),
      ],
    );
  }
}
