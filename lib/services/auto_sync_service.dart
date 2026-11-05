import '../models/document.dart';
import 'cached_document_service.dart';
import 'sqlite_database_service.dart';
import 'supabase_service.dart';
import 'connectivity_service.dart';
import 'upload_queue_manager.dart';

/// Auto-sync service to handle unsynced documents periodically and when online
class AutoSyncService {
  static bool _isInitialized = false;
  static bool _isRunning = false;
  /// How often to pull in other devices' changes. Five minutes meant twelve
  /// full-table reads an hour per device, which is what exhausted the Supabase
  /// Disk IO budget. Edits still appear immediately on the device making them,
  /// and a pull-to-refresh fetches on demand.
  static const Duration _syncInterval = Duration(minutes: 20);

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
          // Insert only when the row is genuinely absent. This used to insert
          // unconditionally — every other sync path already checks — so a
          // document that had in fact reached Supabase was re-inserted and
          // came back 409 Conflict, blocking the rest of the queue.
          final existing = await supabaseService.fetchDocumentByCode(doc.code);
          if (existing != null) {
            await supabaseService.updateDocument(doc.code, doc.toJson());
          } else {
            await supabaseService.createDocument(doc);
          }
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
      // This used to run its own full `select('*, history_entries(*)')` and
      // then rewrite every local row one at a time — a second complete read of
      // both tables every cycle, on top of whatever the screens were doing.
      // CachedDocumentService does the same pull through syncRemoteDocuments,
      // which writes only the rows that actually changed.
      await CachedDocumentService().fetchDocuments(force: true);
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
