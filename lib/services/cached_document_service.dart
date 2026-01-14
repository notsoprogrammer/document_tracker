import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'dart:developer' as developer;
import 'sqlite_database_service.dart';
import 'supabase_service.dart';
import 'google_drive_service.dart';
import 'upload_queue_manager.dart';
import '../models/document.dart';
import '../utils/snackbar_utils.dart';

class CachedDocumentService {
  final SQLiteDatabaseService _localDb = SQLiteDatabaseService();
  final SupabaseService _remoteDb = SupabaseService();
  final Connectivity _connectivity = Connectivity();

  Future<bool> get isOnline async {
    final result = await _connectivity.checkConnectivity();
    return result != ConnectivityResult.none;
  }

  Future<List<Document>> fetchDocuments() async {
    try {
      // Try to fetch from local cache first
      final localDocuments = await _localDb.fetchDocuments();

      // If online, sync with remote and merge data
      if (await isOnline) {
        try {
          final remoteDocuments = await _remoteDb.fetchDocuments();

          // Create a map of remote documents by code for quick lookup
          final remoteMap = {for (var doc in remoteDocuments) doc.code: doc};



          // Merge documents: prefer remote data, but keep local-only documents
          final mergedDocuments = <Document>[];

          // Add all remote documents
          mergedDocuments.addAll(remoteDocuments);

          // Add local documents that don't exist remotely (offline additions)
          for (var localDoc in localDocuments) {
            if (!remoteMap.containsKey(localDoc.code)) {
              mergedDocuments.add(localDoc);
            }
          }

          // Update local cache with merged data
          await _localDb.clearAllData();
          for (var doc in mergedDocuments) {
            await _localDb.createDocument(doc);
          }

          return mergedDocuments;
        } catch (e) {
          print('Failed to sync with remote: $e');
          // Return local data if remote sync fails
          return localDocuments;
        }
      } else {
        // Offline: return cached data
        return localDocuments;
      }
    } catch (e) {
      print('Error fetching documents: $e');
      return [];
    }
  }

  Future<Document> createDocument(Document document) async {
    try {
      // Always save locally first
      await _localDb.createDocument(document);

      // Queue files for upload if they exist
      await _queueFilesForUpload(document);

      // Process uploads immediately if online
      if (await isOnline) {
        try {
          await processPendingUploads();
        } catch (e) {
          debugPrint('Failed to process pending uploads: $e');
        }
      }

      // Fetch the updated document after uploads (to get URLs)
      final updatedDocuments = await _localDb.fetchDocuments();
      final updatedDocument = updatedDocuments.firstWhere(
        (doc) => doc.code == document.code,
        orElse: () => document,
      );

      // If online, sync to remote
      if (await isOnline) {
        try {
          final remoteDoc = await _remoteDb.createDocument(updatedDocument);
          // Update local with any remote changes (like IDs)
          return remoteDoc;
        } catch (e) {
          print('Failed to sync creation to remote: $e');
          // Mark as needing sync since remote failed
          await _localDb.updateDocument(updatedDocument.code, {'needs_sync': true});
          return updatedDocument.copyWith(needsSync: true);
        }
      } else {
        // Mark as needing sync if offline
        await _localDb.updateDocument(updatedDocument.code, {'needs_sync': true});
        return updatedDocument.copyWith(needsSync: true);
      }
    } catch (e) {
      print('Error creating document: $e');
      rethrow;
    }
  }

  Future<void> updateDocument(String documentCode, Map<String, dynamic> updates) async {
    try {
      // Update locally first
      await _localDb.updateDocument(documentCode, updates);

      // If online, sync to remote
      if (await isOnline) {
        try {
          await _remoteDb.updateDocument(documentCode, updates);
        } catch (e) {
          print('Failed to sync update to remote: $e');
          // Update is saved locally, will sync later
        }
      }
    } catch (e) {
      print('Error updating document: $e');
      rethrow;
    }
  }

  Future<void> deleteDocument(String documentCode) async {
    try {
      // Delete locally first
      await _localDb.deleteDocument(documentCode);

      // If online, sync to remote
      if (await isOnline) {
        try {
          await _remoteDb.deleteDocument(documentCode);
        } catch (e) {
          print('Failed to sync deletion to remote: $e');
          // Deletion is done locally, will sync later
        }
      }
    } catch (e) {
      print('Error deleting document: $e');
      rethrow;
    }
  }

