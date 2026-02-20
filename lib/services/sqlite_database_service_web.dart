import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:convert';
import '../models/document.dart';
import '../models/activity.dart';
import '../utils/date_time_utils.dart';

class SQLiteDatabaseService {
  static final SQLiteDatabaseService _instance = SQLiteDatabaseService._internal();
  factory SQLiteDatabaseService() => _instance;
  SQLiteDatabaseService._internal();

  static const String _documentsBoxName = 'documents';
  static const String _activitiesBoxName = 'activities';
  static const String _pendingDeletionsBoxName = 'pending_deletions';
  static const String _notificationsHistoryBoxName = 'notifications_history';

  Box<Map>? _documentsBox;
  Box<Map>? _activitiesBox;
  Box<Map>? _pendingDeletionsBox;
  Box<Map>? _notificationsHistoryBox;

  Future<void> _initHive() async {
    await Hive.initFlutter();

    // Register adapters if needed
    // Hive.registerAdapter(DocumentAdapter());

    _documentsBox = await Hive.openBox<Map>(_documentsBoxName);
    _activitiesBox = await Hive.openBox<Map>(_activitiesBoxName);
    _pendingDeletionsBox = await Hive.openBox<Map>(_pendingDeletionsBoxName);
    _notificationsHistoryBox = await Hive.openBox<Map>(_notificationsHistoryBoxName);
  }

  Future<void> get database async {
    await _initHive();
  }

  Future<Box<Map>> get _documents async {
    if (_documentsBox == null) {
      await _initHive();
    }
    return _documentsBox!;
  }

  Future<Box<Map>> get _activities async {
    if (_activitiesBox == null) {
      await _initHive();
    }
    return _activitiesBox!;
  }

  Future<Box<Map>> get _pendingDeletions async {
    if (_pendingDeletionsBox == null) {
      await _initHive();
    }
    return _pendingDeletionsBox!;
  }

  Future<Box<Map>> get _notificationsHistory async {
    if (_notificationsHistoryBox == null) {
      await _initHive();
    }
    return _notificationsHistoryBox!;
  }

  Future<List<Document>> fetchDocuments() async {
    final box = await _documents;
    final maps = box.values.toList();

    List<Document> documents = [];
    for (var map in maps) {
      final docMap = Map<String, dynamic>.from(map);
      // Skip deleted documents
      if (docMap['deleted_pending_sync'] == 1) continue;

      final history = await fetchHistory(docMap['code']);
      documents.add(Document.fromJson(docMap)..history.addAll(history));
    }

    return documents;
  }

  Future<Document> createDocument(Document document) async {
    final box = await _documents;
    final docData = document.toJson();

    // Convert boolean to integer for consistency
    docData['incoming'] = (docData['incoming'] == true || docData['incoming'] == 1) ? 1 : 0;
    docData['calendar_added'] = (docData['calendar_added'] == true || docData['calendar_added'] == 1) ? 1 : 0;

    // Convert lists to JSON strings
    docData['image_urls'] = jsonEncode(docData['image_urls']);
    docData['file_urls'] = jsonEncode(docData['file_urls']);
    docData['file_names'] = jsonEncode(docData['file_names'] ?? []);
    docData['local_image_paths'] = jsonEncode(docData['local_image_paths'] ?? []);
    docData['local_file_paths'] = jsonEncode(docData['local_file_paths'] ?? []);
    docData['attachments'] = jsonEncode(docData['attachments'] ?? []);
    docData['remarks_list'] = jsonEncode(docData['remarks_list'] ?? []);

    docData['created_at'] = getPhilippineTime().toIso8601String();
    docData['updated_at'] = getPhilippineTime().toIso8601String();

    await box.put(document.code, docData);

    // Add history entries
    for (var entry in document.history) {
      await addHistoryEntry(document.code, entry);
    }

    return document;
  }

