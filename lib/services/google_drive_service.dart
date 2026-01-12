import 'dart:io';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Result class for image operations
class ImageSaveResult {
  final String? localPath;
  final String? driveId;
  final String? driveUrl;
  final bool localSaveSuccess;
  final bool driveSaveSuccess;

  ImageSaveResult({
    this.localPath,
    this.driveId,
    this.driveUrl,
    required this.localSaveSuccess,
    required this.driveSaveSuccess,
  });
}

enum DriveFolder { incoming, outgoing }

class GoogleDriveService {
  // Use your folder IDs - replace these with your actual Google Drive folder IDs
  static const String _incomingFolderId = '1m8qaIDu1P9pBk3sIiOwqis3vL1xXjsah';
  static const String _outgoingFolderId = '1EkHogt5qXNjMjjWBspwseOBoKyrxnfFE';

  /// Upload image to Google Drive (original functionality)
  static Future<String?> uploadImageToDrive(
    File imageFile,
    String fileNameOrUniqueId, {
    DriveFolder folder = DriveFolder.incoming,
  }) async {
    try {
      // Load service account credentials
      final serviceAccountJson = await rootBundle.loadString('assets/service_account_key.json');
      final credentials = ServiceAccountCredentials.fromJson(serviceAccountJson);

      // Get authenticated HTTP client
      final client = await clientViaServiceAccount(
        credentials,
        [drive.DriveApi.driveFileScope]
      );

      // Create Drive API client
      final driveApi = drive.DriveApi(client);

      // Resolve target folder
      final targetFolderId = folder == DriveFolder.outgoing
          ? _outgoingFolderId
          : _incomingFolderId;

      // Build file name if you currently do so elsewhere, keep it; otherwise:
      final fileName = fileNameOrUniqueId.endsWith('.jpg')
          ? fileNameOrUniqueId
          : 'doc_${fileNameOrUniqueId}.jpg';

      // Check if file already exists
      final query = "name = '$fileName' and '$targetFolderId' in parents and trashed = false";
      final existingFiles = await driveApi.files.list(
        q: query,
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
        $fields: 'files(id,name)',
      );

      final media = drive.Media(imageFile.openRead(), await imageFile.length());

      if (existingFiles.files?.isNotEmpty == true) {
        // Update
        final fileId = existingFiles.files!.first.id!;
        final updated = await driveApi.files.update(
          drive.File(name: fileName, parents: [targetFolderId]),
          fileId,
          uploadMedia: media,
          supportsAllDrives: true,
        );
        // Make the file public
        if (updated.id != null) {
          await _makeFilePublic(driveApi, updated.id!);
        }
        return updated.id;
      } else {
        // Create
        final driveFile = drive.File()
          ..name = fileName
          ..parents = [targetFolderId];
        final created = await driveApi.files.create(
          driveFile,
          uploadMedia: media,
          supportsAllDrives: true,
        );
        // Make the file public
        if (created.id != null) {
          await _makeFilePublic(driveApi, created.id!);
        }
        return created.id;
      }

    } catch (e) {
      print('Error uploading to Google Drive: $e');
      return null;
    }
  }

  /// Make a file in Google Drive public
  static Future<void> _makeFilePublic(drive.DriveApi driveApi, String fileId) async {
    try {
      // Create a permission to make the file public
      final permission = drive.Permission()
        ..role = 'reader'
        ..type = 'anyone';

      // Apply the permission to the file
      await driveApi.permissions.create(
        permission,
        fileId,
        supportsAllDrives: true,
      );
    } catch (e) {
      print('Error making file public: $e');
      // We don't rethrow here, as the upload itself was successful
    }
  }

  /// Generate a public URL for a file given its Google Drive file ID
  static String generatePublicUrl(String fileId) {
    return 'https://drive.google.com/uc?id=$fileId';
  }

  /// Upload file and return public URL
  static Future<String?> uploadFile(String filePath, bool isIncoming, String baseFileName) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final extension = filePath.split('.').last.toLowerCase();
      final fileName = extension.isEmpty ? baseFileName : '$baseFileName.$extension';

      final folder = isIncoming ? DriveFolder.incoming : DriveFolder.outgoing;

      final driveId = await uploadImageToDrive(file, fileName, folder: folder);
      if (driveId != null) {
        return generatePublicUrl(driveId);
      }
      return null;
    } catch (e) {
      print('Error uploading file: $e');
      return null;
    }
  }

  /// Upload multiple files and return list of public URLs
  static Future<List<String>> uploadMultipleFiles(List<String> filePaths, bool isIncoming, String baseFileName) async {
    final uploadedUrls = <String>[];

    for (int i = 0; i < filePaths.length; i++) {
      final fileName = filePaths.length == 1 ? baseFileName : '$baseFileName\_${i + 1}';
      final url = await uploadFile(filePaths[i], isIncoming, fileName);
      if (url != null) {
        uploadedUrls.add(url);
      }
    }

    return uploadedUrls;
  }
}
