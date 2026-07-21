import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/document.dart';
import '../models/activity.dart';
import '../models/repository_link.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  // Documents table operations
  Future<List<Document>> fetchDocuments() async {
    try {
      final response = await _client.from('documents').select('*, history_entries(*)');

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

      return documents;
    } catch (e) {
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
      return null;
    }
  }

  Future<Document> createDocument(Document document) async {
    final docData = document.toJson();
    docData.remove('history');

    final response = await _client.from('documents').insert(docData).select().single();

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
  }

  Future<List<Map<String, dynamic>>> fetchNotificationsHistory() async {
    try {
      // Join with documents table to get title and compliance_assignee
      // Group by document_code and get the most recent notification per document
      final response = await _client
          .from('notifications_history')
          .select('*, documents(title, compliance_assignee, status, compliance_deadline)')
          .order('created_at', ascending: false);

      // Group by document_code and take the most recent notification per document
      final grouped = <String, Map<String, dynamic>>{};
      for (final item in response) {
        final docCode = item['document_code'] as String;
        if (!grouped.containsKey(docCode)) {
          grouped[docCode] = item;
        }
      }

      final result = grouped.values.toList();
      return result;
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchOverdueComplianceDocuments() async {
    try {
      final now = DateTime.now();

      final response = await _client
          .from('documents')
          .select('code, title, compliance_deadline, compliance_assignee, status')
          .eq('status', 'For Compliance')
          .not('compliance_deadline', 'is', null)
          .lt('compliance_deadline', now.toString())
          .order('compliance_deadline', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      return [];
    }
  }

  Future<void> updateNotificationStatus(int notificationId, String status) async {
    await _client.from('notifications_history').update({
      'status': status,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('notification_id', notificationId);
  }

  Future<void> updateNotificationsStatusByDocumentCode(String documentCode, String status) async {
    await _client.from('notifications_history').update({
      'status': status,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('document_code', documentCode);
  }

  Future<void> deleteOldNotifications() async {
    final cutoffDate = DateTime.now().subtract(const Duration(days: 30));
    await _client.from('notifications_history').delete().lt('created_at', cutoffDate.toIso8601String());
  }

  Future<void> deleteNotificationsByDocumentCodeAndType(String documentCode, String notificationType) async {
    await _client.from('notifications_history')
        .delete()
        .eq('document_code', documentCode)
        .eq('notification_type', notificationType);
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

    // Delete old scheduled notifications
    await _client.from('notifications_history').delete()
        .eq('document_code', documentCode)
        .or('notification_type.eq.1_day_reminder,notification_type.eq.6_hours_reminder,notification_type.eq.due_soon,notification_type.eq.overdue_hours,notification_type.eq.overdue_days')
        .eq('status', 'scheduled');

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
      } else {
        await _client.from('notifications_history').insert({
          'document_code': documentCode,
          'notification_type': 'overdue_days',
          'notification_id': now.millisecondsSinceEpoch ~/ 1000 + 1,
          'scheduled_time': deadline.toIso8601String(),
          'status': 'scheduled',
        });
      }
    }
  }
  
  // Device tokens operations
  Future<void> saveDeviceToken(String? token, String username) async {
    if (token == null) return;

    // Get user_id from users table
    final userResponse = await _client.from('users').select('id').eq('username', username).single();
    final userId = userResponse['id'];

    // Upsert by token so each physical device keeps its own row
    await _client.from('device_tokens').upsert({
      'user_id': userId,
      'username': username,
      'token': token,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'token');
  }

  Future<void> removeDeviceToken(String token) async {
    await _client.from('device_tokens').delete().eq('token', token);
  }

  /// Updates the notification_preferences JSON column on the device_tokens row
  /// identified by [token]. Fails silently if the column doesn't exist yet.
  Future<void> saveDeviceNotificationPreferences(
    String token,
    Map<String, bool> preferences,
  ) async {
    try {
      await _client.from('device_tokens').update({
        'notification_preferences': preferences,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('token', token);
    } catch (e) {
    }
  }

  Future<List<String>> getAllDeviceTokens() async {
    final response = await _client.from('device_tokens').select('token');
    final tokens = (response as List<dynamic>).map((item) => item['token'] as String).toList();
    return tokens;
  }

  Future<List<String>> fetchAllUsernames() async {
    try {
      final response = await _client.from('users').select('username').order('username');
      return (response as List<dynamic>).map((r) => r['username'] as String).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> scheduleAssignmentNotification(
    String documentCode,
    String documentTitle,
    List<String> assignees,
  ) async {
    if (assignees.isEmpty) return;
    await _client.from('pending_assignment_notifications').insert({
      'document_code': documentCode,
      'document_title': documentTitle,
      'assignees': assignees,
      'notify_at': DateTime.now().add(const Duration(minutes: 1)).toUtc().toIso8601String(),
      'sent': false,
    });
  }

  // Invoke send compliance notifications Edge Function
  Future<void> sendComplianceNotifications({String? documentCode}) async {
    try {
      final body = documentCode != null ? {'document_code': documentCode} : null;
      final response = await _client.functions.invoke('send_compliance_notifications', body: body);
    } catch (e) {
      rethrow;
    }
  }

  // Fetch documents for calendar (those with calendar_deadline or compliance_deadline)
  Future<List<Document>> fetchCalendarDocuments() async {
    try {
      final response = await _client.from('documents').select('*, history_entries(*)').or('calendar_deadline.not.is.null,compliance_deadline.not.is.null');

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

      return documents;
    } catch (e) {
      return [];
    }
  }

  // Activities table operations
  Future<List<Activity>> fetchActivities() async {
    try {
      final response = await _client.from('activities').select('*');

      final activities = response.map((act) => Activity.fromJson(act)).toList();

      return activities;
    } catch (e) {
      return [];
    }
  }

  Future<Activity> createActivity(Activity activity) async {
    final actData = activity.toJson();
    actData.remove('id'); // Remove id as it's auto-generated

    final response = await _client.from('activities').insert(actData).select().single();

    return Activity.fromJson(response);
  }

  Future<void> updateActivity(int activityId, Map<String, dynamic> updates) async {
    updates.remove('id'); // Don't update id
    await _client.from('activities').update(updates).eq('id', activityId);
  }

  Future<void> deleteActivity(int activityId) async {
    await _client.from('activities').delete().eq('id', activityId);
  }

  // Repository links operations
  Future<List<RepositoryLink>> fetchRepositoryLinks() async {
    try {
      final response = await _client.from('repository_links').select('*').order('added_at', ascending: false);
      return (response as List<dynamic>).map((r) => RepositoryLink.fromJson(r)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<RepositoryLink> createRepositoryLink(RepositoryLink link) async {
    final data = link.toJson();
    data.remove('id');
    data.remove('needs_sync');
    final response = await _client.from('repository_links').insert(data).select().single();
    return RepositoryLink.fromJson(response);
  }

  Future<void> updateRepositoryLink(int id, Map<String, dynamic> updates) async {
    updates.remove('id');
    updates.remove('needs_sync');
    await _client.from('repository_links').update(updates).eq('id', id);
  }

  Future<void> deleteRepositoryLink(int id) async {
    await _client.from('repository_links').delete().eq('id', id);
  }
}
