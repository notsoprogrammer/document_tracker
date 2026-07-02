import 'package:flutter/material.dart';
import 'dart:async';
import '../models/document.dart';
import 'cached_document_service.dart';
import 'sqlite_database_service_mobile.dart' if (dart.library.html) 'sqlite_database_service_web.dart';
import 'supabase_service.dart';
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
  bool _isDisposed = false;

  /// Stream of sync status changes
  Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;

  /// Get current sync status
  SyncStatus get currentStatus => _currentStatus;

  /// Initialize the enhanced sync service
  Future<void> initialize() async {
    if (_isInitialized || _isDisposed) return;

    try {
      // Initialize connectivity service
      await ConnectivityService().initialize();

      // Register for reconnection events
      ConnectivityService().registerReconnectionCallback(_onReconnection);

      _isInitialized = true;
    } catch (e) {
    }
  }

  /// Update sync status and notify listeners
  void _updateSyncStatus(SyncStatus status) {
    if (_isDisposed) return;

    _currentStatus = status;
    if (!_syncStatusController.isClosed) {
      _syncStatusController.add(status);
    }
  }

  /// Callback for when internet connection is restored
  void _onReconnection() {
    if (_isDisposed) return;

    performSync();
  }

  /// Perform sync operation with status updates
  Future<void> performSync() async {
    if (_isDisposed) return;

    try {
      final cachedService = CachedDocumentService();

      // Check connectivity
      final isOnline = await cachedService.isOnline;
      if (!isOnline) {
        return;
      }

      // Update status: Starting sync
      _updateSyncStatus(const SyncStatus(
        message: 'Starting sync...',
        isActive: true,
        color: Color(0xFF2196F3),
      ));

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
        if (!_isDisposed) {
          Future.delayed(const Duration(seconds: 3), () {
            if (!_isDisposed) {
              _updateSyncStatus(SyncStatus.idle);
            }
          });
        }
        return;
      }


      // Update status: Syncing documents
      _updateSyncStatus(SyncStatus(
        message: 'Syncing ${unsyncedDocuments.length} documents...',
        isActive: true,
        color: const Color(0xFF2196F3),
        progress: 0,
        total: unsyncedDocuments.length,
      ));

      // Sync to Supabase first
      await _syncToSupabase(unsyncedDocuments);

      // Sync pending deletions
      await _syncPendingDeletions();

      // Then process any pending file uploads (now that documents exist in Supabase)
      await _processPendingUploads();

      // Process any new pending uploads that might have been created during sync
      await _processPendingUploads();

      // Update status: Sync completed
      _updateSyncStatus(const SyncStatus(
        message: 'Sync completed successfully',
        isActive: false,
        color: Color(0xFF4CAF50),
      ));

      // Auto-hide after 3 seconds
      if (!_isDisposed) {
        Future.delayed(const Duration(seconds: 3), () {
          if (!_isDisposed) {
            _updateSyncStatus(SyncStatus.idle);
          }
        });
      }

    } catch (e) {
      _updateSyncStatus(const SyncStatus(
        message: 'Sync failed',
        isActive: false,
        color: Color(0xFFF44336),
      ));

      // Auto-hide error after 5 seconds
      if (!_isDisposed) {
        Future.delayed(const Duration(seconds: 5), () {
          if (!_isDisposed) {
            _updateSyncStatus(SyncStatus.idle);
          }
        });
      }
    }
  }

  /// Process pending file uploads with status updates
  Future<void> _processPendingUploads() async {
    if (_isDisposed) return;

    try {
      final queueManager = UploadQueueManager();
      final pendingUploads = queueManager.getAllItems().where((item) => item['status'] == 'pending').toList();

      if (pendingUploads.isEmpty) return;


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

    } catch (e) {
    }
  }

  /// Sync unsynced documents to Supabase
  Future<void> _syncToSupabase(List<Document> unsyncedDocuments) async {
    if (_isDisposed) return;

    try {

      final supabaseService = SupabaseService();
      int successCount = 0;

      for (int i = 0; i < unsyncedDocuments.length; i++) {
        if (_isDisposed) break;

        final doc = unsyncedDocuments[i];

        // Skip documents that still have local paths (uploads not completed)
        if (doc.localImagePaths.isNotEmpty || doc.localFilePaths.isNotEmpty) {
          continue;
        }

        // Update progress
        _updateSyncStatus(SyncStatus(
          message: 'Syncing documents... ($successCount/${unsyncedDocuments.length})',
          isActive: true,
          color: const Color(0xFF2196F3),
          progress: i,
          total: unsyncedDocuments.length,
        ));

        try {
          // Check if document already exists remotely
          final existingDoc = await supabaseService.fetchDocumentByCode(doc.code);
          if (existingDoc != null) {
            // Update existing document
            await supabaseService.updateDocument(doc.code, doc.toJson());
          } else {
            // Create new document
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

  /// Sync pending deletions to Supabase
  Future<void> _syncPendingDeletions() async {
    if (_isDisposed) return;

    try {
      final cachedService = CachedDocumentService();
      final pendingDeletions = await SQLiteDatabaseService().getPendingDeletions();

      if (pendingDeletions.isEmpty) {
        return;
      }


      // Update status: Syncing deletions
      _updateSyncStatus(SyncStatus(
        message: 'Syncing ${pendingDeletions.length} pending deletions...',
        isActive: true,
        color: const Color(0xFFFF9800),
        progress: 0,
        total: pendingDeletions.length,
      ));

      // Use the cached service method to sync pending deletions
      await cachedService.syncPendingDeletions();

    } catch (e) {
    }
  }

  /// Manually trigger sync
  Future<void> triggerSync() async {
    if (_isDisposed) return;

    await performSync();
  }

  /// Dispose the service
  void dispose() {
    _isDisposed = true;
    ConnectivityService().unregisterReconnectionCallback(_onReconnection);
    if (!_syncStatusController.isClosed) {
      _syncStatusController.close();
    }
    _isInitialized = false;
  }

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;

  /// Check if service is disposed
  bool get isDisposed => _isDisposed;
}
