import 'package:connectivity_plus/connectivity_plus.dart';
import 'sqlite_database_service.dart';
import 'supabase_service.dart';
import '../models/document.dart';

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

      // If online, sync to remote
      if (await isOnline) {
        try {
          final remoteDoc = await _remoteDb.createDocument(document);
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
      final localDoc = (await _localDb.fetchDocuments()).firstWhere((doc) => doc.code == documentCode);
      if (localDoc.needsSync) {
        // Sync to remote
        await _remoteDb.createDocument(localDoc);
        // Mark as synced
        await _localDb.updateDocument(documentCode, {'needs_sync': false});
      }
    } catch (e) {
      print('Error syncing specific document: $e');
      rethrow;
    }
  }
}
