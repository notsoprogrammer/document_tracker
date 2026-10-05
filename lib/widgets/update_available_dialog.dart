import 'package:flutter/material.dart';
import '../services/app_version_service.dart';

/// Offers the published release, downloads it, and opens the installer.
///
/// The download happens here rather than in the browser so the progress is
/// visible and Android's install screen opens on its own — the user never has
/// to go looking for a downloaded file.
class UpdateAvailableDialog extends StatefulWidget {
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

  @override
  State<UpdateAvailableDialog> createState() => _UpdateAvailableDialogState();
}

class _UpdateAvailableDialogState extends State<UpdateAvailableDialog> {
  bool _downloading = false;
  double _progress = 0;
  String? _error;

  /// Set when the download succeeded but Android would not open the installer
  /// without "install unknown apps". The fix is a settings screen, not a
  /// retry, so the dialog offers that instead.
  bool _needsInstallPermission = false;

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
      _needsInstallPermission = false;
    });

    try {
      await AppVersionService().downloadAndInstall(
        widget.release.apkUrl,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      // The installer is now in front of the user; this dialog has done its job.
      if (mounted && !widget.release.mandatory) Navigator.of(context).pop();
    } on InstallPermissionException catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _needsInstallPermission = true;
        _error = e.toString();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  /// Sends the user to Android's "install unknown apps" screen, then — if they
  /// granted it — carries straight on rather than making them start again.
  Future<void> _grantInstallPermission() async {
    final granted = await AppVersionService().requestInstallPermission();
    if (!mounted) return;
    if (granted) {
      await _download();
    } else {
      setState(() => _error =
          'Permission is still off. Turn on "Allow from this source" to '
          'install the update.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final release = widget.release;
    final notes = release.releaseNotes?.trim() ?? '';
    final percent = (_progress * 100).clamp(0, 100).toStringAsFixed(0);

    return PopScope(
      // Neither a mandatory update nor a download in progress should be
      // dismissed by the back button.
      canPop: !release.mandatory && !_downloading,
      child: AlertDialog(
        title: Text(
            release.mandatory ? 'Update required' : 'A new version is available'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You have ${widget.installedVersion}. Version ${release.version} is now available.',
              style: const TextStyle(fontSize: 13.5),
            ),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text("What's new",
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(notes, style: const TextStyle(fontSize: 13)),
            ],
            if (_downloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                minHeight: 6,
              ),
              const SizedBox(height: 6),
              Text(
                _progress > 0 ? 'Downloading… $percent%' : 'Starting download…',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ] else ...[
              const SizedBox(height: 12),
              const Text(
                'Android will ask once for permission to install apps from '
                'FileTrack Hub. Allow it, then tap Install.',
                style: TextStyle(fontSize: 11.5, color: Colors.black54),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(fontSize: 12, color: Colors.red[700])),
            ],
            if (_needsInstallPermission) ...[
              const SizedBox(height: 4),
              const Text(
                'Android will open its settings. Turn on "Allow from this '
                'source", then come back.',
                style: TextStyle(fontSize: 11.5, color: Colors.black54),
              ),
            ],
          ],
        ),
        actions: [
          if (!release.mandatory && !_downloading)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Later'),
            ),
          if (_needsInstallPermission)
            ElevatedButton(
              onPressed: _downloading ? null : _grantInstallPermission,
              child: const Text('Open settings'),
            )
          else
            ElevatedButton(
              onPressed: _downloading ? null : _download,
              child: Text(_error != null ? 'Try again' : 'Download'),
            ),
        ],
      ),
    );
  }
}
