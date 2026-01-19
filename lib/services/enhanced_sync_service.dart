import 'package:flutter/material.dart';
import 'dart:async';
import '../models/document.dart';
import 'cached_document_service.dart';
import 'sqlite_database_service.dart';
import 'supabase_service.dart';
import 'google_drive_service.dart';
import 'connectivity_service.dart';
import 'upload_queue_manager.dart';

/// Represents the current sync status
class SyncStatus {
  final String message;
  final bool isActive;
  final Color color;
  final int? progress;
  final int? total;

  const SyncStatus({
    required this.message,
    required this.isActive,
    required this.color,
    this.progress,
    this.total,
  });

  static const SyncStatus idle = SyncStatus(
    message: '',
    isActive: false,
    color: Color(0xFF2196F3),
  );

  SyncStatus copyWith({
    String? message,
    bool? isActive,
    Color? color,
    int? progress,
    int? total,
  }) {
    return SyncStatus(
      message: message ?? this.message,
      isActive: isActive ?? this.isActive,
      color: color ?? this.color,
      progress: progress ?? this.progress,
      total: total ?? this.total,
    );
  }
}

/// Enhanced sync service with real-time status updates
class EnhancedSyncService {
  static final EnhancedSyncService _instance = EnhancedSyncService._internal();
  factory EnhancedSyncService() => _instance;
  EnhancedSyncService._internal();

  final StreamController<SyncStatus> _syncStatusController = StreamController<SyncStatus>.broadcast();
  SyncStatus _currentStatus = SyncStatus.idle;
  bool _isInitialized = false;

  /// Stream of sync status changes
  Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;

  /// Get current sync status
  SyncStatus get currentStatus => _currentStatus;

  /// Initialize the enhanced sync service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Initialize connectivity service
      await ConnectivityService().initialize();

      // Register for reconnection events
      ConnectivityService().registerReconnectionCallback(_onReconnection);

