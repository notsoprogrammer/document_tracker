import 'dart:convert';

/// A single note/remark entry on a document or activity.
///
/// Notes are an append-only thread: anyone can add one, but only the author
/// can edit or delete their own. Replaces the old single free-text "remarks"
/// field, which forced users to edit existing text just to add a comment.
class Note {
  /// Stable identifier so a note can be edited or deleted without relying on
  /// its position in the list (which shifts as others are added/removed).
  final String id;
  final String text;

  /// Username of whoever wrote it. Legacy remarks migrated from the old
  /// single-field format use [legacyAuthor].
  final String author;
  final DateTime createdAt;

  /// Set when the author has since edited the text, so the UI can mark it.
  final DateTime? editedAt;

  const Note({
    required this.id,
    required this.text,
    required this.author,
    required this.createdAt,
    this.editedAt,
  });

  /// Author attributed to remarks carried over from the pre-notes format,
  /// where no author was recorded.
  static const String legacyAuthor = 'system';

  bool get isLegacy => author == legacyAuthor;
  bool get wasEdited => editedAt != null;

  /// Whether [username] is allowed to modify this note. Anyone may append a
  /// new note, but editing and deleting stay with the original author.
  bool canEdit(String? username) {
    if (username == null || username.isEmpty) return false;
    if (isLegacy) return false;
    return author.toLowerCase() == username.toLowerCase();
  }

  factory Note.create({required String text, required String author}) {
    final now = DateTime.now();
    return Note(
      // Timestamp + author is unique enough here; notes are added by hand,
      // never in bulk.
      id: '${now.microsecondsSinceEpoch}_${author.hashCode.abs()}',
      text: text,
      author: author,
      createdAt: now,
    );
  }

  Note copyWith({String? text, DateTime? editedAt}) => Note(
        id: id,
        text: text ?? this.text,
        author: author,
        createdAt: createdAt,
        editedAt: editedAt ?? this.editedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'author': author,
        'created_at': createdAt.toIso8601String(),
        if (editedAt != null) 'edited_at': editedAt!.toIso8601String(),
      };

  factory Note.fromJson(Map<String, dynamic> json) {
    final createdRaw = json['created_at'];
    final editedRaw = json['edited_at'];
    return Note(
      id: json['id']?.toString() ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      text: json['text']?.toString() ?? '',
      author: json['author']?.toString() ?? legacyAuthor,
      createdAt: createdRaw != null
          ? (DateTime.tryParse(createdRaw.toString()) ?? DateTime.now())
          : DateTime.now(),
      editedAt:
          editedRaw != null ? DateTime.tryParse(editedRaw.toString()) : null,
    );
  }

  /// Wraps a plain string from the old `remarks_list` format (which held bare
  /// strings with no author or timestamp).
  factory Note.fromLegacy(String text, {DateTime? createdAt, int index = 0}) =>
      Note(
        id: 'legacy_$index',
        text: text,
        author: legacyAuthor,
        createdAt: createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      );

  /// Parses a stored `remarks_list` value, accepting every format this column
  /// has held: a JSON string, a list of plain strings (legacy), or a list of
  /// note objects (current).
  ///
  /// [legacyRemarks] is the old single-field remarks text and [legacyDate] the
  /// record's creation date; when the list is empty, that text becomes the
  /// first note so nothing written before this change is lost.
  static List<Note> parseList(
    dynamic raw, {
    String? legacyRemarks,
    DateTime? legacyDate,
  }) {
    dynamic value = raw;

    // The column is sometimes a JSON-encoded string rather than a real list.
    if (value is String) {
      if (value.trim().isEmpty) {
        value = null;
      } else {
        try {
          value = jsonDecode(value);
        } catch (_) {
          value = null;
        }
      }
    }

    final notes = <Note>[];
    if (value is List) {
      for (var i = 0; i < value.length; i++) {
        final entry = value[i];
        if (entry is Map) {
          notes.add(Note.fromJson(Map<String, dynamic>.from(entry)));
        } else if (entry is String && entry.trim().isNotEmpty) {
          notes.add(Note.fromLegacy(entry, createdAt: legacyDate, index: i));
        }
      }
    }

    // Nothing in the list yet — carry the old single remarks field in as the
    // first note rather than dropping it.
    if (notes.isEmpty &&
        legacyRemarks != null &&
        legacyRemarks.trim().isNotEmpty) {
      notes.add(Note.fromLegacy(legacyRemarks.trim(), createdAt: legacyDate));
    }

    notes.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return notes;
  }

  /// Serializes a list back to the storage format.
  static List<Map<String, dynamic>> listToJson(List<Note> notes) =>
      notes.map((n) => n.toJson()).toList();

  @override
  bool operator ==(Object other) => other is Note && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
