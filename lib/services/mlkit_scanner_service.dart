import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

// ─── Public result types ───────────────────────────────────────────────────

/// Requested output format passed to [MlKitScannerService.scanDocument].
enum ScanOutputFormat { image, pdf }

/// Result returned by [MlKitScannerService.scanDocument].
///
/// - [images] → non-empty when [ScanOutputFormat.image] was requested.
/// - [pdf]    → non-null when [ScanOutputFormat.pdf] was requested.
/// - Both absent ([wasCancelled]) → user dismissed the scanner.
class ScannerOutput {
  final List<Uint8List> images;
  final Uint8List? pdf;

  const ScannerOutput({this.images = const [], this.pdf});

  bool get wasCancelled => images.isEmpty && pdf == null;
  bool get hasPdf => pdf != null;
  bool get hasImages => images.isNotEmpty;
}

// ─── Service ───────────────────────────────────────────────────────────────

/// Production-grade document scanner backed by Google ML Kit Document Scanner.
///
/// Platform support:
///   Android – native ML Kit activity (auto edge-detection, perspective
///             correction, and built-in enhancement via Google Play Services).
///   iOS / Web – [isAvailable] returns false; caller falls back to
///               [DocumentScannerService].
///
/// Post-processing pipeline (CamScanner "Color Scan" quality):
///   1. RGB → CIE L*a*b* colour space.
///   2. CLAHE on L channel only (clipLimit 3.8, 8×8 tiles) – adaptive local
///      contrast without colour shift.
///   3. L*a*b* → RGB.
///   4. Background normalisation – pixels with R,G,B > 200 are pushed toward
///      pure white (#FDFDFD–#FFFFFF); shadow gradients removed.
///   5. Adaptive contrast stretch – 1st/99th-percentile luminance range
///      expansion to deepen text without binarising.
///   6. Unsharp mask (radius 1, amount 0.70) – crisp edges, no halo artefacts.
///   7. Light bilateral filter (radius 2, σ_space 2, σ_color 20) – removes
///      paper grain while preserving text and coloured headers.
///   Does NOT threshold, desaturate, or convert to pure black-and-white.
class MlKitScannerService {
  /// True when ML Kit Document Scanner can be launched on this device.
  static bool get isAvailable => !kIsWeb && Platform.isAndroid;

  // ─── Public API ──────────────────────────────────────────────────────────

  /// Launches the ML Kit Document Scanner UI and returns a [ScannerOutput].
  ///
  /// [maxPages] caps the number of pages the user can scan in one session.
  /// [format] controls whether JPEG images or a single combined PDF is produced.
  ///
  /// Returns **null** when ML Kit is unavailable or an unexpected error occurs
  /// (the caller should fall back to the custom CV pipeline).
  static Future<ScannerOutput?> scanDocument({
    int maxPages = 10,
    ScanOutputFormat format = ScanOutputFormat.image,
  }) async {
    if (!isAvailable) return null;

    final mlkitFormat = format == ScanOutputFormat.pdf
        ? DocumentFormat.pdf
        : DocumentFormat.jpeg;

    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormat: mlkitFormat,
        // ScannerMode.full = automatic edge detection + perspective correction
        // + colour-mode enhancement (not B&W).
        mode: ScannerMode.full,
        pageLimit: maxPages,
        isGalleryImport: false,
      ),
    );

    try {
      final DocumentScanningResult result = await scanner.scanDocument();

      if (format == ScanOutputFormat.pdf) {
        if (result.pdf == null) return const ScannerOutput(); // cancelled
        final bytes = await File(result.pdf!.uri).readAsBytes();
        return ScannerOutput(pdf: bytes);
      } else {
        if (result.images.isEmpty) return const ScannerOutput(); // cancelled
        // ML Kit (ScannerMode.full) already produces enhanced JPEGs.
        // Just read the files — no decode/re-encode pass needed.
        final images = await Future.wait(
          result.images.map((path) => File(path).readAsBytes()),
        );
        return ScannerOutput(images: images);
      }
    } on Exception catch (e) {
      return null; // caller falls back to custom CV pipeline
    } finally {
      scanner.close();
    }
  }

}