  Future<void> addHistoryEntry(String documentCode, HistoryEntry entry, {String? personnel}) async {
    try {
      // Add to local history
      await _localDb.addHistoryEntry(documentCode, entry, personnel: personnel);

      // If online, sync to remote
      if (await isOnline) {
        try {
          await _remoteDb.addHistoryEntry(documentCode, entry, personnel: personnel);
        } catch (e) {
          print('Failed to sync history to remote: $e');
          // History is saved locally, will sync later
        }
      }
    } catch (e) {
      print('Error adding history entry: $e');
      rethrow;
    }
  }

  Future<void> syncPendingChanges() async {
    if (!(await isOnline)) return;

    try {
      // This is a simplified sync - in a full implementation,
      // you'd track pending changes and sync them properly
      final localDocs = await _localDb.fetchDocuments();
      final remoteDocs = await _remoteDb.fetchDocuments();

      // For now, just ensure local matches remote
      await _localDb.clearAllData();
      for (var doc in remoteDocs) {
        await _localDb.createDocument(doc);
      }
    } catch (e) {
      print('Error syncing pending changes: $e');
    }
  }

  Future<void> syncSpecificDocument(String documentCode) async {
    if (!(await isOnline)) return;

    try {
      // Get the local document
      final localDocs = await _localDb.fetchDocuments();
      final localDoc = localDocs.firstWhere((doc) => doc.code == documentCode);

      if (localDoc.needsSync) {
        // Check if document already exists remotely
        final existingDoc = await _remoteDb.fetchDocumentByCode(documentCode);
        if (existingDoc != null) {
          // Update existing document
          await _remoteDb.updateDocument(documentCode, localDoc.toJson());
        } else {
          // Create new document
          await _remoteDb.createDocument(localDoc);
        }

        // Update local to mark as synced
        await _localDb.updateDocument(documentCode, {'needs_sync': 0});
      }
    } catch (e) {
      print('Error syncing specific document: $e');
      rethrow;
    }
  }

  Future<void> syncAllData(
    BuildContext context, {
    required Future<void> Function() reloadRecords,
    bool showMessages = true,
  }) async {
    // Check offline
    if (!(await isOnline)) {
      debugPrint('Device is offline - skipping sync');
      if (context.mounted && showMessages) {
        SnackbarUtils.showWarningSnackBar(context, 'Device is offline - sync skipped');
      }
      return;
    }

    // Fetch unsynced documents
    final allDocuments = await _localDb.fetchDocuments();
    final unsynced = allDocuments.where((doc) => doc.needsSync).toList();
    if (unsynced.isEmpty) {
      if (context.mounted && showMessages) {
        SnackbarUtils.showInfoSnackBar(context, 'All documents are already synced!');
      }
      return;
    }

    // Sync to Supabase
    int success = 0;
    for (var doc in unsynced) {
      try {
        // Check if document already exists remotely
        final existingDoc = await _remoteDb.fetchDocumentByCode(doc.code);
        if (existingDoc != null) {
          // Update existing document
          await _remoteDb.updateDocument(doc.code, doc.toJson());
        } else {
          // Create new document
          await _remoteDb.createDocument(doc);
        }
        await _localDb.updateDocument(doc.code, {'needs_sync': 0});
        success++;
      } catch (e) {
        print('Failed to sync document ${doc.code}: $e');
      }
    }

    // Show result
    if (context.mounted && showMessages) {
      final total = unsynced.length;
      if (success == total) {
        SnackbarUtils.showSuccessSnackBar(context, 'Synced $success of $total documents');
      } else {
        SnackbarUtils.showWarningSnackBar(context, 'Synced $success of $total documents');
      }
    }

    await reloadRecords();
  }

  /// Queue files for background upload
  Future<void> _queueFilesForUpload(Document document) async {
    final queueManager = UploadQueueManager();

    // Queue image files from local paths
    if (document.localImagePaths.isNotEmpty) {
      for (final localPath in document.localImagePaths) {
        queueManager.addToQueue(
          documentCode: document.code,
          filePath: localPath,
          isImage: true,
          localPath: localPath,
        );
      }
    }

    // Queue document files from local paths
    if (document.localFilePaths.isNotEmpty) {
      for (final localPath in document.localFilePaths) {
        queueManager.addToQueue(
          documentCode: document.code,
          filePath: localPath,
          isImage: false,
          localPath: localPath,
        );
      }
    }
  }

