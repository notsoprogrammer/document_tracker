import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/supabase_config.dart';

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

enum DriveFolder { incoming, outgoing, flagCeremony, attendance, movs, certificates, locationalZoning, cdc, spDocuments, reclassification }

class GoogleDriveService {
  // Use your folder IDs - replace these with your actual Google Drive folder IDs
  static const String _incomingFolderId = '1m8qaIDu1P9pBk3sIiOwqis3vL1xXjsah';
  static const String _outgoingFolderId = '1EkHogt5qXNjMjjWBspwseOBoKyrxnfFE';
  static const String _flagCeremonyFolderId = '1KYbOWoQZZIAbT69t7elduQLiITdFK45Y';
  static const String _attendanceFolderId = '124-6z-XwOaUtoQWUsqdnt8J2Urns4Cjk';
  static const String _movsFolderId = '1q92hYeqzrZhgoXhu0e8-3BuzFYMdVFPr';
  static const String _certificatesFolderId = '1pEBNcA3CjBeoABvbcAGxTa41Jaml76tn';
  static const String _locationalZoningFolderId = '10IwsvYcEWCK69OHmQBd0lgqyup8Hgmwo';
  static const String _cdcFolderId = '1cO9b-mQB9YrbjBdnnoxnsIVhqp_QYuKL';
  static const String _spDocumentsFolderId = '1wAmcxzIY271M7STbKwGCwxW4_-uoViB-';
  static const String _reclassificationFolderId = '1akueBVl9oRIporDPYuvCOnVmn14hFtqR';

  // Supabase function URL for secure uploads
  static const String _supabaseFunctionUrl = SupabaseConfig.uploadToDriveFunctionUrl;

 static String getFolderId(String category) {
    // Determine folder based on the selected type (category)
    if ([
      'Sectoral Plans',
      'Ecological Profile',
      'Research/Studies/Trainings',
      'CLUP Zoning Reclassification',
      'CSOs',
      'CDC – Resolution',
      'CDC – Minutes',
      'CDC – Attendance',
      'AIP',
      'Barangay – AIP',
      'Barangay– GAD',
      'Zoning/Loc. Clearance',
      'Zoning/Loc. Certification',
    ].contains(category)) {
      return _attendanceFolderId; // Core Function -> attendance
    } else if ([
      'PR/PPMP',
      'Liquidation/ Reimbursement',
      'PFMAT',
    ].contains(category)) {
      return _movsFolderId; // Strategic Function -> movs
    } else if ([
      'DTR',
      'Monthly Accomplishment Report',
      'Quarterly Accomplishment Report',
      'OPCR',
      'Certificate/Attendance',
      'Dept. Heads Meeting',
      'Clean-up Drives',
      'Tree Planting',
      'Earthquake Drills',
      'Monthly Staff Meeting',
      'Man. Com',
      'Cash Advance',
      'L&D/IDP/DNA',
      'Budget',
      'Others',
    ].contains(category)) {
      return _certificatesFolderId; // Support Function -> certificates
    } else {
      throw Exception('Unknown category: $category');
    }
  }

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
      // Build file name if you currently do so elsewhere, keep it; otherwise:
      final fileName = fileNameOrUniqueId.endsWith('.jpg')
          ? fileNameOrUniqueId
          : 'doc_${fileNameOrUniqueId}.jpg';

      // Read file bytes and upload via Supabase
      final bytes = await imageFile.readAsBytes();
      return await _uploadFileFromBytesViaSupabase(bytes, fileName, folder: folder);
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


  static String generatePublicUrl(String fileId) {
    return 'https://drive.google.com/uc?id=$fileId';
  }

  /// Normalize attachment value to extract fileId if it's a legacy Google Drive URL
  static String normalizeFileId(String attachmentValue) {
    if (attachmentValue.contains('drive.google.com')) {
      final uri = Uri.parse(attachmentValue);
      if (attachmentValue.contains('/file/d/')) {
        // Format: https://drive.google.com/file/d/FILE_ID/view
        final segments = uri.pathSegments;
        final fileIndex = segments.indexOf('d');
        if (fileIndex != -1 && fileIndex + 1 < segments.length) {
          return segments[fileIndex + 1];
        }
      } else if (attachmentValue.contains('uc?id=')) {
        // Format: https://drive.google.com/uc?id=FILE_ID
        final fileId = uri.queryParameters['id'];
        return fileId ?? attachmentValue;
      } else if (attachmentValue.contains('open?id=')) {
        // Format: https://drive.google.com/open?id=FILE_ID
        final fileId = uri.queryParameters['id'];
        return fileId ?? attachmentValue;
      } else if (attachmentValue.contains('folders/')) {
        // Format: https://drive.google.com/folders/FOLDER_ID
        final segments = uri.pathSegments;
        final folderIndex = segments.indexOf('folders');
        if (folderIndex != -1 && folderIndex + 1 < segments.length) {
          return segments[folderIndex + 1];
        }
      }
    }
    // Assume it's already a file ID if it matches the pattern
    if (RegExp(r'^[a-zA-Z0-9_-]{20,}$').hasMatch(attachmentValue)) {
      return attachmentValue;
    }
    return attachmentValue;
  }

