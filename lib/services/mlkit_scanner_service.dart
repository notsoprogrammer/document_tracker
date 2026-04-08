import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image/image.dart' as img;

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
/// Post-processing applied to JPEG output (colour-preserving):
///   1. Unsharp mask  – sharpens text without binarising.
///   2. Contrast boost – mild midpoint stretch.
///   3. Background normalisation – whitens paper, preserves logos / colours.
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
        // Post-process every page concurrently in isolates.
        final futures = result.images.map((path) async {
          final raw = await File(path).readAsBytes();
          return compute(_postProcess, raw);
        });
        return ScannerOutput(images: await Future.wait(futures));
      }
    } on Exception catch (e) {
      debugPrint('[MlKitScannerService] scanDocument error: $e');
      return null; // caller falls back to custom CV pipeline
    } finally {
      scanner.close();
    }
  }

  // ─── Post-processing (top-level for compute()) ───────────────────────────

  /// Applies unsharp mask → contrast boost → background normalisation.
  /// Colour-preserving: does NOT binarise the image.
  /// Encodes the result as a 93 % quality JPEG.
  static Uint8List _postProcess(Uint8List jpegBytes) {
    img.Image? image = img.decodeImage(jpegBytes);
    if (image == null) return jpegBytes;

    _unsharpMask(image, amount: 0.65, radius: 1);
    _contrastBoost(image, factor: 1.12);
    _normalizeBackground(image);

    return Uint8List.fromList(img.encodeJpg(image, quality: 93));
  }

  // ─── Image enhancement helpers ────────────────────────────────────────────

  /// Unsharp mask: output = original + amount × (original − blurred).
  static void _unsharpMask(
    img.Image src, {
    required double amount,
    required int radius,
  }) {
    final blurred = img.gaussianBlur(src, radius: radius);
    for (var y = 0; y < src.height; y++) {
      for (var x = 0; x < src.width; x++) {
        final p = src.getPixel(x, y);
        final b = blurred.getPixel(x, y);
        src.setPixelRgb(
          x,
          y,
          (p.r + amount * (p.r - b.r)).clamp(0, 255).round(),
          (p.g + amount * (p.g - b.g)).clamp(0, 255).round(),
          (p.b + amount * (p.b - b.b)).clamp(0, 255).round(),
        );
      }
    }
  }

  /// Mild contrast stretch around the midpoint (128).
  static void _contrastBoost(img.Image image, {required double factor}) {
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final p = image.getPixel(x, y);
        image.setPixelRgb(
          x,
          y,
          ((p.r - 128) * factor + 128).clamp(0, 255).round(),
          ((p.g - 128) * factor + 128).clamp(0, 255).round(),
          ((p.b - 128) * factor + 128).clamp(0, 255).round(),
        );
      }
    }
  }

  /// Scales all channels so the 95th-percentile pixel (paper background)
  /// maps to pure white, preserving relative colours.
  static void _normalizeBackground(img.Image image) {
    final samples = <int>[];
    for (var y = 0; y < image.height; y += 16) {
      for (var x = 0; x < image.width; x += 16) {
        final p = image.getPixel(x, y);
        samples.add(((p.r + p.g + p.b) / 3).round());
      }
    }
    if (samples.isEmpty) return;
    samples.sort();

    final bgLevel =
        samples[(samples.length * 0.95).round().clamp(0, samples.length - 1)];
    if (bgLevel < 200 || bgLevel >= 255) return;

    final scale = 255.0 / bgLevel;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final p = image.getPixel(x, y);
        image.setPixelRgb(
          x,
          y,
          (p.r * scale).clamp(0, 255).round(),
          (p.g * scale).clamp(0, 255).round(),
          (p.b * scale).clamp(0, 255).round(),
        );
      }
    }
  }
}
