import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'dart:io';

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

  /// Save image locally in the app's documents directory
  static Future<String?> saveImageLocally(File imageFile, String uniqueId) async {
    try {
      // Get the app's documents directory
      final appDocDir = await getApplicationDocumentsDirectory();

      // Create images/documents directory if it doesn't exist
      final imagesDir = Directory(path.join(appDocDir.path, 'images', 'documents'));
      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }

      // Create filename with timestamp for uniqueness
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'doc_${uniqueId}_$timestamp.jpg';
      final localPath = path.join(imagesDir.path, fileName);

      // Copy the image file to local storage
      final localFile = await imageFile.copy(localPath);

      print('Image saved locally: ${localFile.path}');
      return localFile.path;
    } catch (e) {
      print('Error saving image locally: $e');
      return null;
    }
  }

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

  /// Save image both locally and to Google Drive
  static Future<ImageSaveResult> saveImageWithBackup(
    File imageFile,
    String uniqueId, {
    DriveFolder folder = DriveFolder.incoming,
  }) async {
    String? localPath;
    String? driveId;
    String? driveUrl;
    bool localSuccess = false;
    bool driveSuccess = false;

    // Always try to save locally first
    localPath = await saveImageLocally(imageFile, uniqueId);
    localSuccess = localPath != null;

    // Try to upload to Google Drive
    try {
      driveId = await uploadImageToDrive(
        imageFile,
        uniqueId,
        folder: folder,
      );
      driveSuccess = driveId != null;

      // Generate public URL if upload was successful
      if (driveId != null) {
        driveUrl = generatePublicUrl(driveId);
      }
    } catch (e) {
      print('Google Drive upload failed, but local save succeeded: $e');
      driveSuccess = false;
    }

    return ImageSaveResult(
      localPath: localPath,
      driveId: driveId,
      driveUrl: driveUrl,
      localSaveSuccess: localSuccess,
      driveSaveSuccess: driveSuccess,
    );
  }

  /// Get local image file if it exists
  static Future<File?> getLocalImage(String localPath) async {
    try {
      final file = File(localPath);
      if (await file.exists()) {
        return file;
      }
      return null;
    } catch (e) {
      print('Error getting local image: $e');
      return null;
    }
  }

  /// Get all local image files for a specific document
  static Future<List<File>> getLocalImagesForDocument(String uniqueId) async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory(path.join(appDocDir.path, 'images', 'documents'));

      if (!await imagesDir.exists()) {
        return [];
      }

      final files = await imagesDir.list().toList();
      final imageFiles = files
          .whereType<File>()
          .where((file) => path.basename(file.path).startsWith('doc_$uniqueId'))
          .toList();

      return imageFiles;
    } catch (e) {
      print('Error getting local images for document: $e');
      return [];
    }
  }

  /// Clean up old local images (older than specified days)
  static Future<void> cleanupOldImages({int daysOld = 30}) async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory(path.join(appDocDir.path, 'images', 'documents'));

      if (!await imagesDir.exists()) {
        return;
      }

      final cutoffDate = DateTime.now().subtract(Duration(days: daysOld));
      final files = await imagesDir.list().toList();

      for (final file in files) {
        if (file is File) {
          final stat = await file.stat();
          if (stat.modified.isBefore(cutoffDate)) {
            await file.delete();
            print('Deleted old image: ${file.path}');
          }
        }
      }
    } catch (e) {
      print('Error cleaning up old images: $e');
    }
  }

  /// Get the size of local images directory in bytes
  static Future<int> getLocalImagesSize() async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory(path.join(appDocDir.path, 'images', 'documents'));

      if (!await imagesDir.exists()) {
        return 0;
      }

      int totalSize = 0;
      final files = await imagesDir.list(recursive: true).toList();

      for (final file in files) {
        if (file is File) {
          final stat = await file.stat();
          totalSize += stat.size;
        }
      }

      return totalSize;
    } catch (e) {
      print('Error calculating local images size: $e');
      return 0;
    }
  }

  /// Legacy method for backward compatibility
  @deprecated
  static Future<String?> uploadImage(File imageFile, String uniqueId) async {
    final result = await saveImageWithBackup(imageFile, uniqueId);
    return result.driveId;
  }
}