  Future<void> updateDocument(String documentCode, Map<String, dynamic> updates) async {
    final box = await _documents;
    final existing = box.get(documentCode);
    if (existing == null) return;

    final updated = Map<String, dynamic>.from(existing)..addAll(updates);

    // Convert boolean to integer if present
    if (updates.containsKey('incoming')) {
      updated['incoming'] = (updates['incoming'] == true || updates['incoming'] == 1) ? 1 : 0;
    }
    if (updates.containsKey('needs_sync')) {
      updated['needs_sync'] = (updates['needs_sync'] == true || updates['needs_sync'] == 1) ? 1 : 0;
    }
    if (updates.containsKey('calendar_added')) {
      updated['calendar_added'] = (updates['calendar_added'] == true || updates['calendar_added'] == 1) ? 1 : 0;
    }

    // Convert lists to JSON strings if present
    if (updates.containsKey('image_urls')) {
      updated['image_urls'] = jsonEncode(updates['image_urls']);
    }
    if (updates.containsKey('file_urls')) {
      updated['file_urls'] = jsonEncode(updates['file_urls']);
    }
    if (updates.containsKey('file_names')) {
      updated['file_names'] = jsonEncode(updates['file_names']);
    }
    if (updates.containsKey('local_image_paths')) {
      updated['local_image_paths'] = jsonEncode(updates['local_image_paths']);
    }
    if (updates.containsKey('local_file_paths')) {
      updated['local_file_paths'] = jsonEncode(updates['local_file_paths']);
    }
    if (updates.containsKey('scheduled_notification_ids')) {
      updated['scheduled_notification_ids'] = jsonEncode(updates['scheduled_notification_ids']);
    }
    if (updates.containsKey('attachments')) {
      updated['attachments'] = jsonEncode(updates['attachments']);
    }
    if (updates.containsKey('remarks_list')) {
      updated['remarks_list'] = jsonEncode(updates['remarks_list']);
    }

    updated['updated_at'] = getPhilippineTime().toIso8601String();

    await box.put(documentCode, updated);
  }

  Future<void> deleteDocument(String documentCode) async {
    final box = await _documents;
    await box.delete(documentCode);

    // Delete history entries
    final historyBox = await Hive.openBox<Map>('history_${documentCode}');
    await historyBox.clear();
    await historyBox.close();
  }

  Future<void> addHistoryEntry(String documentCode, HistoryEntry entry, {String? personnel}) async {
    final box = await Hive.openBox<Map>('history_${documentCode}');
    final entryData = {
      'action': entry.action,
      'person': entry.person,
      'timestamp': entry.timestamp.toIso8601String(),
      'notes': entry.notes,
      'personnel': personnel ?? entry.person,
    };
    await box.add(entryData);
  }

  Future<List<HistoryEntry>> fetchHistory(String documentCode) async {
    final box = await Hive.openBox<Map>('history_${documentCode}');
    final maps = box.values.toList();

    return maps.map((map) => HistoryEntry.fromJson(Map<String, dynamic>.from(map))).toList();
  }

  Future<void> clearAllData() async {
    final docsBox = await _documents;
    final activitiesBox = await _activities;
    final pendingDeletionsBox = await _pendingDeletions;
    final notificationsBox = await _notificationsHistory;

    await docsBox.clear();
    await activitiesBox.clear();
    await pendingDeletionsBox.clear();
    await notificationsBox.clear();

    // Note: In web version, we can't easily enumerate all boxes
    // History boxes will be cleared when accessed or can be handled differently
  }

  // Pending deletions methods
  Future<void> addPendingDeletion({
    required String deletedBy,
    required String docCode,
    required String title,
  }) async {
    final box = await _pendingDeletions;
    final deletionData = {
      'deleted_by': deletedBy,
      'doc_code': docCode,
      'title': title,
      'deleted_at': getPhilippineTime().toIso8601String(),
      'synced': 0,
    };
    await box.add(deletionData);
  }

