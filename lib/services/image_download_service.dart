import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_image_gallery_saver/flutter_image_gallery_saver.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/google_drive_service.dart';
import 'package:device_info_plus/device_info_plus.dart';


class ImageDownloadService {
  static Future<void> downloadAndSave(String imageUrl) async {
    if (imageUrl.isEmpty) {
      throw Exception('No image to download');
    }

    // Normalize Google Drive fileId
    final normalizedFileId =
        GoogleDriveService.normalizeFileId(imageUrl);

    final downloadUrl =
        'https://drive.google.com/uc?id=$normalizedFileId&export=download';

    if (kIsWeb) {
      await _handleWebDownload(downloadUrl);
    } else {
      await _handleMobileDownload(downloadUrl);
    }
  }


  static Future<void> _handleWebDownload(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not open download link');
    }
  }

  /// 📱 MOBILE DOWNLOAD
  static Future<void> _handleMobileDownload(String url) async {
    final hasPermission = await _requestPermission();

    if (!hasPermission) {
      throw Exception(
          'Storage permission is needed to save the image. Allow it in '
          'Settings > Apps > FileTrack Hub > Permissions.');
    }

    final tempDir = await getTemporaryDirectory();
    final fileName =
        'doc_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final tempPath = '${tempDir.path}/$fileName';

    // Download file
    await Dio().download(url, tempPath);

    // Save to gallery
    final bytes = await File(tempPath).readAsBytes();
    await FlutterImageGallerySaver.saveImage(bytes);

    // Cleanup
    try {
      await File(tempPath).delete();
    } catch (_) {}
  }

  /// 🔐 PERMISSION HANDLER
  static Future<bool> _requestPermission() async {
    if (!Platform.isAndroid) {
      final status = await Permission.photos.request();
      return status.isGranted || status.isLimited;
    }

    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = androidInfo.version.sdkInt;

    // Android 10 (API 29) and up save through MediaStore, which needs no
    // permission at all — the app writes its own new image rather than reading
    // the user's library.
    //
    // Asking anyway was what broke downloading. On 13+ this requested
    // READ_MEDIA_IMAGES, which AndroidManifest.xml deliberately strips with
    // tools:node="remove" (the app uses the system Photo Picker instead). A
    // permission the app does not declare can never be granted, so the request
    // failed instantly, no prompt ever appeared, and the user saw only
    // "Photos permission required".
    if (sdkInt >= 29) return true;

    // Android 9 and below genuinely need WRITE_EXTERNAL_STORAGE, which the
    // manifest declares with maxSdkVersion="29".
    final status = await Permission.storage.request();
    return status.isGranted;
  }

}