  /// Generate a proxy URL for a file given its Google Drive file ID (for CORS-free access)
  static String generateProxyUrl(String fileId) {
    return '${SupabaseConfig.proxyImageFunctionUrl}?fileId=$fileId';
  }
  /// Upload file and return public URL (generic method for any file type)
  static Future<String?> uploadFile(String filePath, bool isIncoming, String baseFileName) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final extension = filePath.split('.').last.toLowerCase();
      final fileName = extension.isEmpty ? baseFileName : '$baseFileName.$extension';

      final folder = isIncoming ? DriveFolder.incoming : DriveFolder.outgoing;

      final driveUrl = await uploadFileToDrive(file, fileName, folder: folder);
      return driveUrl;
    } catch (e) {
      print('Error uploading file: $e');
      return null;
    }
  }

  /// Upload file from bytes (for web compatibility)
  static Future<String?> uploadFileFromBytes(List<int> bytes, String fileName, {DriveFolder folder = DriveFolder.incoming}) async {
    // Always use Supabase function to keep service account secure
    return _uploadFileFromBytesViaSupabase(bytes, fileName, folder: folder);
  }

  /// Upload any file to Google Drive (generic method)
  static Future<String?> uploadFileToDrive(
    File file,
    String fileName, {
    DriveFolder folder = DriveFolder.incoming,
  }) async {
    try {
      // Read file bytes and upload via Supabase
      final bytes = await file.readAsBytes();
      return await _uploadFileFromBytesViaSupabase(bytes, fileName, folder: folder);
    } catch (e) {
      print('Error uploading file to Google Drive: $e');
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
      driveUrl = driveId; // For backward compatibility, driveUrl now holds fileId
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

  /// Upload file from bytes via Supabase function (for web builds)
  static Future<String?> _uploadFileFromBytesViaSupabase(List<int> bytes, String fileName, {DriveFolder folder = DriveFolder.incoming}) async {
    try {
      // Resolve target folder
      final targetFolderId = folder == DriveFolder.outgoing
          ? _outgoingFolderId
          : folder == DriveFolder.flagCeremony
              ? _flagCeremonyFolderId
              : folder == DriveFolder.attendance
                  ? _attendanceFolderId
                  : folder == DriveFolder.movs
                      ? _movsFolderId
                      : folder == DriveFolder.certificates
                          ? _certificatesFolderId
                          : folder == DriveFolder.locationalZoning
                              ? _locationalZoningFolderId
                              : folder == DriveFolder.cdc
                                  ? _cdcFolderId
                                  : folder == DriveFolder.spDocuments
                                      ? _spDocumentsFolderId
                                      : folder == DriveFolder.reclassification
                                          ? _reclassificationFolderId
                                          : _incomingFolderId;

      // Convert bytes to base64
      final base64Data = base64Encode(bytes);

      // Prepare request payload
      final payload = {
        'fileName': fileName,
        'fileData': base64Data,
        'folderId': targetFolderId,
        'mimeType': _getMimeType(fileName),
      };

      // Make request to Supabase function (45s timeout to handle large images)
      final response = await http.post(
        Uri.parse(_supabaseFunctionUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${SupabaseConfig.supabaseAnonKey}',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return result['fileId'];
        } else {
          print('Supabase function error: ${result['error']}');
          return null;
        }
      } else {
        print('Supabase function failed with status: ${response.statusCode}');
        print('Response: ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error uploading via Supabase: $e');
      return null;
    }
  }

  /// Get MIME type based on file extension
  static String _getMimeType(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default:
        return 'application/octet-stream';
    }
  }

  /// Delete a file from Google Drive using Supabase function
  static Future<bool> deleteFile(String fileId) async {
    try {
      // Prepare request payload for deletion
      final payload = {
        'action': 'delete',
        'fileId': fileId,
      };

      // Make request to Supabase function (45s timeout to handle large images)
      final response = await http.post(
        Uri.parse(_supabaseFunctionUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${SupabaseConfig.supabaseAnonKey}',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          print('Successfully deleted file from Google Drive: $fileId');
          return true;
        } else {
          print('Supabase function error deleting file: ${result['error']}');
          return false;
        }
      } else {
        print('Supabase function failed with status: ${response.statusCode}');
        print('Response: ${response.body}');
        return false;
      }
    } catch (e) {
      print('Error deleting file from Google Drive: $e');
      return false;
    }
  }

  /// Legacy method for backward compatibility
  @deprecated
  static Future<String?> uploadImage(File imageFile, String uniqueId) async {
    final result = await saveImageWithBackup(imageFile, uniqueId);
    return result.driveId;
  }
}
