import 'dart:io';
import 'package:flutter/foundation.dart';
import 'sqlite_database_service.dart' if (dart.library.html) 'sqlite_database_service_web.dart';

/// Manages a queue of files pending upload to Google Drive
class UploadQueueManager extends ChangeNotifier {
  static final UploadQueueManager _instance = UploadQueueManager._internal();
  factory UploadQueueManager() => _instance;
  UploadQueueManager._internal();

  final List<Map<String, dynamic>> _uploadQueue = [];
  // Persistent bytes cache for web files — survives queue-item status changes
  final Map<String, List<int>> _webBytesCache = {};
  bool _isProcessing = false;
  bool _isInitialized = false;

  // Debug log — ring buffer of the last 200 events, visible in the upload debug dialog
  static final List<String> _debugLog = [];
  static List<String> get debugLog => List.unmodifiable(_debugLog);

  static void log(String message) {
    final now = DateTime.now();
    final ts = '${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}:${now.second.toString().padLeft(2,'0')}.${now.millisecond.toString().padLeft(3,'0')}';
    final entry = '[$ts] $message';
    _debugLog.add(entry);
    if (_debugLog.length > 200) _debugLog.removeAt(0);
    debugPrint('UploadQueue: $entry');
  }

  /// Initialize the queue from SQLite persistence
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Only use SQLite persistence on mobile (non-web)
      if (!kIsWeb) {
        // Reset any stuck uploads (in case app crashed during upload)
        await SQLiteDatabaseService().resetStuckUploads();
        
        // Load pending uploads from SQLite
        final pendingUploads = await SQLiteDatabaseService().getPendingUploads();
        for (final upload in pendingUploads) {
          _uploadQueue.add({
            'documentCode': upload['document_code'],
            'filePath': upload['file_path'],
            'isImage': upload['is_image'] == 1,
            'localPath': upload['local_path'],
            'bytes': null, // Bytes cannot be persisted to SQLite
            'status': upload['status'],
            'retryCount': upload['retry_count'] ?? 0,
            'timestamp': upload['timestamp'],
            'sqliteId': upload['id'], // Store SQLite ID for updates
          });
        }
      }
      _isInitialized = true;
    } catch (e) {
      _isInitialized = true; // Continue with empty queue
    }
  }

  /// Start processing if not already processing
  bool startProcessing() {
    if (_isProcessing) return false;
    _isProcessing = true;
    return true;
  }

  /// End processing
  void endProcessing() {
    _isProcessing = false;
  }

  /// Add a file to the upload queue
  void addToQueue({
    required String documentCode,
    required String filePath,
    required bool isImage,
    required String localPath,
    List<int>? bytes, // For web compatibility
  }) async {
    // Persist bytes in cache regardless of duplicate status
    if (bytes != null) {
      _webBytesCache['$documentCode:$filePath'] = bytes;
    }

    // Check if file already exists in queue for this document across all statuses
    final alreadyQueued = _uploadQueue.any((item) =>
      item['documentCode'] == documentCode &&
      item['filePath'] == filePath
    );

    if (!alreadyQueued) {
      // Add to in-memory queue
      _uploadQueue.add({
        'documentCode': documentCode,
        'filePath': filePath,
        'isImage': isImage,
        'localPath': localPath,
        'bytes': bytes, // Store bytes for web files
        'status': 'pending',
        'retryCount': 0,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      // Persist to SQLite (non-web only, and only if bytes are not required)
      if (!kIsWeb && bytes == null) {
        try {
          await SQLiteDatabaseService().addPendingUpload(
            documentCode: documentCode,
            filePath: filePath,
            isImage: isImage,
            localPath: localPath,
          );
        } catch (e) {
        }
      }
    } else {
    }
  }

  /// Add a web camera image to the upload queue with bytes
  void addWebCameraImageToQueue({
    required String documentCode,
    required String filePath,
    required List<int> bytes,
  }) {
    // Persist bytes in cache regardless of duplicate status
    _webBytesCache['$documentCode:$filePath'] = bytes;

    // Check if file already exists in queue across all statuses
    final alreadyQueued = _uploadQueue.any((item) =>
      item['documentCode'] == documentCode &&
      item['filePath'] == filePath
    );

    if (!alreadyQueued) {
      _uploadQueue.add({
        'documentCode': documentCode,
        'filePath': filePath,
        'isImage': true,
        'localPath': filePath,
        'bytes': bytes, // Store bytes for web camera images
        'status': 'pending',
        'retryCount': 0,
        'timestamp': DateTime.now().toIso8601String(),
      });
      // Note: Web images with bytes are NOT persisted to SQLite
    } else {
    }
  }

  /// Retrieve cached web bytes for a file (fallback when queue item bytes are null)
  List<int>? getBytesForFile(String documentCode, String filePath) {
    return _webBytesCache['$documentCode:$filePath'];
  }

  /// Re-key all queue entries from [oldCode] to [newCode] (e.g. when '-' placeholder is replaced by the real code)
  void updateDocumentCode(String oldCode, String newCode) async {
    if (oldCode == newCode) return;
    for (final item in _uploadQueue) {
      if (item['documentCode'] == oldCode) {
        item['documentCode'] = newCode;
      }
    }
    // Re-key web bytes cache
    final keysToUpdate = _webBytesCache.keys.where((k) => k.startsWith('$oldCode:')).toList();
    for (final key in keysToUpdate) {
      final filePath = key.substring(oldCode.length + 1);
      final bytes = _webBytesCache.remove(key);
      if (bytes != null) _webBytesCache['$newCode:$filePath'] = bytes;
    }
    // Persist to SQLite
    if (!kIsWeb) {
      try {
        await SQLiteDatabaseService().updatePendingUploadsDocumentCode(oldCode, newCode);
      } catch (e) {
      }
    }
  }

  /// Remove all queued items for a document (e.g. when the add screen is cancelled)
  Future<void> removeAllForDocument(String documentCode) async {
    final paths = _uploadQueue
        .where((item) => item['documentCode'] == documentCode)
        .map((item) => item['filePath'] as String)
        .toList();
    _uploadQueue.removeWhere((item) => item['documentCode'] == documentCode);
    for (final path in paths) {
      _webBytesCache.remove('$documentCode:$path');
    }
    if (!kIsWeb) {
      try {
        await SQLiteDatabaseService().removeAllPendingUploadsForDocument(documentCode);
      } catch (e) {}
    }
    if (paths.isNotEmpty) notifyListeners();
  }

  /// Remove a file from the upload queue
  void removeFromQueue(String documentCode, String filePath) async {
    _uploadQueue.removeWhere(
      (item) => item['documentCode'] == documentCode && item['filePath'] == filePath
    );
    _webBytesCache.remove('$documentCode:$filePath');
    
    // Remove from SQLite persistence
    if (!kIsWeb) {
      try {
        await SQLiteDatabaseService().removePendingUploadByDocumentAndPath(documentCode, filePath);
      } catch (e) {
      }
    }
  }

  /// Get all pending uploads for a document
  List<Map<String, dynamic>> getPendingUploads(String documentCode) {
    return _uploadQueue.where((item) =>
      item['documentCode'] == documentCode && item['status'] == 'pending'
    ).toList();
  }

  /// Get all failed uploads for retry
  List<Map<String, dynamic>> getFailedUploads() {
    return _uploadQueue.where((item) =>
      item['status'] == 'failed' && item['retryCount'] < 3
    ).toList();
  }

  /// Update upload status
  void updateStatus(String documentCode, String filePath, String status, {int? retryCount, Future<void> Function()? onCompleted}) async {
    final index = _uploadQueue.indexWhere(
      (item) => item['documentCode'] == documentCode && item['filePath'] == filePath
    );

    if (index != -1) {
      final oldStatus = _uploadQueue[index]['status'];
      _uploadQueue[index]['status'] = status;
      if (retryCount != null) {
        _uploadQueue[index]['retryCount'] = retryCount;
      }
      
      // Update SQLite persistence
      if (!kIsWeb) {
        final sqliteId = _uploadQueue[index]['sqliteId'];
        if (sqliteId != null) {
          try {
            await SQLiteDatabaseService().updatePendingUploadStatus(sqliteId, status, retryCount: retryCount);
          } catch (e) {
          }
        }
      }
      
      if (status == 'completed') {
        if (onCompleted != null) {
          await onCompleted();
        }
        // Remove the item from the queue after completion
        _uploadQueue.removeAt(index);
        
        // Remove from SQLite
        if (!kIsWeb) {
          try {
            await SQLiteDatabaseService().removePendingUploadByDocumentAndPath(documentCode, filePath);
          } catch (e) {
          }
        }
      }
      // Notify listeners only if the status actually changed
      if (oldStatus != status) {
        notifyListeners();
      }
    }
  }

  /// Mark upload as completed and remove from queue
  Future<void> markCompletedAndRemove(String documentCode, String filePath, {Future<void> Function()? onCompleted}) async {
    final index = _uploadQueue.indexWhere(
      (item) => item['documentCode'] == documentCode && item['filePath'] == filePath
    );

    if (index != -1) {
      // Run the cleanup callback
      if (onCompleted != null) {
        await onCompleted();
      }
      // Update status to completed
      _uploadQueue[index]['status'] = 'completed';
      // Remove the item from the queue and clear bytes cache
      _uploadQueue.removeAt(index);
      _webBytesCache.remove('$documentCode:$filePath');
      
      // Remove from SQLite persistence
      if (!kIsWeb) {
        try {
          await SQLiteDatabaseService().removePendingUploadByDocumentAndPath(documentCode, filePath);
        } catch (e) {
        }
      }
      
      // Notify listeners
      notifyListeners();
    }
  }

  /// Clean up missing files from queue
  Future<void> cleanupMissingFiles() async {
    final toRemove = [];

    for (final item in _uploadQueue) {
      final file = File(item['localPath']);
      if (!await file.exists()) {
        toRemove.add(item);
      }
    }

    for (final item in toRemove) {
      _uploadQueue.remove(item);
    }
  }

  /// Get queue statistics
  Map<String, dynamic> getQueueStats() {
    final pending = _uploadQueue.where((item) => item['status'] == 'pending').length;
    final processing = _uploadQueue.where((item) => item['status'] == 'uploading').length;
    final completed = _uploadQueue.where((item) => item['status'] == 'completed').length;
    final failed = _uploadQueue.where((item) => item['status'] == 'failed').length;

    return {
      'total': _uploadQueue.length,
      'pending': pending,
      'processing': processing,
      'completed': completed,
      'failed': failed,
      'isProcessing': _isProcessing,
    };
  }

  /// Clear completed uploads older than specified duration
  void clearOldCompleted(Duration maxAge) {
    final cutoff = DateTime.now().subtract(maxAge);
    _uploadQueue.removeWhere((item) =>
      item['status'] == 'completed' &&
      DateTime.parse(item['timestamp']).isBefore(cutoff)
    );
  }

  /// Get all queue items
  List<Map<String, dynamic>> getAllItems() {
    return List.from(_uploadQueue);
  }

  /// Clear all items (in-memory only)
  void clear() {
    _uploadQueue.clear();
  }

  /// Clear all items from both memory and SQLite persistence
  Future<void> clearAll() async {
    _uploadQueue.clear();
    if (!kIsWeb) {
      try {
        await SQLiteDatabaseService().clearAllPendingUploads();
      } catch (e) {
        log('clearAll ERROR: $e');
      }
    }
    log('DEBUG: queue cleared by user');
    notifyListeners();
  }
}
