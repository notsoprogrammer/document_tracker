import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import '../config/supabase_config.dart';
import 'upload_queue_manager.dart';

/// Thrown when the server rejects a payload outright (too large, malformed).
/// These must never be retried — the same bytes will fail every time.
class PermanentUploadException implements Exception {
  final String message;
  PermanentUploadException(this.message);
  @override
  String toString() => 'PermanentUploadException: $message';
}

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

enum DriveFolder { incoming, outgoing, flagCeremony, attendance, movs, certificates, locationalZoning, cdc, spDocuments, reclassification, resolutions }

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
  static const String _resolutionsFolderId = '1Jotcls0aRcykZrWCfiobH3vwd3ZSzZC6';

  // Supabase function URL for secure uploads
  static const String _supabaseFunctionUrl = SupabaseConfig.uploadToDriveFunctionUrl;

 static String getFolderId(String category) {
    // Determine folder based on the selected type (category)
    if ([
      'Sectoral Plans',
      'Ecological Profile',
      'Research/Studies/Trainings',
      'CSOs',
      'AIP',
      'Barangay – AIP',
      'Barangay – GAD',
    ].contains(category)) {
      return _attendanceFolderId; // Core Function -> attendance
    } else if ([
      'CDC – Resolution',
      'CDC – Minutes',
      'CDC – Attendance',
      'Execom Resolution',
      'Supplemental AIP',
      'CDC Invitation',
    ].contains(category)) {
      return _cdcFolderId; // CDC Documents
    } else if ([
      'SP Resolution',
      'SP Ordinance',
    ].contains(category)) {
      return _spDocumentsFolderId; // SP Documents
    } else if ([
      'Locational Clearance',
      'Zoning Clearance',
      'Zoning Certification',
    ].contains(category)) {
      return _locationalZoningFolderId; // Locational & Zoning
    } else if ([
      'CLUP Zoning Reclassification',
    ].contains(category)) {
      return _reclassificationFolderId; // Reclassification
    } else if ([
      'PR/PPMP',
      'Liquidation/ Reimbursement',
      'PFMAR/PFMIP',
    ].contains(category)) {
      return _movsFolderId; // Strategic Function -> movs
    } else if ([
      'DTR',
      'Monthly Accomplishment Report',
      'Quarterly Accomplishment Report',
      'Annual Accomplishment Report',
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
      'Annual Budget',
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

      return localFile.path;
    } catch (e) {
      return null;
    }
  }

  /// Upload image to Google Drive (original functionality)
  static Future<String?> uploadImageToDrive(
    File imageFile,
    String fileNameOrUniqueId, {
    DriveFolder folder = DriveFolder.incoming,
  }) async {
    // Build file name if you currently do so elsewhere, keep it; otherwise:
    final fileName = fileNameOrUniqueId.endsWith('.jpg')
        ? fileNameOrUniqueId
        : 'doc_${fileNameOrUniqueId}.jpg';

    // Read file bytes and upload via Supabase. Errors propagate so the queue
    // can tell a retryable failure from a permanent one.
    final bytes = await imageFile.readAsBytes();
    return await _uploadFileFromBytesViaSupabase(bytes, fileName, folder: folder);
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
    // Read file bytes and upload via Supabase. Errors propagate so the queue
    // can tell a retryable failure from a permanent one.
    final bytes = await file.readAsBytes();
    return await _uploadFileFromBytesViaSupabase(bytes, fileName, folder: folder);
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
          }
        }
      }
    } catch (e) {
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
      return 0;
    }
  }

  /// Hard ceiling for any single attachment. Matches the 50MB limit the add/edit
  /// screens enforce at pick time, so the UI never accepts a file the transport
  /// can't carry.
  static const int maxUploadBytes = 50 * 1024 * 1024;

  /// Files at or below this go inline through the edge function as base64.
  /// Anything larger uses a Drive resumable session so the bytes bypass
  /// Supabase entirely.
  static const int inlineUploadThreshold = 4 * 1024 * 1024;

  /// Resumable chunk size. Google requires every chunk except the last to be a
  /// multiple of 256KB; 5MB is 20 such blocks and keeps retries cheap on a
  /// flaky office connection.
  static const int _resumableChunkSize = 5 * 1024 * 1024;

  /// Downscale/re-encode an image so it comfortably fits the edge function's
  /// request budget. Safety net for images that bypassed capture-time
  /// compression (older queued files, file-picker imports, web camera bytes).
  /// Returns the original bytes unchanged if it isn't a compressible image or
  /// if anything goes wrong — compression must never block an upload.
  static List<int> compressImageBytes(List<int> bytes, String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    if (!['jpg', 'jpeg', 'png'].contains(extension)) return bytes;
    if (bytes.length <= 300 * 1024) return bytes;

    try {
      final decoded = img.decodeImage(Uint8List.fromList(bytes));
      if (decoded == null) return bytes;

      const maxDim = 1920;
      final img.Image resized;
      if (decoded.width >= decoded.height && decoded.width > maxDim) {
        resized = img.copyResize(decoded, width: maxDim);
      } else if (decoded.height > decoded.width && decoded.height > maxDim) {
        resized = img.copyResize(decoded, height: maxDim);
      } else {
        resized = decoded;
      }

      final out = img.encodeJpg(resized, quality: 80);
      // Only take the result if it actually helped.
      if (out.length < bytes.length) {
        UploadQueueManager.log(
            'compress: $fileName ${(bytes.length / 1024).round()}KB -> ${(out.length / 1024).round()}KB');
        return out;
      }
      return bytes;
    } catch (e) {
      UploadQueueManager.log('compress: skipped for $fileName ($e)');
      return bytes;
    }
  }

  /// Ask the edge function for a Drive resumable upload session URL.
  static Future<String> _createResumableSession(
      String fileName, String folderId, String mimeType) async {
    final response = await http.post(
      Uri.parse(_supabaseFunctionUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${SupabaseConfig.supabaseAnonKey}',
      },
      body: jsonEncode({
        'action': 'create_upload_session',
        'fileName': fileName,
        'folderId': folderId,
        'mimeType': mimeType,
      }),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode >= 400 && response.statusCode < 500) {
      throw PermanentUploadException(
          'Could not start upload (HTTP ${response.statusCode}): ${response.body}');
    }
    if (response.statusCode != 200) {
      throw Exception('Could not start upload (HTTP ${response.statusCode})');
    }

    final result = jsonDecode(response.body);
    final sessionUrl = result['sessionUrl'] as String?;
    if (result['success'] != true || sessionUrl == null) {
      throw Exception('Upload session rejected: ${result['error'] ?? 'unknown'}');
    }
    return sessionUrl;
  }

  /// Grant public read on a file uploaded via a resumable session.
  static Future<void> _finalizeResumableUpload(String fileId) async {
    final response = await http.post(
      Uri.parse(_supabaseFunctionUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${SupabaseConfig.supabaseAnonKey}',
      },
      body: jsonEncode({'action': 'finalize', 'fileId': fileId}),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      // The file IS in Drive at this point — only the public permission
      // failed. Log it rather than failing the upload and causing a duplicate.
      UploadQueueManager.log(
          'finalize warning for $fileId: HTTP ${response.statusCode} ${response.body}');
    }
  }

  /// Upload large files straight to Google Drive in chunks using a resumable
  /// session. The bytes never touch Supabase, so there's no base64 inflation
  /// and no edge request-body ceiling — and a dropped connection only costs
  /// the current chunk, not the whole file.
  static Future<String?> _uploadViaResumableSession(
    List<int> bytes,
    String fileName,
    String folderId,
    String mimeType,
  ) async {
    final total = bytes.length;
    final sessionUrl = await _createResumableSession(fileName, folderId, mimeType);

    UploadQueueManager.log(
        'resumable start $fileName ${(total / 1024 / 1024).toStringAsFixed(1)}MB '
        'in ${(total / _resumableChunkSize).ceil()} chunk(s)');

    final client = http.Client();
    try {
      int offset = 0;
      while (offset < total) {
        final end = (offset + _resumableChunkSize) > total
            ? total
            : offset + _resumableChunkSize;
        final chunk = bytes.sublist(offset, end);

        final request = http.Request('PUT', Uri.parse(sessionUrl))
          ..bodyBytes = Uint8List.fromList(chunk)
          ..headers['Content-Type'] = mimeType
          ..headers['Content-Range'] = 'bytes $offset-${end - 1}/$total';

        final streamed = await client
            .send(request)
            .timeout(const Duration(seconds: 120));
        final response = await http.Response.fromStream(streamed);

        // 308 Resume Incomplete — Google acknowledges the chunk and tells us,
        // via the Range header, exactly how much it actually stored.
        if (response.statusCode == 308) {
          final range = response.headers['range'];
          if (range != null && range.contains('-')) {
            offset = int.parse(range.split('-').last) + 1;
          } else {
            offset = end;
          }
          continue;
        }

        if (response.statusCode == 200 || response.statusCode == 201) {
          final result = jsonDecode(response.body);
          final fileId = result['id'] as String?;
          if (fileId == null) {
            throw Exception('Drive returned no file id');
          }
          await _finalizeResumableUpload(fileId);
          UploadQueueManager.log('resumable done $fileName -> $fileId');
          return fileId;
        }

        if (response.statusCode >= 400 && response.statusCode < 500) {
          throw PermanentUploadException(
              'Drive rejected upload (HTTP ${response.statusCode}): ${response.body}');
        }

        throw Exception('Chunk upload failed (HTTP ${response.statusCode})');
      }

      throw Exception('Upload ended without Drive confirming the file');
    } finally {
      client.close();
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
                                          : folder == DriveFolder.resolutions
                                              ? _resolutionsFolderId
                                              : _incomingFolderId;

      // Safety net: shrink anything that slipped past capture-time compression
      final uploadBytes = compressImageBytes(bytes, fileName);

      // Fail fast rather than burning three retries on bytes the server
      // will always reject.
      if (uploadBytes.length > maxUploadBytes) {
        throw PermanentUploadException(
            'File too large: ${(uploadBytes.length / 1024 / 1024).toStringAsFixed(1)}MB '
            '(max ${(maxUploadBytes / 1024 / 1024).round()}MB)');
      }

      // Anything substantial goes straight to Drive in chunks instead of being
      // base64'd through the edge function.
      if (uploadBytes.length > inlineUploadThreshold) {
        return await _uploadViaResumableSession(
          uploadBytes,
          fileName,
          targetFolderId,
          _getMimeType(fileName),
        );
      }

      // Convert bytes to base64
      final base64Data = base64Encode(uploadBytes);

      // Prepare request payload
      final payload = {
        'fileName': fileName,
        'fileData': base64Data,
        'folderId': targetFolderId,
        'mimeType': _getMimeType(fileName),
      };

      // The timeout has to cover BOTH legs: phone -> Supabase, then
      // Supabase -> Google Drive. Scale it with payload size (assume a
      // pessimistic ~50KB/s floor) instead of using one fixed value.
      final timeoutSecs =
          (30 + (base64Data.length / 1024 / 50).ceil()).clamp(45, 180);

      UploadQueueManager.log(
          'POST $fileName ${(uploadBytes.length / 1024).round()}KB timeout:${timeoutSecs}s');

      final response = await http.post(
        Uri.parse(_supabaseFunctionUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${SupabaseConfig.supabaseAnonKey}',
        },
        body: jsonEncode(payload),
      ).timeout(Duration(seconds: timeoutSecs));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return result['fileId'];
        }
        throw Exception('Upload rejected: ${result['error'] ?? 'unknown error'}');
      }

      // 4xx means this payload will never be accepted — don't retry it.
      if (response.statusCode >= 400 && response.statusCode < 500) {
        throw PermanentUploadException(
            'Server rejected upload (HTTP ${response.statusCode}): ${response.body}');
      }

      // 5xx / anything else is transient — let the caller retry.
      throw Exception('Upload failed (HTTP ${response.statusCode})');
    } on PermanentUploadException {
      rethrow;
    } catch (e) {
      UploadQueueManager.log('upload error for $fileName: $e');
      rethrow;
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
          return true;
        } else {
          return false;
        }
      } else {
        return false;
      }
    } catch (e) {
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