  Future<List<Map<String, dynamic>>> getPendingDeletions() async {
    final box = await _pendingDeletions;
    return box.values
        .map((map) => Map<String, dynamic>.from(map))
        .where((deletion) => deletion['synced'] == 0)
        .toList();
  }

  Future<void> markDeletionAsSynced(int deletionId) async {
    final box = await _pendingDeletions;
    final existing = box.getAt(deletionId);
    if (existing != null) {
      final updated = Map<String, dynamic>.from(existing);
      updated['synced'] = 1;
      await box.putAt(deletionId, updated);
    }
  }

  Future<void> markDocumentAsDeletedPending(String documentCode) async {
    await updateDocument(documentCode, {'deleted_pending_sync': 1});
  }

  Future<void> deletePendingDeletionRecord(int deletionId) async {
    final box = await _pendingDeletions;
    await box.deleteAt(deletionId);
  }

  Future<void> close() async {
    await _documentsBox?.close();
    await _activitiesBox?.close();
    await _pendingDeletionsBox?.close();
    await _notificationsHistoryBox?.close();
  }

  // Notifications history methods
  Future<void> addNotificationHistory({
    required String documentCode,
    required String notificationType,
    required int notificationId,
    required DateTime scheduledTime,
    String status = 'scheduled',
  }) async {
    final box = await _notificationsHistory;
    final historyData = {
      'document_code': documentCode,
      'notification_type': notificationType,
      'notification_id': notificationId,
      'scheduled_time': scheduledTime.toIso8601String(),
      'status': status,
      'created_at': getPhilippineTime().toIso8601String(),
    };
    await box.add(historyData);
  }

  Future<List<Map<String, dynamic>>> fetchNotificationsHistory() async {
    final box = await _notificationsHistory;
    return box.values.map((map) => Map<String, dynamic>.from(map)).toList();
  }

  Future<void> updateNotificationStatus(int id, String status) async {
    final box = await _notificationsHistory;
    final existing = box.getAt(id);
    if (existing != null) {
      final updated = Map<String, dynamic>.from(existing);
      updated['status'] = status;
      await box.putAt(id, updated);
    }
  }

  Future<void> updateNotificationStatusByNotificationId(int notificationId, String status) async {
    final box = await _notificationsHistory;
    final allEntries = box.toMap();
    for (var entry in allEntries.entries) {
      final data = Map<String, dynamic>.from(entry.value);
      if (data['notification_id'] == notificationId) {
        data['status'] = status;
        await box.put(entry.key, data);
        break;
      }
    }
  }

  Future<void> updateNotificationsStatusByDocumentCode(String documentCode, String status) async {
    final box = await _notificationsHistory;
    final allEntries = box.toMap();
    for (var entry in allEntries.entries) {
      final data = Map<String, dynamic>.from(entry.value);
      if (data['document_code'] == documentCode) {
        data['status'] = status;
        await box.put(entry.key, data);
      }
    }
  }

  Future<void> deleteOldNotifications() async {
    final box = await _notificationsHistory;
    final oneMonthAgo = getPhilippineTime().subtract(const Duration(days: 30));
    final allEntries = box.toMap();
    final toDelete = <dynamic>[];

    for (var entry in allEntries.entries) {
      final data = Map<String, dynamic>.from(entry.value);
      final createdAt = DateTime.parse(data['created_at']);
      if (createdAt.isBefore(oneMonthAgo)) {
        toDelete.add(entry.key);
      }
    }

    for (var key in toDelete) {
      await box.delete(key);
    }
  }

  // Activities methods
  Future<List<Activity>> fetchActivities() async {
    final box = await _activities;
    final maps = box.values.toList();

    return maps.map((map) => Activity.fromJson(Map<String, dynamic>.from(map))).toList();
  }

  Future<Activity> createActivity(Activity activity) async {
    final box = await _activities;
    final actData = activity.toJson();
    actData.remove('id'); // Remove id for auto-generation
    actData['needs_sync'] = (actData['needs_sync'] == true || actData['needs_sync'] == 1) ? 1 : 0;
    actData['created_at'] = getPhilippineTime().toIso8601String();

    final id = await box.add(actData);
    return activity.copyWith(id: id);
  }

