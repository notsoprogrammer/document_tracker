import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image/image.dart' as img;

/// Production-grade document scanner backed by Google ML Kit Document Scanner.
///
/// Platform support:
///   Android – native ML Kit activity (auto edge-detection, perspective
///             correction, and built-in enhancement via Google Play Services).
///   iOS / Web – returns null; caller should fall back to [DocumentScannerService].
///
/// Post-processing (applied after ML Kit's own enhancement):
///   1. Unsharp mask  – crisp text without B&W conversion (preserves colour).
///   2. Contrast boost – mild midpoint stretch for readability.
///   3. Background normalisation – whitens paper while keeping logos / colours.
class MlKitScannerService {
  /// True when the ML Kit Document Scanner is available on this device.
  static bool get isAvailable => !kIsWeb && Platform.isAndroid;

  // ─── Public API ────────────────────────────────────────────────────────────

  /// Launches the ML Kit Document Scanner UI.
  ///
  /// Returns a list of processed JPEG [Uint8List]s — one per scanned page.
  /// Returns an **empty list** when the user cancels.
  /// Returns **null** when ML Kit is unavailable or an error occurs (caller
  /// should fall back to the custom CV pipeline).
  static Future<List<Uint8List>?> scanDocument({int maxPages = 10}) async {
    if (!isAvailable) return null;

    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        // JPEG gives the best quality/size tradeoff for document images.
        documentFormat: DocumentFormat.jpeg,
        // ScannerMode.full = automatic edge detection + perspective correction
        // + built-in image enhancement (colour mode, not B&W).
        mode: ScannerMode.full,
        pageLimit: maxPages,
        // Camera-only: no gallery import so the user can't bypass the scanner.
        isGalleryImport: false,
      ),
    );

    try {
      final DocumentScanningResult result = await scanner.scanDocument();

      if (result.images.isEmpty) return []; // user cancelled

      // Post-process every page concurrently via compute() isolates.
      final futures = result.images.map((path) async {
        final rawBytes = await File(path).readAsBytes();
        return compute(_postProcess, rawBytes);
      });

      return await Future.wait(futures);
    } on Exception catch (e) {
      debugPrint('[MlKitScannerService] scanDocument error: $e');
      return null; // caller falls back to custom CV pipeline
    } finally {
      scanner.close();
    }
  }

  // ─── Post-processing (top-level for compute()) ─────────────────────────────

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

  // ─── Image enhancement helpers ─────────────────────────────────────────────

  /// Unsharp mask: output = original + amount × (original − blurred).
  /// Sharpens fine text details without introducing haloing on large regions.
  static void _unsharpMask(img.Image src, {required double amount, required int radius}) {
    // gaussianBlur returns a new image; src is modified in-place below.
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

  /// Mild S-curve contrast stretch around the midpoint (128).
  /// factor > 1 increases contrast; keep close to 1.0 to avoid clipping.
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

  /// Scales all channels so the 95th-percentile pixel (the paper background)
  /// maps to pure white. Pixels already near white are left untouched.
  /// Colours (logos, stamps, ink) are preserved because every channel scales
  /// by the same per-pixel factor derived from the *background* sample.
  static void _normalizeBackground(img.Image image) {
    // Sample every 16th pixel for speed.
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

    // Only normalise when the background is noticeably off-white.
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