  /// Process pending file uploads
  Future<void> processPendingUploads({VoidCallback? onUploadComplete}) async {
    if (!(await isOnline)) return;

    final queueManager = UploadQueueManager();
    final failedUploads = queueManager.getFailedUploads();

    // Also get pending uploads that haven't been attempted yet
    final allItems = queueManager.getAllItems();
    final pendingUploads = allItems.where((item) =>
      item['status'] == 'pending'
    ).toList();

    // Combine pending and failed uploads
    final uploadsToProcess = [...pendingUploads, ...failedUploads];
    bool hasCompletedUploads = false;

    for (final upload in uploadsToProcess) {
      try {
        queueManager.updateStatus(
          upload['documentCode'],
          upload['filePath'],
          'uploading'
        );

        final file = File(upload['localPath']);
        final isImage = upload['isImage'];
        final fileName = '${upload['documentCode']}_${DateTime.now().millisecondsSinceEpoch}';

        // Get the document to determine the correct folder
        final docs = await _localDb.fetchDocuments();
        final doc = docs.firstWhere((d) => d.code == upload['documentCode']);
        final folder = doc.mode == 'Flag Ceremony'
            ? DriveFolder.flagCeremony
            : doc.incoming
                ? DriveFolder.incoming
                : DriveFolder.outgoing;

        String? driveUrl;
        if (isImage) {
          // For images, use the existing uploadImageToDrive method
          driveUrl = await GoogleDriveService.uploadImageToDrive(
            file,
            fileName,
            folder: folder,
          );
          debugPrint('Image upload result for ${upload['filePath']}: $driveUrl');
        } else {
          // For documents, use uploadFileToDrive method which handles file extensions properly
          final file = File(upload['localPath']);
          final extension = upload['localPath'].split('.').last.toLowerCase();
          final docFileName = extension.isEmpty ? fileName : '$fileName.$extension';
          driveUrl = await GoogleDriveService.uploadFileToDrive(
            file,
            docFileName,
            folder: folder,
          );
          debugPrint('Document upload result for ${upload['filePath']}: $driveUrl');
        }

        if (driveUrl != null) {
          // Update document with the uploaded URL
          final documentCode = upload['documentCode'];
          final isImage = upload['isImage'];

          // Get current document to update URLs
          final docs = await _localDb.fetchDocuments();
          final doc = docs.firstWhere((d) => d.code == documentCode);

          if (isImage) {
            final updatedUrls = [...doc.imageUrls, driveUrl];
            final updatedLocalPaths = doc.localImagePaths.where((path) => path != upload['localPath']).toList();
            await _localDb.updateDocument(documentCode, {
              'image_urls': updatedUrls,
              'local_image_paths': updatedLocalPaths,
            });
            // Also update remote database
            await _remoteDb.updateDocument(documentCode, {
              'image_urls': updatedUrls,
              'local_image_paths': updatedLocalPaths,
            });
          } else {
            final updatedUrls = [...doc.fileUrls, driveUrl];
            final updatedLocalPaths = doc.localFilePaths.where((path) => path != upload['localPath']).toList();
            await _localDb.updateDocument(documentCode, {
              'file_urls': updatedUrls,
              'local_file_paths': updatedLocalPaths,
            });
            // Also update remote database
            await _remoteDb.updateDocument(documentCode, {
              'file_urls': updatedUrls,
              'local_file_paths': updatedLocalPaths,
            });
          }

          queueManager.updateStatus(documentCode, upload['filePath'], 'completed');
          hasCompletedUploads = true;
          debugPrint('Successfully uploaded ${upload['filePath']} for document $documentCode');
        } else {
          throw Exception('Upload returned null URL');
        }
      } catch (e) {
        debugPrint('Failed to upload ${upload['filePath']}: $e');
        final newRetryCount = upload['retryCount'] + 1;
        if (newRetryCount >= 3) {
          queueManager.updateStatus(
            upload['documentCode'],
            upload['filePath'],
            'failed',
            retryCount: newRetryCount
          );
        } else {
          queueManager.updateStatus(
            upload['documentCode'],
            upload['filePath'],
            'failed',
            retryCount: newRetryCount
          );
        }
      }
    }

    // Call the callback if uploads were completed
    if (hasCompletedUploads && onUploadComplete != null) {
      onUploadComplete();
    }
  }

  // Future<void> syncSpecificDocument(String documentCode) async {
  //   if (!(await isOnline)) return;

  //   try {
  //     final localDoc = (await _localDb.fetchDocuments()).firstWhere((doc) => doc.code == documentCode);
  //     if (localDoc.needsSync) {
  //       // Sync to remote
  //       await _remoteDb.createDocument(localDoc);
  //       // Mark as synced
  //       await _localDb.updateDocument(documentCode, {'needs_sync': false});
  //     }
  //   } catch (e) {
  //     print('Error syncing specific document: $e');
  //     rethrow;
  //   }
  // }
}
