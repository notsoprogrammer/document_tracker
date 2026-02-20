import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'sqlite_database_service_mobile.dart' if (dart.library.html) 'sqlite_database_service_web.dart';
import 'supabase_service.dart';
import 'google_drive_service.dart';
import 'upload_queue_manager.dart';
import '../models/document.dart';
import '../utils/snackbar_utils.dart';
import '../services/auth_service.dart';

class CachedDocumentService {
  final SQLiteDatabaseService _localDb = SQLiteDatabaseService();
  final SupabaseService _remoteDb = SupabaseService();
  final Connectivity _connectivity = Connectivity();

  Future<bool> get isOnline async {
    final result = await _connectivity.checkConnectivity();
    return result != ConnectivityResult.none;
  }

  /// Ensure database schema is up to date by accessing the database
  Future<void> _ensureDatabaseSchema() async {
    try {
      // Access the database to trigger any pending upgrades
      await _localDb.database;
      // debugPrint('Database schema check completed');
    } catch (e) {
      debugPrint('Error ensuring database schema: $e');
    }
  }

  Future<List<Document>> fetchDocuments() async {
    try {
      // Ensure database schema is up to date
      await _ensureDatabaseSchema();

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
            } else {
              // If local document exists in remote and is marked as needing sync, mark as synced
              if (localDoc.needsSync) {
                await _localDb.updateDocument(localDoc.code, {'needs_sync': 0});
                // debugPrint('Marked local document ${localDoc.code} as synced (already exists in remote)');
              }
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

      // Process uploads in the background if online
      if (await isOnline) {
        try {
          // Start uploads in background - don't wait for completion
          processPendingUploads();
        } catch (e) {
          debugPrint('Failed to start background uploads: $e');
        }
      }

      // If online, sync to remote immediately (regardless of upload status)
      if (await isOnline) {
        try {
          final remoteDoc = await _remoteDb.createDocument(document);

          // Create urgent notification if status is Urgent
          if (remoteDoc.status == 'Urgent') {
            try {
              await _remoteDb.addNotificationHistory(
                documentCode: remoteDoc.code,
                notificationType: 'urgent',
                notificationId: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                scheduledTime: DateTime.now(),
                status: 'urgent',
              );
              print('Urgent notification created for new document ${remoteDoc.code}');
            } catch (e) {
              print('Failed to create urgent notification for new document: $e');
            }
          }

          // Update local with any remote changes (like IDs)
          return remoteDoc;
        } catch (e) {
          print('Failed to sync creation to remote: $e');
          // Mark as needing sync since remote failed
          await _localDb.updateDocument(document.code, {'needs_sync': true});
          return document.copyWith(needsSync: true);
        }
      } else {
        // Mark as needing sync if offline
        await _localDb.updateDocument(document.code, {'needs_sync': true});
        return document.copyWith(needsSync: true);
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
      // Get the document details before deleting for logging
      final localDocs = await _localDb.fetchDocuments();
      final document = localDocs.firstWhere((doc) => doc.code == documentCode);
      final username = await AuthService.getUsername();

      // Get all Drive URLs that need to be deleted
      final allDriveUrls = [...document.imageUrls, ...document.fileUrls];

      // Check if online
      if (await isOnline) {
        // Online: Delete immediately and log to Supabase
        try {
          // Delete all Drive files first
          for (final driveUrl in allDriveUrls) {
            try {
              // Extract file ID from URL if needed
              final fileId = GoogleDriveService.normalizeFileId(driveUrl);
              await GoogleDriveService.deleteFile(fileId);
              // debugPrint('Deleted Drive file: $fileId');
            } catch (e) {
              debugPrint('Failed to delete Drive file $driveUrl: $e');
              // Continue with other files even if one fails
            }
          }

          // Delete from remote first
          await _remoteDb.deleteDocument(documentCode);
          
          // Log the deletion to Supabase
          if (username != null) {
            await _remoteDb.logDeletedRecord(username, documentCode, document.title ?? documentCode);
          }
          
          // Delete locally after successful remote deletion
          await _localDb.deleteDocument(documentCode);
          
          // debugPrint('Document $documentCode deleted successfully (online)');
        } catch (e) {
          print('Failed to delete from remote: $e');
          rethrow;
        }
      } else {
        // Offline: Mark as deleted_pending_sync and add to pending_deletions
        debugPrint('Device is offline - marking document $documentCode for deletion');
        
        // Mark document as deleted_pending_sync (hides it from UI)
        await _localDb.markDocumentAsDeletedPending(documentCode);
        
        // Add to pending deletions table
        if (username != null) {
          await _localDb.addPendingDeletion(
            deletedBy: username,
            docCode: documentCode,
            title: document.title ?? documentCode,
          );
        }

        // Also queue Drive file deletions for when back online
        for (final driveUrl in allDriveUrls) {
          final fileId = GoogleDriveService.normalizeFileId(driveUrl);
          await _localDb.addPendingDriveDeletion(
            fileId: fileId,
            documentCode: documentCode,
          );
        }
        
        // debugPrint('Document $documentCode marked for deletion (offline)');
      }
    } catch (e) {
      print('Error deleting document: $e');
      rethrow;
    }
  }

  /// Sync pending deletions to Supabase
  Future<void> syncPendingDeletions() async {
    if (!(await isOnline)) {
      // debugPrint('Device is offline - skipping pending deletions sync');
      return;
    }

    try {
      final pendingDeletions = await _localDb.getPendingDeletions();
      
      if (pendingDeletions.isEmpty) {
        // debugPrint('No pending deletions to sync');
        return;
      }

      // debugPrint('Syncing ${pendingDeletions.length} pending deletions...');
      int successCount = 0;

      for (final deletion in pendingDeletions) {
        try {
          final docCode = deletion['doc_code'] as String;
          final deletedBy = deletion['deleted_by'] as String;
          final title = deletion['title'] as String;
          final deletionId = deletion['id'] as int;

          // Delete from Supabase
          await _remoteDb.deleteDocument(docCode);
          
          // Log the deletion to Supabase
          await _remoteDb.logDeletedRecord(deletedBy, docCode, title);
          
          // Actually delete the document from local SQLite
          await _localDb.deleteDocument(docCode);
          
          // Mark deletion as synced (or delete the pending deletion record)
          await _localDb.deletePendingDeletionRecord(deletionId);
          
          successCount++;
          // debugPrint('Synced deletion for document $docCode');
        } catch (e) {
          debugPrint('Failed to sync deletion for ${deletion['doc_code']}: $e');
          // Continue with next deletion
        }
      }

      // debugPrint('Synced $successCount of ${pendingDeletions.length} pending deletions');
    } catch (e) {
      debugPrint('Error syncing pending deletions: $e');
    }
  }

  Future<void> addHistoryEntry(String documentCode, HistoryEntry entry, {String? personnel}) async {
    try {
      // Prevent duplicate "Files Uploaded" history entries
      if (entry.action == 'Files Uploaded') {
        final docs = await _localDb.fetchDocuments();
        final doc = docs.firstWhere((d) => d.code == documentCode);
        if (doc.history.isNotEmpty && doc.history.last.action == 'Files Uploaded') {
          // debugPrint('Skipping duplicate "Files Uploaded" history entry for document $documentCode');
          return;
        }
      }

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

        // After successful sync, trigger notifications if needed
        if (localDoc.status == 'For Compliance' && localDoc.complianceDeadline != null) {
          try {
            // Record notification history
            await _remoteDb.addNotificationHistory(
              documentCode: localDoc.code,
              notificationType: 'scheduled',
              notificationId: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              scheduledTime: localDoc.complianceDeadline!,
              status: 'scheduled',
            );
            // Send compliance notifications
            await _remoteDb.sendComplianceNotifications(documentCode: localDoc.code);
            print('Compliance notifications triggered for synced document ${localDoc.code}');
          } catch (e) {
            print('Failed to trigger compliance notifications for synced document ${localDoc.code}: $e');
          }
        } else if (localDoc.status == 'Urgent') {
          try {
            // Record urgent notification history
            await _remoteDb.addNotificationHistory(
              documentCode: localDoc.code,
              notificationType: 'urgent',
              notificationId: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              scheduledTime: DateTime.now(),
              status: 'urgent',
            );
            print('Urgent notification created for synced document ${localDoc.code}');
          } catch (e) {
            print('Failed to create urgent notification for synced document: $e');
          }
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
      // debugPrint('Device is offline - skipping sync');
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

        // After successful sync, trigger notifications if needed
        if (doc.status == 'For Compliance' && doc.complianceDeadline != null) {
          try {
            // Record notification history
            await _remoteDb.addNotificationHistory(
              documentCode: doc.code,
              notificationType: 'scheduled',
              notificationId: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              scheduledTime: doc.complianceDeadline!,
              status: 'scheduled',
            );
            // Send compliance notifications
            await _remoteDb.sendComplianceNotifications(documentCode: doc.code);
            print('Compliance notifications triggered for synced document ${doc.code}');
          } catch (e) {
            print('Failed to trigger compliance notifications for synced document ${doc.code}: $e');
          }
        } else if (doc.status == 'Urgent') {
          try {
            // Record urgent notification history
            await _remoteDb.addNotificationHistory(
              documentCode: doc.code,
              notificationType: 'urgent',
              notificationId: DateTime.now().millisecondsSinceEpoch ~/ 1000,
              scheduledTime: DateTime.now(),
              status: 'urgent',
            );
            print('Urgent notification created for synced document ${doc.code}');
          } catch (e) {
            print('Failed to create urgent notification for synced document: $e');
          }
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
      for (int i = 0; i < document.localImagePaths.length; i++) {
        final localPath = document.localImagePaths[i];
        // For web camera images, we need to get bytes from the screen state
        // This is a simplified approach - in practice, you'd pass bytes through the document or use a different mechanism
        queueManager.addToQueue(
          documentCode: document.code,
          filePath: localPath,
          isImage: true,
          localPath: localPath,
          bytes: kIsWeb && localPath.startsWith('web_image_') ? null : null, // Bytes will be handled in processPendingUploads
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

    // Prevent concurrent processing
    if (!queueManager.startProcessing()) {
      // debugPrint('Upload processing already in progress, skipping');
      return;
    }

    try {
      // Get all items and filter only status == 'pending' || status == 'failed'
      final allItems = queueManager.getAllItems();
      final uploadsToProcess = allItems.where((item) =>
        item['status'] == 'pending' || item['status'] == 'failed'
      ).toList();
      bool hasCompletedUploads = false;
      final Set<String> documentsWithUploads = {};

      for (final upload in uploadsToProcess) {
        try {
          queueManager.updateStatus(
            upload['documentCode'],
            upload['filePath'],
            'uploading'
          );

          final isImage = upload['isImage'];
          final fileName = '${upload['documentCode']}_${DateTime.now().millisecondsSinceEpoch}';

          // Get the document to determine the correct folder
          final docs = await _localDb.fetchDocuments();
          final doc = docs.firstWhere((d) => d.code == upload['documentCode']);
          DriveFolder folder;
          if (doc.mode == 'Flag Ceremony') {
            folder = DriveFolder.flagCeremony;
          } else if ([
            'Sectoral Plans',
            'Ecological Profile',
            'Research/Studies/Trainings',
            'CLUP Zoning Reclassification',
            'CSOs',
            'CDC – Resolution',
            'CDC – Minutes',
            'CDC – Attendance',
            'AIP',
            'Barangay – AIP',
            'Barangay– GAD',
            'Zoning/Loc. Clearance',
            'Zoning/Loc. Certification',
          ].contains(doc.category)) {
            folder = DriveFolder.attendance; // Core Function -> attendance
          } else if ([
            'PR/PPMP',
            'Liquidation/ Reimbursement',
            'PFMAT',
          ].contains(doc.category)) {
            folder = DriveFolder.movs; // Strategic Function -> movs
          } else if ([
            'DTR',
            'Monthly Accomplishment Report',
            'Quarterly Accomplishment Report',
            'OPCR',
            'Certificate/Attendance',
            'Dept. Heads Meeting',
            'Clean-up Drives',
            'Tree Planting',
            'Earthquake Drills',
            'Monthly Staff Meeting',
            'Man. Com',
            'Cash Advance',
            'L&D/IDP/DNA',
            'Budget',
            'Others'
          ].contains(doc.category)) {
            folder = DriveFolder.certificates; // Support Function -> certificates
          } else if (doc.mode == 'Office Function MOVs') {
            // For Office Function MOVs with category not in predefined lists (e.g., "Others"),
            // use movs folder as default for Office Function MOVs
            folder = DriveFolder.movs;
          } else if (doc.incoming) {
            folder = DriveFolder.incoming;
          } else {
            folder = DriveFolder.outgoing;
          }

          String? driveUrl;
          String uploadedFileName;

          // Check if this is a web camera image (blob URL that we can't handle)
          if (kIsWeb && upload['localPath'].startsWith('blob:')) {
            // Skip blob URLs - these should have been replaced with bytes in the screens
            // debugPrint('Skipping blob URL upload: ${upload['localPath']}');
            queueManager.updateStatus(upload['documentCode'], upload['filePath'], 'failed', retryCount: 3);
            continue;
          }

          // Check if this is a web file with bytes
          final bytes = upload['bytes'] as List<int>?;
          if (kIsWeb && bytes != null) {
            // Web file with bytes - use uploadFileFromBytes
            final extension = upload['localPath'].split('.').last.toLowerCase();
            final docFileName = extension.isEmpty ? fileName : '$fileName.$extension';
            driveUrl = await GoogleDriveService.uploadFileFromBytes(
              bytes,
              docFileName,
              folder: folder,
            );
            // debugPrint('Web file upload result for ${upload['filePath']}: $driveUrl');
            uploadedFileName = docFileName;
          } else if (!kIsWeb || !upload['localPath'].startsWith('web_')) {
            // Regular file - use existing methods (only for non-web or non-web-prefixed files)
            final file = File(upload['localPath']);
            if (isImage) {
              // For images, use the existing uploadImageToDrive method
              driveUrl = await GoogleDriveService.uploadImageToDrive(
                file,
                fileName,
                folder: folder,
              );
              // debugPrint('Image upload result for ${upload['filePath']}: $driveUrl');
              // For images, the uploaded filename is fileName + extension
              final extension = upload['localPath'].split('.').last.toLowerCase();
              uploadedFileName = extension.isEmpty ? fileName : '$fileName.$extension';
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
              // debugPrint('Document upload result for ${upload['filePath']}: $driveUrl');
              uploadedFileName = docFileName;
            }
          } else {
            // Web file without bytes - this shouldn't happen with our new implementation
            // debugPrint('Web file without bytes: ${upload['localPath']} - skipping');
            queueManager.updateStatus(upload['documentCode'], upload['filePath'], 'failed', retryCount: 3);
            continue;
          }

          if (driveUrl != null) {
            // Update document with the uploaded URL
            final documentCode = upload['documentCode'];
            final isImage = upload['isImage'];

            // Get current document to update URLs
            final docs = await _localDb.fetchDocuments();
            final doc = docs.firstWhere((d) => d.code == documentCode);

            if (isImage) {
              final updatedUrls = [...doc.imageUrls];
              if (!updatedUrls.contains(driveUrl)) {
                updatedUrls.add(driveUrl);
              }
              final updatedLocalPaths = doc.localImagePaths.where((path) => path != upload['localPath']).toList();
              final updatedFileNames = doc.fileNames.contains(uploadedFileName) ? doc.fileNames : [...doc.fileNames, uploadedFileName];
              await _localDb.updateDocument(documentCode, {
                'image_urls': updatedUrls,
                'local_image_paths': updatedLocalPaths,
                'file_names': updatedFileNames,
              });
              // Also update remote database
              await _remoteDb.updateDocument(documentCode, {
                'image_urls': updatedUrls,
                'local_image_paths': updatedLocalPaths,
                'file_names': updatedFileNames,
              });
            } else {
              final updatedUrls = [...doc.fileUrls];
              if (!updatedUrls.contains(driveUrl)) {
                updatedUrls.add(driveUrl);
              }
              final updatedLocalPaths = doc.localFilePaths.where((path) => path != upload['localPath']).toList();
              final updatedFileNames = doc.fileNames.contains(uploadedFileName) ? doc.fileNames : [...doc.fileNames, uploadedFileName];
              await _localDb.updateDocument(documentCode, {
                'file_urls': updatedUrls,
                'local_file_paths': updatedLocalPaths,
                'file_names': updatedFileNames,
              });
              // Also update remote database
              await _remoteDb.updateDocument(documentCode, {
                'file_urls': updatedUrls,
                'local_file_paths': updatedLocalPaths,
                'file_names': updatedFileNames,
              });
            }

            // Define cleanup callback
            Future<void> cleanup() async {
              final isImage = upload['isImage'];
              final docs = await _localDb.fetchDocuments();
              final doc = docs.firstWhere((d) => d.code == documentCode);

              if (isImage) {
                final updatedLocalPaths = doc.localImagePaths.where((path) => path != upload['localPath']).toList();
                await _localDb.updateDocument(documentCode, {
                  'local_image_paths': updatedLocalPaths,
                });
                await _remoteDb.updateDocument(documentCode, {
                  'local_image_paths': updatedLocalPaths,
                });
              } else {
                final updatedLocalPaths = doc.localFilePaths.where((path) => path != upload['localPath']).toList();
                await _localDb.updateDocument(documentCode, {
                  'local_file_paths': updatedLocalPaths,
                });
                await _remoteDb.updateDocument(documentCode, {
                  'local_file_paths': updatedLocalPaths,
                });
              }

            }

            queueManager.markCompletedAndRemove(documentCode, upload['filePath'], onCompleted: cleanup);
            hasCompletedUploads = true;
            documentsWithUploads.add(documentCode);
            // debugPrint('Successfully uploaded ${upload['filePath']} for document $documentCode');
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
    } finally {
      queueManager.endProcessing();
    }
  }

  /// Delete an attachment from Google Drive and update document records
  Future<bool> deleteAttachmentFromDrive(String driveUrl) async {
    try {
      // Delete from Google Drive
      final deleteSuccess = await GoogleDriveService.deleteFile(driveUrl);
      if (!deleteSuccess) {
        print('Failed to delete file from Google Drive: $driveUrl');
        return false;
      }

      // Find the document that contains this driveUrl
      final docs = await _localDb.fetchDocuments();
      Document? doc;
      bool isImage = false;
      int urlIndex = -1;

      for (final document in docs) {
        if (document.imageUrls.contains(driveUrl)) {
          doc = document;
          isImage = true;
          urlIndex = document.imageUrls.indexOf(driveUrl);
          break;
        } else if (document.fileUrls.contains(driveUrl)) {
          doc = document;
          isImage = false;
          urlIndex = document.fileUrls.indexOf(driveUrl);
          break;
        }
      }

      if (doc == null) {
        print('Document containing driveUrl $driveUrl not found');
        return false;
      }

      // Remove URL from appropriate list
      List<String> updatedUrls;
      if (isImage) {
        updatedUrls = doc.imageUrls.where((url) => url != driveUrl).toList();
        await _localDb.updateDocument(doc.code, {'image_urls': updatedUrls});
        if (await isOnline) {
          await _remoteDb.updateDocument(doc.code, {'image_urls': updatedUrls});
        }
      } else {
        updatedUrls = doc.fileUrls.where((url) => url != driveUrl).toList();
        await _localDb.updateDocument(doc.code, {'file_urls': updatedUrls});
        if (await isOnline) {
          await _remoteDb.updateDocument(doc.code, {'file_urls': updatedUrls});
        }
      }

      // Remove corresponding file name if it exists
      if (urlIndex != -1 && urlIndex < doc.fileNames.length) {
        final updatedFileNames = List<String>.from(doc.fileNames)..removeAt(urlIndex);
        await _localDb.updateDocument(doc.code, {'file_names': updatedFileNames});
        if (await isOnline) {
          await _remoteDb.updateDocument(doc.code, {'file_names': updatedFileNames});
        }
      }

      print('Successfully removed attachment from document ${doc.code}');
      return true;
    } catch (e) {
      print('Error deleting attachment: $e');
      return false;
    }
  }

}
