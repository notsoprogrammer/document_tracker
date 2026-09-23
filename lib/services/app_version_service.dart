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

  factory AppRelease.fromJson(Map<String, dynamic> json) => AppRelease(
        version: json['version']?.toString() ?? '',
        buildNumber: int.tryParse(json['build_number']?.toString() ?? '') ?? 0,
        apkUrl: json['apk_url']?.toString() ?? '',
        releaseNotes: json['release_notes']?.toString(),
        mandatory: json['mandatory'] == true,
      );
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

  static const String _table = 'app_version';

  AppRelease? _cached;

  /// The published release, or null when it cannot be read. Never throws: a
  /// failed version check must not stop anyone using the app.
  Future<AppRelease?> fetchLatest({bool forceRefresh = false}) async {
    if (_cached != null && !forceRefresh) return _cached;
    try {
      final rows = await Supabase.instance.client
          .from(_table)
          .select()
          .order('build_number', ascending: false)
          .limit(1);
      if (rows.isEmpty) return null;
      return _cached = AppRelease.fromJson(Map<String, dynamic>.from(rows.first));
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
    if (latest == null || latest.apkUrl.isEmpty) return null;

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
