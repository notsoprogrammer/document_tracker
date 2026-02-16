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
      throw Exception('Photos permission required');
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

  final deviceInfo = DeviceInfoPlugin();
  final androidInfo = await deviceInfo.androidInfo;
  final sdkInt = androidInfo.version.sdkInt;

  if (sdkInt >= 33) {
    // Android 13+
    final status = await Permission.photos.request();
    return status.isGranted || status.isLimited;
  } else {
    // Android 12 and below
    final status = await Permission.storage.request();
    return status.isGranted;
  }
}

}
