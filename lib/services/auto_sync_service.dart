import 'package:flutter/foundation.dart';
import '../models/document.dart';
import 'cached_document_service.dart';
import 'sqlite_database_service.dart';
import 'supabase_service.dart';
import 'google_drive_service.dart';

/// Auto-sync service to handle unsynced documents periodically
class AutoSyncService {
  static bool _isRunning = false;
  static bool _isInitialized = false;
  static const Duration _syncInterval = Duration(minutes: 5);

  /// Initialize the auto-sync service
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _isInitialized = true;
      debugPrint('AutoSyncService initialized');

      // Start periodic sync
      _startPeriodicSync();
    } catch (e) {
      debugPrint('Error initializing AutoSyncService: $e');
    }
  }

  /// Start periodic sync for unsynced documents
  static void _startPeriodicSync() {
    if (_isRunning) return;

    _isRunning = true;
    debugPrint('Starting periodic auto-sync...');

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

  /// Perform sync operation for unsynced documents
  static Future<void> _performSync() async {
    try {
      final cachedService = CachedDocumentService();

      // Check connectivity
      final isOnline = await cachedService.isOnline;
      if (!isOnline) {
        debugPrint('Device is offline - skipping auto-sync');
        return;
      }

      // Get all unsynced documents
      final allDocuments = await SQLiteDatabaseService().fetchDocuments();
      final unsyncedDocuments = allDocuments.where((doc) => doc.needsSync).toList();

      if (unsyncedDocuments.isEmpty) {
        debugPrint('No unsynced documents found');
        return;
      }

      debugPrint('Found ${unsyncedDocuments.length} unsynced documents for auto-sync');

      // Sync to Supabase
      await _syncToSupabase(unsyncedDocuments);

      // Sync to Google Drive if needed
      await _syncToGoogleDrive(unsyncedDocuments);

    } catch (e) {
      debugPrint('Error in auto-sync: $e');
    }
  }

  /// Sync unsynced documents to Supabase
  static Future<void> _syncToSupabase(List<Document> unsyncedDocuments) async {
    try {
      debugPrint('Auto-syncing ${unsyncedDocuments.length} documents to Supabase...');

      final supabaseService = SupabaseService();
      int successCount = 0;

      for (final doc in unsyncedDocuments) {
        try {
          await supabaseService.createDocument(doc);
          await SQLiteDatabaseService().updateDocument(doc.code, {'needs_sync': 0});
          successCount++;
        } catch (e) {
          debugPrint('Failed to sync document ${doc.code} to Supabase: $e');
        }
      }

      debugPrint('Auto-sync to Supabase completed: $successCount/${unsyncedDocuments.length} documents synced');
    } catch (e) {
      debugPrint('Error in auto-sync to Supabase: $e');
    }
  }

  /// Sync unsynced documents to Google Drive
  static Future<void> _syncToGoogleDrive(List<Document> unsyncedDocuments) async {
    try {
      debugPrint('Auto-syncing ${unsyncedDocuments.length} documents to Google Drive...');

      int successCount = 0;

      for (final doc in unsyncedDocuments) {
        try {
          // Upload file if present
          if (doc.filePath != null) {
            final url = await GoogleDriveService.uploadFile(doc.filePath!, doc.incoming, doc.code);
            if (url != null) {
              // Update document with the uploaded URL
              await SQLiteDatabaseService().updateDocument(doc.code, {'file_urls': [url]});
            }
          }

          // Note: imageUrls and fileUrls are already uploaded when document is created
          // This auto-sync is mainly for documents that failed initial upload
          successCount++;
        } catch (e) {
          debugPrint('Failed to sync document ${doc.code} to Google Drive: $e');
        }
      }

      debugPrint('Auto-sync to Google Drive completed: $successCount/${unsyncedDocuments.length} documents synced');
    } catch (e) {
      debugPrint('Error in auto-sync to Google Drive: $e');
    }
  }

  /// Manually trigger sync
  static Future<void> triggerSync() async {
    debugPrint('Manual auto-sync triggered');
    await _performSync();
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
        'isRunning': _isRunning,
        'isInitialized': _isInitialized,
      };
    } catch (e) {
      debugPrint('Error getting sync stats: $e');
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
    debugPrint('AutoSyncService stopped');
  }

  /// Dispose the auto-sync service
  static void dispose() {
    stop();
    _isInitialized = false;
    debugPrint('AutoSyncService disposed');
  }

  /// Check if service is running
  static bool get isRunning => _isRunning;

  /// Check if service is initialized
  static bool get isInitialized => _isInitialized;
}
