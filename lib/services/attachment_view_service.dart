import 'package:supabase_flutter/supabase_flutter.dart';

class AttachmentViewEntry {
  final String username;
  final String attachmentType; // 'image' or 'pdf'
  final DateTime viewedAt;

  const AttachmentViewEntry({
    required this.username,
    required this.attachmentType,
    required this.viewedAt,
  });
}

class AttachmentViewService {
  static final _db = Supabase.instance.client;

  static Future<void> recordView({
    required String documentCode,
    required String username,
    required String attachmentType, // 'image' | 'pdf'
  }) async {
    try {
      await _db.from('document_attachment_views').insert({
        'document_code': documentCode,
        'username': username,
        'attachment_type': attachmentType,
        'viewed_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {
      // Silently fail — viewing should never block the user
    }
  }

  /// Returns viewers sorted by most recent first, deduplicated by username+type
  /// (keeps only the latest view per username per type).
  static Future<List<AttachmentViewEntry>> getViewers(String documentCode) async {
    try {
      final rows = await _db
          .from('document_attachment_views')
          .select('username, attachment_type, viewed_at')
          .eq('document_code', documentCode)
          .order('viewed_at', ascending: false);

      final seen = <String>{};
      final result = <AttachmentViewEntry>[];
      for (final row in rows as List) {
        final key = '${row['username']}|${row['attachment_type']}';
        if (seen.add(key)) {
          result.add(AttachmentViewEntry(
            username: row['username'] as String,
            attachmentType: row['attachment_type'] as String,
            viewedAt: DateTime.parse(row['viewed_at'] as String).toLocal(),
          ));
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }
}
