import 'dart:io';
import 'package:flutter/foundation.dart';

/// Manages a queue of files pending upload to Google Drive
class UploadQueueManager extends ChangeNotifier {
  static final UploadQueueManager _instance = UploadQueueManager._internal();
  factory UploadQueueManager() => _instance;
  UploadQueueManager._internal();

  final List<Map<String, dynamic>> _uploadQueue = [];
  bool _isProcessing = false;

  /// Add a file to the upload queue
  void addToQueue({
    required String documentCode,
    required String filePath,
    required bool isImage,
    required String localPath,
    List<int>? bytes, // For web compatibility
  }) {
    // Check if file already exists in queue for this document across all statuses
    final alreadyQueued = _uploadQueue.any((item) =>
      item['documentCode'] == documentCode &&
      item['filePath'] == filePath
    );

    if (!alreadyQueued) {
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
      debugPrint('Added file to upload queue: $filePath for document $documentCode');
    } else {
      debugPrint('Skipped duplicate queue item: $filePath for document $documentCode');
    }
  }

  /// Add a web camera image to the upload queue with bytes
  void addWebCameraImageToQueue({
    required String documentCode,
    required String filePath,
    required List<int> bytes,
  }) {
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
      debugPrint('Added web camera image to upload queue: $filePath for document $documentCode');
    } else {
      debugPrint('Skipped duplicate queue item: $filePath for document $documentCode');
    }
  }

  /// Remove a file from the upload queue
  void removeFromQueue(String documentCode, String filePath) {
    _uploadQueue.removeWhere(
      (item) => item['documentCode'] == documentCode && item['filePath'] == filePath
    );
    debugPrint('Removed file from upload queue: $filePath for document $documentCode');
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
      debugPrint('Updated upload status: $filePath -> $status');
      if (status == 'completed') {
        if (onCompleted != null) {
          await onCompleted();
        }
        // Remove the item from the queue after completion
        _uploadQueue.removeAt(index);
      }
      // Notify listeners only if the status actually changed
      if (oldStatus != status) {
        notifyListeners();
      }
    }
  }

  /// Mark upload as completed and remove from queue
  void markCompletedAndRemove(String documentCode, String filePath, {Future<void> Function()? onCompleted}) async {
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
      debugPrint('Marked upload as completed and removing from queue: $filePath for document $documentCode');
      // Remove the item from the queue
      _uploadQueue.removeAt(index);
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
        debugPrint('File no longer exists, removing from queue: ${item['localPath']}');
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

  /// Clear all items
  void clear() {
    _uploadQueue.clear();
    debugPrint('Cleared upload queue');
  }
}
