import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/document.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  // Documents table operations
  Future<List<Document>> fetchDocuments() async {
    try {
      print('Fetching documents from Supabase...');
      final response = await _client.from('documents').select('*, history_entries(*)');
      print('Raw response: $response');

      final documents = response.map((doc) {
        final document = Document.fromJson(doc);
        // Add history entries from the joined table
        if (doc['history_entries'] != null) {
          final historyEntries = (doc['history_entries'] as List<dynamic>)
              .map((entry) => HistoryEntry.fromJson(entry))
              .toList();
          document.history.addAll(historyEntries);
        }
        return document;
      }).toList();

      print('Parsed ${documents.length} documents');
      return documents;
    } catch (e) {
      print('Error fetching documents: $e');
      return [];
    }
  }

  Future<Document?> fetchDocumentByCode(String code) async {
    try {
      final response = await _client.from('documents').select('*, history_entries(*)').eq('code', code).single();
      final document = Document.fromJson(response);
      // Add history entries from the joined table
      if (response['history_entries'] != null) {
        final historyEntries = (response['history_entries'] as List<dynamic>)
            .map((entry) => HistoryEntry.fromJson(entry))
            .toList();
        document.history.addAll(historyEntries);
      }
      return document;
    } catch (e) {
      print('Error fetching document by code: $e');
      return null;
    }
  }

  Future<Document> createDocument(Document document) async {
    final docData = document.toJson();
    docData.remove('history'); // Remove history as it's stored separately

    print('Creating document with data: $docData'); // Debug log

    final response = await _client.from('documents').insert(docData).select().single();

    print('Document created successfully: $response'); // Debug log

    // Create initial history entry in history_entries table (skip for flag ceremony)
    if (document.history.isNotEmpty && document.mode != 'Flag Ceremony') {
      await _client.from('history_entries').insert(
        document.history.map((entry) => {
          'document_code': response['code'],
          'personnel': entry.person, // Set personnel to the person who performed the action
          ...entry.toJson(),
        }).toList()
      );
    }

    return Document.fromJson(response)..history.addAll(document.history);
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      return "Today ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}";
    } else if (difference.inDays == 1) {
      return "Yesterday ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}";
    } else if (difference.inDays < 7) {
      return "${difference.inDays} days ago";
    } else {
      return "${dateTime.month}/${dateTime.day}/${dateTime.year}";
    }
  }

  Future<void> updateDocument(String documentCode, Map<String, dynamic> updates) async {
    await _client.from('documents').update(updates).eq('code', documentCode);
  }

  Future<void> deleteDocument(String documentCode) async {
    await _client.from('documents').delete().eq('code', documentCode);
  }

  Future<void> logDeletedRecord(String deletedBy, String docCode, String title) async {
    await _client.from('deleted_records').insert({
      'deleted_by': deletedBy,
      'doc_code': docCode,
      'title': title,
    });
  }

  // History operations - simplified to work with existing table structure
  Future<void> addHistoryEntry(String documentCode, HistoryEntry entry, {String? personnel}) async {
    await _client.from('history_entries').insert({
      'document_code': documentCode,
      'personnel': personnel ?? entry.person,
      ...entry.toJson(),
    });
    print('History entry added to database for document $documentCode: ${entry.action}');
  }

  Future<List<HistoryEntry>> fetchHistory(String documentCode) async {
    // Return empty list for now - history is handled by Document model
    return [];
  }

  Future<List<Map<String, dynamic>>> fetchDeletedRecords() async {
    try {
      final response = await _client.from('deleted_records').select('*').order('deleted_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching deleted records: $e');
      return [];
    }
  }

  // Notification history operations
  Future<void> addNotificationHistory({
    required String documentCode,
    required String notificationType,
    required int notificationId,
    required DateTime scheduledTime,
    String status = 'scheduled',
  }) async {
    await _client.from('notifications_history').insert({
      'document_code': documentCode,
      'notification_type': notificationType,
      'notification_id': notificationId,
      'scheduled_time': scheduledTime.toIso8601String(),
      'status': status,
    });
    print('Notification history added for document $documentCode: $notificationType');
  }

  Future<List<Map<String, dynamic>>> fetchNotificationsHistory() async {
    try {
      final response = await _client.from('notifications_history').select('*').order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching notification history: $e');
      return [];
    }
  }

  Future<void> updateNotificationStatus(int notificationId, String status) async {
    await _client.from('notifications_history').update({
      'status': status,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('notification_id', notificationId);
    print('Notification $notificationId status updated to $status');
  }

  Future<void> updateNotificationsStatusByDocumentCode(String documentCode, String status) async {
    await _client.from('notifications_history').update({
      'status': status,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('document_code', documentCode);
    print('All notifications for document $documentCode updated to $status');
  }

  Future<void> deleteOldNotifications() async {
    final cutoffDate = DateTime.now().subtract(const Duration(days: 30));
    await _client.from('notifications_history').delete().lt('created_at', cutoffDate.toIso8601String());
    print('Deleted notification history older than 30 days');
  }
}
