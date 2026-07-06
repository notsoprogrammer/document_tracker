import 'package:flutter/foundation.dart';
import '../models/document.dart';
import 'cached_document_service.dart';
import 'sqlite_database_service.dart';
import 'supabase_service.dart';
import 'connectivity_service.dart';
import 'upload_queue_manager.dart';
import '../utils/date_time_utils.dart';

/// Auto-sync service to handle unsynced documents periodically and when online
class AutoSyncService {
  static bool _isInitialized = false;
  static bool _isRunning = false;
  static const Duration _syncInterval = Duration(minutes: 5);

  /// Initialize the auto-sync service
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Initialize connectivity service
      await ConnectivityService().initialize();

      // Initialize upload queue from SQLite persistence
      await UploadQueueManager().initialize();

      // Register for reconnection events
      ConnectivityService().registerReconnectionCallback(_onReconnection);

      // Start periodic sync
      _startPeriodicSync();

      _isInitialized = true;
    } catch (e) {
    }
  }

  /// Start periodic sync for cross-device synchronization
  static void _startPeriodicSync() {
    if (_isRunning) return;

    _isRunning = true;

    // Run sync immediately and then periodically
    _performSync();

    // Schedule periodic syncs
    Future.doWhile(() async {
      if (!_isRunning) return false;

      await Future.delayed(_syncInterval);
      if (_isRunning) {
        await _performSync();
      }

      return _isRunning;
    });
  }

  /// Callback for when internet connection is restored
  static void _onReconnection() {
    _performSync();
  }

  /// Perform sync operation for unsynced documents
  static Future<void> _performSync() async {
    try {
      final cachedService = CachedDocumentService();

      // Check connectivity
      final isOnline = await cachedService.isOnline;
      if (!isOnline) {
        return;
      }

      // Get all unsynced documents
      final allDocuments = await SQLiteDatabaseService().fetchDocuments();
      final unsyncedDocuments = allDocuments.where((doc) => doc.needsSync).toList();

      // Sync documents to Supabase first (so they exist before uploads reference them)
      if (unsyncedDocuments.isNotEmpty) {
        await _syncToSupabase(unsyncedDocuments);
      }

      // Always process pending file uploads — not just when there are unsynced docs.
      // Queue items persist across sessions (SQLite on mobile); without this, a pending
      // upload on a document that is already synced would never be retried.
      await cachedService.processPendingUploads();

    } catch (e) {
    }
  }

  /// Sync unsynced documents to Supabase
  static Future<void> _syncToSupabase(List<Document> unsyncedDocuments) async {
    try {

      final supabaseService = SupabaseService();
      int successCount = 0;

      for (final doc in unsyncedDocuments) {
        try {
          await supabaseService.createDocument(doc);
          await SQLiteDatabaseService().updateDocument(doc.code, {'needs_sync': 0});
          successCount++;
        } catch (e) {
        }
      }

    } catch (e) {
    }
  }

  /// Perform full bidirectional sync (push local changes and pull remote changes)
  static Future<void> _performFullSync() async {
    try {
      final cachedService = CachedDocumentService();

      // Check connectivity
      final isOnline = await cachedService.isOnline;
      if (!isOnline) {
        return;
      }


      // Step 1: Push local unsynced documents to Supabase first
      final allDocuments = await SQLiteDatabaseService().fetchDocuments();
      final unsyncedDocuments = allDocuments.where((doc) => doc.needsSync).toList();

      if (unsyncedDocuments.isNotEmpty) {
        await _syncToSupabase(unsyncedDocuments);

        // Then process any pending file uploads (now that documents exist in Supabase)
        await cachedService.processPendingUploads();
      }

      // Step 2: Pull remote documents from Supabase and merge with local
      await _pullFromSupabase();

    } catch (e) {
    }
  }

  /// Pull documents from Supabase and merge with local database
  static Future<void> _pullFromSupabase() async {
    try {
      final supabaseService = SupabaseService();
      final remoteDocuments = await supabaseService.fetchDocuments();
      final localDocuments = await SQLiteDatabaseService().fetchDocuments();

      // Create a map of local documents by code for quick lookup
      final localDocMap = {for (var doc in localDocuments) doc.code: doc};

      int addedCount = 0;
      int updatedCount = 0;

      for (final remoteDoc in remoteDocuments) {
        if (localDocMap.containsKey(remoteDoc.code)) {
          // Document exists locally - check if remote is newer
          // final localDoc = localDocMap[remoteDoc.code]!;

          // For now, we'll update local documents with remote data if they exist
          
          await SQLiteDatabaseService().updateDocument(remoteDoc.code, {
            'title': remoteDoc.title,
            'type': remoteDoc.type,
            'from_or_to': remoteDoc.fromOrTo,
            'mode': remoteDoc.mode,
            'addressed_to': remoteDoc.assignedTo,
            'remarks': remoteDoc.remarks,
            'person': remoteDoc.person,
            'incoming': remoteDoc.incoming,
            'status': remoteDoc.status,
            'image_urls': remoteDoc.imageUrls,
            'file_urls': remoteDoc.fileUrls,
            'updated_at': getPhilippineTime().toIso8601String(),
            'needs_sync': 0, // Mark as synced
          });
          updatedCount++;
        } else {
          // Document doesn't exist locally - add it
          await SQLiteDatabaseService().createDocument(remoteDoc);
          await SQLiteDatabaseService().updateDocument(remoteDoc.code, {'needs_sync': 0});
          addedCount++;
        }
      }

    } catch (e) {
    }
  }

  /// Manually trigger sync (bidirectional - push local changes and pull remote changes)
  static Future<void> triggerSync() async {
    await _performFullSync();
  }

  /// Get sync statistics
  static Future<Map<String, dynamic>> getSyncStats() async {
    try {
      final allDocuments = await SQLiteDatabaseService().fetchDocuments();
      final syncedDocuments = allDocuments.where((doc) => !doc.needsSync).toList();
      final unsyncedDocuments = allDocuments.where((doc) => doc.needsSync).toList();

      return {
        'total': allDocuments.length,
        'synced': syncedDocuments.length,
        'unsynced': unsyncedDocuments.length,
        'syncPercentage': allDocuments.isEmpty ? 100.0 : (syncedDocuments.length / allDocuments.length) * 100,
        'isInitialized': _isInitialized,
      };
    } catch (e) {
      return {
        'total': 0,
        'synced': 0,
        'unsynced': 0,
        'syncPercentage': 0.0,
        'isRunning': _isRunning,
        'isInitialized': _isInitialized,
      };
    }
  }

  /// Stop the auto-sync service
  static void stop() {
    _isRunning = false;
  }

  /// Dispose the auto-sync service
  static void dispose() {
    stop();
    ConnectivityService().unregisterReconnectionCallback(_onReconnection);
    _isInitialized = false;
  }

  /// Check if service is running
  static bool get isRunning => _isRunning;

  /// Check if service is initialized
  static bool get isInitialized => _isInitialized;
}
