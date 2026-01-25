import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'sqlite_database_service.dart';
import 'supabase_service.dart';
import '../models/activity.dart';

class CachedActivityService {
  final SQLiteDatabaseService _localDb = SQLiteDatabaseService();
  final SupabaseService _remoteDb = SupabaseService();
  final Connectivity _connectivity = Connectivity();

  Future<bool> get isOnline async {
    final result = await _connectivity.checkConnectivity();
    return result != ConnectivityResult.none;
  }

  Future<List<Activity>> fetchActivities() async {
    try {
      // If online, fetch from remote and update local cache
      if (await isOnline) {
        try {
          final remoteActivities = await _remoteDb.fetchActivities();
          // Clear local and save remote
          // Since activities are simple, we can replace local with remote
          // For now, just return remote and update local in background
          for (var act in remoteActivities) {
            await _localDb.createActivity(act.copyWith(needsSync: false));
          }
          return remoteActivities;
        } catch (e) {
          print('Failed to fetch from remote: $e');
          // Fall back to local
          return await _localDb.fetchActivities();
        }
      } else {
        // Offline: return local data
        return await _localDb.fetchActivities();
      }
    } catch (e) {
      print('Error fetching activities: $e');
      return [];
    }
  }

  Future<Activity> createActivity(Activity activity) async {
    try {
      // Always save locally first
      final localAct = await _localDb.createActivity(activity);

      // If online, sync to remote immediately
      if (await isOnline) {
        try {
          final remoteAct = await _remoteDb.createActivity(localAct);
          // Update local with remote id if different
          if (remoteAct.id != localAct.id) {
            await _localDb.updateActivity(localAct.id!, {'id': remoteAct.id});
          }
          return remoteAct;
        } catch (e) {
          print('Failed to sync creation to remote: $e');
          // Mark as needing sync since remote failed
          await _localDb.updateActivity(localAct.id!, {'needs_sync': true});
          return localAct.copyWith(needsSync: true);
        }
      } else {
        // Mark as needing sync if offline
        await _localDb.updateActivity(localAct.id!, {'needs_sync': true});
        return localAct.copyWith(needsSync: true);
      }
    } catch (e) {
      print('Error creating activity: $e');
      rethrow;
    }
  }

  Future<void> updateActivity(int activityId, Map<String, dynamic> updates) async {
    try {
      // Update locally first
      await _localDb.updateActivity(activityId, updates);

      // If online, sync to remote
      if (await isOnline) {
        try {
          await _remoteDb.updateActivity(activityId, updates);
        } catch (e) {
          print('Failed to sync update to remote: $e');
          // Update is saved locally, will sync later
        }
      }
    } catch (e) {
      print('Error updating activity: $e');
      rethrow;
    }
  }

  Future<void> deleteActivity(int activityId) async {
    try {
      // Check if online
      if (await isOnline) {
        // Online: Delete from remote first
        try {
          await _remoteDb.deleteActivity(activityId);
          // Delete locally after successful remote deletion
          await _localDb.deleteActivity(activityId);
          debugPrint('Activity $activityId deleted successfully (online)');
        } catch (e) {
          print('Failed to delete from remote: $e');
          rethrow;
        }
      } else {
        // Offline: For now, just delete locally (no pending deletions for activities yet)
        await _localDb.deleteActivity(activityId);
        debugPrint('Activity $activityId deleted locally (offline)');
      }
    } catch (e) {
      print('Error deleting activity: $e');
      rethrow;
    }
  }

  Future<void> syncPendingChanges() async {
    if (!(await isOnline)) return;

    try {
      // Sync unsynced activities
      final localActivities = await _localDb.fetchActivities();
      final unsynced = localActivities.where((act) => act.needsSync).toList();

      for (var act in unsynced) {
        try {
          // For simplicity, try to create on remote (assuming no duplicates)
          await _remoteDb.createActivity(act);
          // Mark as synced
          await _localDb.updateActivity(act.id!, {'needs_sync': false});
        } catch (e) {
          print('Failed to sync activity ${act.id}: $e');
        }
      }
    } catch (e) {
      print('Error syncing pending changes: $e');
    }
  }
}
