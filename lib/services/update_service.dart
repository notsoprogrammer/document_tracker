import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UpdateInfo {
  final String latestVersion;
  final String downloadUrl;
  const UpdateInfo({required this.latestVersion, required this.downloadUrl});
}

class UpdateService {
  static const String appName = 'FileTrack';

  /// Steps shown to the user before or when the APK installer is blocked.
  static const String installPermissionSteps =
      'To install the $appName update you need to allow installation '
      'from unknown sources:\n\n'
      '1. Tap "Settings" on the permission prompt that appears.\n'
      '2. Enable "Allow from this source".\n'
      '3. Go back — the installer will continue automatically.\n\n'
      'Alternatively: Settings → Apps → Special app access\n'
      '→ Install unknown apps → select your browser or file manager → Allow.';

  static Future<UpdateInfo?> checkForUpdate() async {
    if (kIsWeb) return null;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final rows = await Supabase.instance.client
          .from('app_config')
          .select('key, value');

      final config = <String, String>{
        for (final row in (rows as List)) row['key'] as String: row['value'] as String,
      };

      final latestVersion = config['latest_version'];
      final downloadUrl = config['apk_download_url'];

      if (latestVersion == null || downloadUrl == null) return null;
      if (!_isNewer(latestVersion, currentVersion)) return null;

      return UpdateInfo(latestVersion: latestVersion, downloadUrl: downloadUrl);
    } catch (e) {
      return null;
    }
  }

  static Future<void> downloadAndInstall(
    String downloadUrl, {
    void Function(double progress)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final savePath = '${dir.path}/update.apk';

    await Dio().download(
      downloadUrl,
      savePath,
      onReceiveProgress: (received, total) {
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      },
    );

    final result = await OpenFile.open(
      savePath,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type != ResultType.done) {
      throw Exception(
        'Could not open the $appName installer: ${result.message}\n\n'
        '$installPermissionSteps',
      );
    }
  }

  static bool _isNewer(String latest, String current) {
    final l = latest.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final c = current.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    for (int i = 0; i < 3; i++) {
      final lv = i < l.length ? l[i] : 0;
      final cv = i < c.length ? c[i] : 0;
      if (lv > cv) return true;
      if (lv < cv) return false;
    }
    return false;
  }
}
