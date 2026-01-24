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

  Future<void> updateDocument(String documentCode, Map<String, dynamic> updates) async {
    // Fetch current document to check status and compliance fields
    final currentDoc = await fetchDocumentByCode(documentCode);
    if (currentDoc == null) {
      throw Exception('Document not found');
    }

    // Check if compliance fields are being updated
    final isComplianceUpdate = updates.containsKey('compliance_deadline') || updates.containsKey('compliance_assignee');

    // Update the document
    await _client.from('documents').update(updates).eq('code', documentCode);

    // If compliance fields updated and status is For Compliance, update notifications
    if (isComplianceUpdate && currentDoc.status == 'For Compliance') {
      final newDeadline = updates['compliance_deadline'] != null ? DateTime.parse(updates['compliance_deadline']) : currentDoc.complianceDeadline;
      final newAssignee = updates['compliance_assignee'] ?? currentDoc.complianceAssignee;
      if (newDeadline != null) {
        await updateComplianceNotifications(documentCode, newDeadline, newAssignee);
      }
    }
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
      print('Fetching notification history from Supabase...');
      // Join with documents table to get title and compliance_assignee
      // Group by document_code and get the most recent notification per document
      final response = await _client
          .from('notifications_history')
          .select('*, documents(title, compliance_assignee, status, compliance_deadline)')
          .order('created_at', ascending: false);

      print('Notification history response: $response');

      // Group by document_code and take the most recent notification per document
      final grouped = <String, Map<String, dynamic>>{};
      for (final item in response) {
        final docCode = item['document_code'] as String;
        if (!grouped.containsKey(docCode)) {
          grouped[docCode] = item;
        }
      }

      final result = grouped.values.toList();
      print('Grouped notification history: $result');
      return result;
    } catch (e) {
      print('Error fetching notification history: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchOverdueComplianceDocuments() async {
    try {
      print('Fetching overdue compliance documents from Supabase...');
      final now = DateTime.now();

      final response = await _client
          .from('documents')
          .select('code, title, compliance_deadline, compliance_assignee, status')
          .eq('status', 'For Compliance')
          .not('compliance_deadline', 'is', null)
          .lt('compliance_deadline', now.toString())
          .order('compliance_deadline', ascending: true);

      print('Overdue compliance documents: $response');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching overdue compliance documents: $e');
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

  Future<void> deleteNotificationsByDocumentCodeAndType(String documentCode, String notificationType) async {
    await _client.from('notifications_history')
        .delete()
        .eq('document_code', documentCode)
        .eq('notification_type', notificationType);
    print('Deleted $notificationType notifications for document $documentCode');
  }

  Future<void> updateComplianceNotifications(String documentCode, DateTime deadline, String? assignee) async {
    final now = DateTime.now();
    final timeDiff = deadline.difference(now);
    final hoursDiff = timeDiff.inHours;

    // Insert immediate notification with status 'updated' for audit
    await _client.from('notifications_history').insert({
      'document_code': documentCode,
      'notification_type': 'immediate',
      'notification_id': now.millisecondsSinceEpoch ~/ 1000,
      'scheduled_time': deadline.toIso8601String(),
      'status': 'updated',
    });
    print('Inserted updated immediate notification for document $documentCode');

    // Delete old scheduled notifications
    await _client.from('notifications_history').delete()
        .eq('document_code', documentCode)
        .or('notification_type.eq.1_day_reminder,notification_type.eq.6_hours_reminder,notification_type.eq.due_soon,notification_type.eq.overdue_hours,notification_type.eq.overdue_days')
        .eq('status', 'scheduled');
    print('Deleted old scheduled notifications for document $documentCode');

    // Insert new scheduled notifications based on deadline
    if (hoursDiff > 48) {
      // Schedule 1_day_reminder
      final reminderTime = deadline.subtract(const Duration(hours: 24)).copyWith(hour: 1, minute: 0, second: 0, millisecond: 0, microsecond: 0);

      await _client.from('notifications_history').insert({
        'document_code': documentCode,
        'notification_type': '1_day_reminder',
        'notification_id': now.millisecondsSinceEpoch ~/ 1000 + 1,
        'scheduled_time': reminderTime.toIso8601String(),
        'status': 'scheduled',
      });
      print('Inserted 1_day_reminder for document $documentCode');
    } else if (hoursDiff > 6) {
      if (hoursDiff <= 24) {
        // Schedule 6_hours_reminder
        await _client.from('notifications_history').insert({
          'document_code': documentCode,
          'notification_type': '6_hours_reminder',
          'notification_id': now.millisecondsSinceEpoch ~/ 1000 + 1,
          'scheduled_time': deadline.toIso8601String(),
          'status': 'scheduled',
        });
        print('Inserted 6_hours_reminder for document $documentCode');
      }
    } else if (hoursDiff > 0) {
      // Schedule due_soon
      await _client.from('notifications_history').insert({
        'document_code': documentCode,
        'notification_type': 'due_soon',
        'notification_id': now.millisecondsSinceEpoch ~/ 1000 + 1,
        'scheduled_time': deadline.toIso8601String(),
        'status': 'scheduled',
      });
      print('Inserted due_soon for document $documentCode');
    } else {
      // Overdue - insert overdue notification
      final overdueHours = -hoursDiff;
      if (overdueHours < 24) {
        await _client.from('notifications_history').insert({
          'document_code': documentCode,
          'notification_type': 'overdue_hours',
          'notification_id': now.millisecondsSinceEpoch ~/ 1000 + 1,
          'scheduled_time': deadline.toIso8601String(),
          'status': 'scheduled',
        });
        print('Inserted overdue_hours for document $documentCode');
      } else {
        await _client.from('notifications_history').insert({
          'document_code': documentCode,
          'notification_type': 'overdue_days',
          'notification_id': now.millisecondsSinceEpoch ~/ 1000 + 1,
          'scheduled_time': deadline.toIso8601String(),
          'status': 'scheduled',
        });
        print('Inserted overdue_days for document $documentCode');
      }
    }
  }
  
  // Device tokens operations
  Future<void> saveDeviceToken(String token) async {
    await _client.from('device_tokens').upsert({
      'token': token,
      'updated_at': DateTime.now().toIso8601String(),
    });
    print('Device token saved: $token');
  }

  Future<List<String>> getAllDeviceTokens() async {
    final response = await _client.from('device_tokens').select('token');
    final tokens = (response as List<dynamic>).map((item) => item['token'] as String).toList();
    print('Retrieved ${tokens.length} device tokens');
    return tokens;
  }

  // Invoke send compliance notifications Edge Function
  Future<void> sendComplianceNotifications({String? documentCode}) async {
    try {
      final body = documentCode != null ? {'document_code': documentCode} : null;
      final response = await _client.functions.invoke('send_compliance_notifications', body: body);
      print('Compliance notifications sent: ${response.data}');
    } catch (e) {
      print('Error sending compliance notifications: $e');
      rethrow;
    }
  }
}