  Future<void> updateActivity(int activityId, Map<String, dynamic> updates) async {
    final box = await _activities;
    final existing = box.get(activityId);
    if (existing == null) return;

    final updated = Map<String, dynamic>.from(existing)..addAll(updates);
    if (updates.containsKey('needs_sync')) {
      updated['needs_sync'] = (updates['needs_sync'] == true || updates['needs_sync'] == 1) ? 1 : 0;
    }

    await box.put(activityId, updated);
  }

  Future<void> deleteActivity(int activityId) async {
    final box = await _activities;
    await box.delete(activityId);
  }

  // Pending uploads methods (stub implementations for web)
  // Note: Web version uses in-memory queue in UploadQueueManager instead of SQLite persistence

  /// Add a pending upload to the queue (stub for web - uploads are handled in-memory)
  Future<void> addPendingUpload({
    required String documentCode,
    required String filePath,
    required bool isImage,
    required String localPath,
    String status = 'pending',
    int retryCount = 0,
  }) async {
    // Stub: Web version handles uploads in-memory via UploadQueueManager
    // This method exists for API compatibility but does nothing in web
    print('addPendingUpload called on web - uploads handled in-memory');
  }

  /// Get all pending uploads (stub for web - uploads are handled in-memory)
  Future<List<Map<String, dynamic>>> getPendingUploads() async {
    // Stub: Web version handles uploads in-memory via UploadQueueManager
    // This method exists for API compatibility but returns empty list
    print('getPendingUploads called on web - uploads handled in-memory');
    return [];
  }

  /// Remove a pending upload by document code and file path (stub for web)
  Future<void> removePendingUploadByDocumentAndPath(String documentCode, String filePath) async {
    // Stub: Web version handles uploads in-memory via UploadQueueManager
    print('removePendingUploadByDocumentAndPath called on web - uploads handled in-memory');
  }

  /// Update the status of a pending upload (stub for web)
  Future<void> updatePendingUploadStatus(int id, String status, {int? retryCount}) async {
    // Stub: Web version handles uploads in-memory via UploadQueueManager
    print('updatePendingUploadStatus called on web - uploads handled in-memory');
  }

  /// Reset any stuck uploads (stub for web)
  Future<void> resetStuckUploads() async {
    // Stub: Web version handles uploads in-memory via UploadQueueManager
    // This method exists for API compatibility but does nothing in web
    print('resetStuckUploads called on web - uploads handled in-memory');
  }

  // Pending drive deletions methods (stub implementations for web)
  // Note: Web version cannot directly delete Drive files - user must be on mobile

  /// Add a pending drive deletion (stub for web)
  Future<void> addPendingDriveDeletion({
    required String fileId,
    required String documentCode,
  }) async {
    // Stub: Web version cannot directly delete Drive files
    // This method exists for API compatibility but does nothing in web
    print('addPendingDriveDeletion called on web - Drive deletion not supported on web');
  }

  /// Get pending drive deletions (stub for web)
  Future<List<Map<String, dynamic>>> getPendingDriveDeletions() async {
    // Stub: Web version cannot directly delete Drive files
    print('getPendingDriveDeletions called on web - returning empty list');
    return [];
  }

  /// Delete a pending drive deletion record (stub for web)
  Future<void> deletePendingDriveDeletionRecord(int id) async {
    // Stub: Web version cannot directly delete Drive files
    print('deletePendingDriveDeletionRecord called on web - Drive deletion not supported on web');
  }

  /// Delete a pending drive deletion by file ID (stub for web)
  Future<void> deletePendingDriveDeletionByFileId(String fileId) async {
    // Stub: Web version cannot directly delete Drive files
    print('deletePendingDriveDeletionByFileId called on web - Drive deletion not supported on web');
  }
}
