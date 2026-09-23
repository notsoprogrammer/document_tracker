import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_version_service.dart';

/// Offers the published release and sends the user to the APK.
///
/// Android installs it through the browser's downloader, so this only opens
/// the link — the user still confirms the install themselves.
class UpdateAvailableDialog extends StatelessWidget {
  final AppRelease release;
  final String installedVersion;

  const UpdateAvailableDialog({
    super.key,
    required this.release,
    required this.installedVersion,
  });

  /// Shows the prompt if one is due. Returns whether it was shown.
  static Future<bool> showIfAvailable(
    BuildContext context, {
    required String installedVersion,
    bool forceRefresh = false,
  }) async {
    final release =
        await AppVersionService().checkForUpdate(forceRefresh: forceRefresh);
    if (release == null || !context.mounted) return false;

    await showDialog(
      context: context,
      // A mandatory update cannot be dismissed by tapping away.
      barrierDismissible: !release.mandatory,
      builder: (_) => UpdateAvailableDialog(
        release: release,
        installedVersion: installedVersion,
      ),
    );
    return true;
  }

  Future<void> _download(BuildContext context) async {
    final uri = Uri.parse(release.apkUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (context.mounted && !release.mandatory) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final notes = release.releaseNotes?.trim() ?? '';

    return PopScope(
      canPop: !release.mandatory,
      child: AlertDialog(
        title: Text(
            release.mandatory ? 'Update required' : 'A new version is available'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You have $installedVersion. Version ${release.version} is now available.',
              style: const TextStyle(fontSize: 13.5),
            ),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text("What's new",
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(notes, style: const TextStyle(fontSize: 13)),
            ],
            const SizedBox(height: 12),
            const Text(
              'The download opens in your browser. Open it when it finishes to install.',
              style: TextStyle(fontSize: 11.5, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          if (!release.mandatory)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Later'),
            ),
          ElevatedButton(
            onPressed: () => _download(context),
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }
}
