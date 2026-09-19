import 'package:flutter/material.dart';
import '../models/note.dart';

/// An append-only notes thread.
///
/// Anyone signed in can add a note; only the note's author can edit or delete
/// it. Replaces the old single free-text remarks field, where adding a comment
/// meant editing whatever someone else had already written.
///
/// Purely presentational — it hands the updated list back through [onChanged]
/// and lets the caller persist it.
class NotesThread extends StatefulWidget {
  final List<Note> notes;
  final String? currentUsername;

  /// Called with the full updated list whenever a note is added, edited or
  /// deleted. The caller persists it and is expected to rebuild with the
  /// new list.
  final Future<void> Function(List<Note> updated) onChanged;

  /// Heading shown above the thread.
  final String label;

  /// Hides the composer (e.g. on read-only views).
  final bool readOnly;

  const NotesThread({
    super.key,
    required this.notes,
    required this.currentUsername,
    required this.onChanged,
    this.label = 'Remarks',
    this.readOnly = false,
  });

  @override
  State<NotesThread> createState() => _NotesThreadState();
}

class _NotesThreadState extends State<NotesThread> {
  bool _saving = false;

  String _formatStamp(DateTime dt) {
    // Legacy notes carry no real date — don't show a misleading 1970.
    if (dt.millisecondsSinceEpoch == 0) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${dt.month}/${dt.day}/${dt.year} $hour12:$minute $ampm';
  }

  Future<void> _apply(List<Note> updated) async {
    setState(() => _saving = true);
    try {
      await widget.onChanged(updated);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Shared composer dialog for both adding and editing, so the two paths
  /// always look and behave the same.
  Future<String?> _promptForText({
    required String title,
    required String confirmLabel,
    String initialText = '',
  }) async {
    final controller = TextEditingController(text: initialText);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          minLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Write a remark…',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _addNote() async {
    final author = widget.currentUsername;
    if (author == null || author.isEmpty) return;

    final text = await _promptForText(
      title: 'Add remark',
      confirmLabel: 'Add',
    );
    if (text == null || text.isEmpty) return;

    await _apply([...widget.notes, Note.create(text: text, author: author)]);
  }

  Future<void> _editNote(Note note) async {
    final result = await _promptForText(
      title: 'Edit remark',
      confirmLabel: 'Save',
      initialText: note.text,
    );
    if (result == null || result.isEmpty || result == note.text) return;

    final updated = widget.notes
        .map((n) => n.id == note.id
            ? n.copyWith(text: result, editedAt: DateTime.now())
            : n)
        .toList();
    await _apply(updated);
  }

  Future<void> _deleteNote(Note note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete note?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _apply(widget.notes.where((n) => n.id != note.id).toList());
  }

  Widget _buildNote(Note note) {
    final theme = Theme.of(context);
    final canEdit = !widget.readOnly && note.canEdit(widget.currentUsername);
    final stamp = _formatStamp(note.createdAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  children: [
                    Text(
                      note.isLegacy ? 'Original remarks' : note.author,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    if (stamp.isNotEmpty)
                      Text(stamp,
                          style:
                              TextStyle(fontSize: 10, color: Colors.grey[600])),
                    if (note.wasEdited)
                      Text('(edited)',
                          style: TextStyle(
                              fontSize: 10,
                              fontStyle: FontStyle.italic,
                              color: Colors.grey[600])),
                  ],
                ),
              ),
              if (canEdit) ...[
                InkWell(
                  onTap: _saving ? null : () => _editNote(note),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.edit_outlined,
                        size: 15, color: Colors.grey[600]),
                  ),
                ),
                InkWell(
                  onTap: _saving ? null : () => _deleteNote(note),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.delete_outline,
                        size: 15, color: Colors.grey[600]),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(note.text, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canCompose = !widget.readOnly &&
        (widget.currentUsername?.isNotEmpty ?? false);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.comment, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.primary,
                      fontSize: 12,
                    ),
                  ),
                  if (_saving) ...[
                    const SizedBox(width: 8),
                    const SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(strokeWidth: 1.5)),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              if (widget.notes.isEmpty)
                Text(
                  'No remarks yet',
                  style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey[500]),
                )
              else
                ...widget.notes.map(_buildNote),

              // Anyone signed in may append a remark, without touching anyone
              // else's. Opens a dialog so the detail panel stays compact.
              if (canCompose)
                InkWell(
                  onTap: _saving ? null : _addNote,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_comment_outlined,
                            size: 15, color: theme.colorScheme.primary),
                        const SizedBox(width: 4),
                        Text('Add remark',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
