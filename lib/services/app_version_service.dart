import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The release currently published, as recorded in Supabase.
class AppRelease {
  final String version;
  final int buildNumber;
  final String apkUrl;
  final String? releaseNotes;

  /// When true the prompt cannot be dismissed — for releases that fix
  /// something staff must not keep running without.
  final bool mandatory;

  const AppRelease({
    required this.version,
    required this.buildNumber,
    required this.apkUrl,
    this.releaseNotes,
    this.mandatory = false,
  });

  /// Builds a release from the `app_config` key/value rows.
  ///
  /// Only `latest_version` is required. `apk_download_url` falls back to the
  /// Drive link the About screen shipped with, so a missing key cannot silently
  /// suppress the prompt; the rest are optional.
  static AppRelease? fromConfig(Map<String, String> config) {
    final version = config['latest_version']?.trim() ?? '';
    if (version.isEmpty) return null;

    return AppRelease(
      version: version,
      buildNumber: int.tryParse(config['latest_build_number']?.trim() ?? '') ?? 0,
      apkUrl: (config['apk_download_url']?.trim().isNotEmpty ?? false)
          ? config['apk_download_url']!.trim()
          : fallbackApkUrl,
      releaseNotes: config['release_notes'],
      mandatory: (config['update_mandatory'] ?? '').toLowerCase() == 'true',
    );
  }

  /// Used when `apk_download_url` is not set.
  static const String fallbackApkUrl =
      'https://drive.google.com/uc?export=download&id=1WfT-M5Knp4VgkHkUYBWXXk0zqM8DIQX6';
}

/// Checks whether a newer APK has been published.
///
/// The APK itself stays on Google Drive; Supabase holds one row saying which
/// release is current and where to get it. Releasing is then "upload the APK,
/// update the row" — previously the download link was hardcoded in the About
/// screen, so every release needed a code change and a rebuild to point at it.
///
/// Android only. The web build updates itself on the next page load, and iOS
/// cannot install an APK.
class AppVersionService {
  static final AppVersionService _instance = AppVersionService._internal();
  factory AppVersionService() => _instance;
  AppVersionService._internal();

  /// The key/value table the app has always used for this. It predates this
  /// service — an earlier update checker read the same two keys — so pointing
  /// at a new table would have meant migrating data for no reason.
  static const String _table = 'app_config';

  AppRelease? _cached;

  /// The published release, or null when it cannot be read. Never throws: a
  /// failed version check must not stop anyone using the app.
  Future<AppRelease?> fetchLatest({bool forceRefresh = false}) async {
    if (_cached != null && !forceRefresh) return _cached;
    try {
      final rows =
          await Supabase.instance.client.from(_table).select('key, value');
      final config = <String, String>{
        for (final row in (rows as List))
          if (row['key'] != null) '${row['key']}': '${row['value'] ?? ''}',
      };
      return _cached = AppRelease.fromConfig(config);
    } catch (e) {
      debugPrint('AppVersionService: could not read $_table: $e');
      return null;
    }
  }

  /// The release to offer, or null when this build is already current.
  ///
  /// The build number is the authority — it is the value Android itself
  /// compares and the only one guaranteed to increase. The version name is
  /// used only when a row predates build numbers.
  Future<AppRelease?> checkForUpdate({bool forceRefresh = false}) async {
    if (kIsWeb) return null;

    final latest = await fetchLatest(forceRefresh: forceRefresh);
    if (latest == null) return null;

    final info = await PackageInfo.fromPlatform();
    final installedBuild = int.tryParse(info.buildNumber) ?? 0;

    if (latest.buildNumber > 0 && installedBuild > 0) {
      return latest.buildNumber > installedBuild ? latest : null;
    }
    return _isNewerVersion(latest.version, info.version) ? latest : null;
  }

  /// Compares dotted version names ("2.9.0" > "2.8.3"), padding the shorter
  /// one so "2.9" and "2.9.0" are equal rather than different.
  static bool _isNewerVersion(String candidate, String installed) {
    List<int> parts(String v) => v
        .split('+')
        .first
        .split('.')
        .map((p) => int.tryParse(p.trim()) ?? 0)
        .toList();

    final a = parts(candidate);
    final b = parts(installed);
    final length = a.length > b.length ? a.length : b.length;

    for (var i = 0; i < length; i++) {
      final left = i < a.length ? a[i] : 0;
      final right = i < b.length ? b[i] : 0;
      if (left != right) return left > right;
    }
    return false;
  }
}
