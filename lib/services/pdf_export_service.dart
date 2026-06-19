import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../config/supabase_config.dart';
import '../services/google_drive_service.dart';
import '../utils/pdf_download_helper.dart';

class PdfExportService {
  static Future<void> exportImagesToPdf({
    required List<String> imageUrls,
    required String fileName,
  }) async {
    final doc = pw.Document();
    int pageCount = 0;

    for (final url in imageUrls) {
      try {
        final proxyUrl = _proxyUrl(url);
        final response = await http.get(
          Uri.parse(proxyUrl),
          headers: {'Authorization': 'Bearer ${SupabaseConfig.supabaseAnonKey}'},
        ).timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) {
          final image = pw.MemoryImage(response.bodyBytes);
          final isLandscape = image.width != null &&
              image.height != null &&
              image.width! > image.height!;
          final pageFormat =
              isLandscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
          doc.addPage(pw.Page(
            pageFormat: pageFormat,
            margin: const pw.EdgeInsets.all(16),
            build: (ctx) => pw.Center(
              child: pw.Image(image, fit: pw.BoxFit.contain),
            ),
          ));
          pageCount++;
        }
      } catch (_) {
        // Skip images that fail — continue with remaining
      }
    }

    if (pageCount == 0) {
      throw Exception('No images could be loaded for PDF export');
    }

    final pdfBytes = Uint8List.fromList(await doc.save());
    // Sanitize filename — remove characters that are invalid in file names
    final safeFileName =
        '${fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')}.pdf';

    if (kIsWeb) {
      await triggerPdfDownload(pdfBytes, safeFileName);
    } else {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$safeFileName');
      await file.writeAsBytes(pdfBytes);
      await OpenFile.open(file.path);
    }
  }

  static String _proxyUrl(String imageUrl) {
    if (imageUrl.contains('drive.google.com/uc?id=')) {
      final uri = Uri.parse(imageUrl);
      final fileId = uri.queryParameters['id'];
      if (fileId != null) return GoogleDriveService.generateProxyUrl(fileId);
    }
    return GoogleDriveService.generateProxyUrl(imageUrl);
  }
}