      _isInitialized = true;
      debugPrint('EnhancedSyncService initialized');
    } catch (e) {
      debugPrint('Error initializing EnhancedSyncService: $e');
    }
  }

  /// Update sync status and notify listeners
  void _updateSyncStatus(SyncStatus status) {
    _currentStatus = status;
    _syncStatusController.add(status);
    debugPrint('Sync status updated: ${status.message}');
  }

  /// Callback for when internet connection is restored
  void _onReconnection() {
    debugPrint('Internet reconnected! Starting auto-sync...');
    performSync();
  }

  /// Perform sync operation with status updates
  Future<void> performSync() async {
    try {
      final cachedService = CachedDocumentService();

      // Check connectivity
      final isOnline = await cachedService.isOnline;
      if (!isOnline) {
        debugPrint('Device is offline - skipping sync');
        return;
      }

      // Update status: Starting sync
      _updateSyncStatus(const SyncStatus(
        message: 'Starting sync...',
        isActive: true,
        color: Color(0xFF2196F3),
      ));

      // Process any pending file uploads first
      await _processPendingUploads();

      // Get all unsynced documents
      final allDocuments = await SQLiteDatabaseService().fetchDocuments();
      final unsyncedDocuments = allDocuments.where((doc) => doc.needsSync).toList();

      if (unsyncedDocuments.isEmpty) {
        _updateSyncStatus(const SyncStatus(
          message: 'All documents synced',
          isActive: false,
          color: Color(0xFF4CAF50),
        ));
        // Auto-hide after 3 seconds
        Future.delayed(const Duration(seconds: 3), () {
          _updateSyncStatus(SyncStatus.idle);
        });
        return;
      }

      debugPrint('Found ${unsyncedDocuments.length} unsynced documents');

      // Update status: Syncing documents
      _updateSyncStatus(SyncStatus(
        message: 'Syncing ${unsyncedDocuments.length} documents...',
        isActive: true,
        color: const Color(0xFF2196F3),
        progress: 0,
        total: unsyncedDocuments.length,
      ));

      // Sync to Supabase
      await _syncToSupabase(unsyncedDocuments);

      // Sync to Google Drive if needed
      await _syncToGoogleDrive(unsyncedDocuments);

      // Process any new pending uploads that might have been created during sync
      await _processPendingUploads();

      // Update status: Sync completed
      _updateSyncStatus(const SyncStatus(
        message: 'Sync completed successfully',
        isActive: false,
        color: Color(0xFF4CAF50),
      ));

      // Auto-hide after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        _updateSyncStatus(SyncStatus.idle);
      });

    } catch (e) {
      debugPrint('Error in sync: $e');
      _updateSyncStatus(const SyncStatus(
        message: 'Sync failed',
        isActive: false,
        color: Color(0xFFF44336),
      ));

      // Auto-hide error after 5 seconds
      Future.delayed(const Duration(seconds: 5), () {
        _updateSyncStatus(SyncStatus.idle);
      });
    }
  }

  /// Process pending file uploads with status updates
  Future<void> _processPendingUploads() async {
    try {
      final queueManager = UploadQueueManager();
      final pendingUploads = queueManager.getAllItems().where((item) => item['status'] == 'pending').toList();

      if (pendingUploads.isEmpty) return;

      debugPrint('Processing ${pendingUploads.length} pending uploads');

      // Update status: Uploading files
      _updateSyncStatus(SyncStatus(
        message: 'Uploading ${pendingUploads.length} files...',
        isActive: true,
        color: const Color(0xFFFF9800),
        progress: 0,
        total: pendingUploads.length,
      ));

      final cachedService = CachedDocumentService();
      await cachedService.processPendingUploads();

      debugPrint('File uploads completed');
    } catch (e) {
      debugPrint('Error processing pending uploads: $e');
    }
  }

  /// Sync unsynced documents to Supabase
  Future<void> _syncToSupabase(List<Document> unsyncedDocuments) async {
    try {
      debugPrint('Syncing ${unsyncedDocuments.length} documents to Supabase...');

      final supabaseService = SupabaseService();
      int successCount = 0;

      for (int i = 0; i < unsyncedDocuments.length; i++) {
        final doc = unsyncedDocuments[i];

        // Update progress
        _updateSyncStatus(SyncStatus(
          message: 'Syncing documents... ($successCount/${unsyncedDocuments.length})',
          isActive: true,
          color: const Color(0xFF2196F3),
          progress: i,
          total: unsyncedDocuments.length,
        ));

        try {
          await supabaseService.createDocument(doc);
          await SQLiteDatabaseService().updateDocument(doc.code, {'needs_sync': 0});
          successCount++;
        } catch (e) {
          debugPrint('Failed to sync document ${doc.code} to Supabase: $e');
        }
      }

      debugPrint('Supabase sync completed: $successCount/${unsyncedDocuments.length} documents synced');
    } catch (e) {
      debugPrint('Error in Supabase sync: $e');
    }
  }

  /// Sync unsynced documents to Google Drive
  Future<void> _syncToGoogleDrive(List<Document> unsyncedDocuments) async {
    try {
      debugPrint('Syncing ${unsyncedDocuments.length} documents to Google Drive...');

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
          successCount++;
        } catch (e) {
          debugPrint('Failed to sync document ${doc.code} to Google Drive: $e');
        }
      }

      debugPrint('Google Drive sync completed: $successCount/${unsyncedDocuments.length} documents synced');
    } catch (e) {
      debugPrint('Error in Google Drive sync: $e');
    }
  }

  /// Manually trigger sync
  Future<void> triggerSync() async {
    debugPrint('Manual sync triggered');
    await performSync();
  }

  /// Dispose the service
  void dispose() {
    ConnectivityService().unregisterReconnectionCallback(_onReconnection);
    _syncStatusController.close();
    _isInitialized = false;
    debugPrint('EnhancedSyncService disposed');
  }

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;
}
