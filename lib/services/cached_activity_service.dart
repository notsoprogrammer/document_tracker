import 'package:connectivity_plus/connectivity_plus.dart';
import 'sqlite_database_service_mobile.dart' if (dart.library.html) 'sqlite_database_service_web.dart';
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
      // Try to fetch from local cache first
      var localActivities = await _localDb.fetchActivities();

      // If online, sync with remote and merge data
      if (await isOnline) {
        try {
          final remoteActivities = await _remoteDb.fetchActivities();

          // Deduplicate local activities
          final Map<int, Activity> localMap = {};
          for (var act in localActivities) {
            if (act.id != null) {
              localMap[act.id!] = act;
            }
          }
          localActivities = localMap.values.toList();

          // Create a map of remote activities by id for quick lookup
          final remoteMap = {for (var act in remoteActivities) act.id: act};

          // Merge activities: prefer remote data, but keep local-only activities
          var mergedActivities = <Activity>[];

          // Add all remote activities
          mergedActivities.addAll(remoteActivities);

          // Add local activities that don't exist remotely (offline additions)
          for (var localAct in localActivities) {
            if (!remoteMap.containsKey(localAct.id)) {
              mergedActivities.add(localAct);
            } else {
              // If local activity exists in remote and is marked as needing sync, mark as synced
              if (localAct.needsSync) {
                await _localDb.updateActivity(localAct.id!, {'needs_sync': 0});
              }
            }
          }

          // Deduplicate by id to prevent duplicates
          final Map<int, Activity> uniqueMap = {};
          for (var act in mergedActivities) {
            if (act.id != null) {
              uniqueMap[act.id!] = act;
            }
          }
          mergedActivities = uniqueMap.values.toList();

          // Update local cache with merged data
          // Clear and re-add activities
          for (var act in localActivities) {
            if (act.id != null) {
              await _localDb.deleteActivity(act.id!);
            }
          }
          for (var act in mergedActivities) {
            await _localDb.createActivity(act);
          }

          return mergedActivities;
        } catch (e) {
          // Return local data if remote sync fails
          return localActivities;
        }
      } else {
        // Offline: return cached data
        return localActivities;
      }
    } catch (e) {
      return [];
    }
  }

  Future<Activity> createActivity(Activity activity) async {
    try {
      // Always save locally first
      final localActivity = await _localDb.createActivity(activity);

      // If online, sync to remote immediately
      if (await isOnline) {
        try {
          final remoteActivity = await _remoteDb.createActivity(activity);

          // Update local with remote data if needed
          return remoteActivity;
        } catch (e) {
          // Mark as needing sync since remote failed
          await _localDb.updateActivity(localActivity.id!, {'needs_sync': 1});
          return localActivity.copyWith(needsSync: true);
        }
      } else {
        // Mark as needing sync if offline
        await _localDb.updateActivity(localActivity.id!, {'needs_sync': 1});
        return localActivity.copyWith(needsSync: true);
      }
    } catch (e) {
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
          // Update is saved locally, will sync later
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteActivity(int activityId) async {
    try {
      // If online, delete from remote first
      if (await isOnline) {
        try {
          await _remoteDb.deleteActivity(activityId);
        } catch (e) {
          rethrow;
        }
      }

      // Delete locally
      await _localDb.deleteActivity(activityId);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> syncPendingChanges() async {
    if (!(await isOnline)) return;

    try {
      final localActivities = await _localDb.fetchActivities();
      final unsynced = localActivities.where((act) => act.needsSync).toList();

      for (var act in unsynced) {
        try {
          if (act.id != null) {
            await _remoteDb.createActivity(act);
            await _localDb.updateActivity(act.id!, {'needs_sync': 0});
          }
        } catch (e) {
        }
      }
    } catch (e) {
    }
  }
}
