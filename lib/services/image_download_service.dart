import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';
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

    // Fetch through the same proxy the viewer uses, NOT drive.google.com
    // directly. Attachments are uploaded by a service account and are not
    // shared publicly, so 'uc?export=download' returns Google's sign-in page
    // instead of the file — which the old code happily wrote to a .jpg and
    // handed to the gallery saver, so the download silently did nothing.
    final downloadUrl = GoogleDriveService.generateProxyUrl(normalizedFileId);

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

    final response = await Dio().get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: true,
        // Read the body on an error status too, so the check below can report
        // what came back rather than throwing something opaque.
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    if (response.statusCode != 200 || response.data == null) {
      throw Exception(
          'Could not download the image (server said ${response.statusCode}).');
    }

    // Anything that is not an image means the request was answered by an error
    // or sign-in page. Saving those bytes would produce a broken file and look
    // like nothing happened at all.
    final contentType = response.headers.value('content-type') ?? '';
    if (!contentType.startsWith('image/')) {
      throw Exception(
          'The file could not be read from Drive. It may have been moved or '
          'deleted.');
    }

    await FlutterImageGallerySaver.saveImage(
        Uint8List.fromList(response.data!));
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
