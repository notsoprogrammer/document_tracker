import 'dart:io';
import 'dart:math' as math;
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

  static void _removeIllumination(img.Image image) {
  // Large blur to estimate lighting field
  final blurred = img.gaussianBlur(image, radius: 25);

  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final p = image.getPixel(x, y);
      final b = blurred.getPixel(x, y);

      // Avoid divide by zero
      final r = (p.r * 255 / (b.r + 1)).clamp(0, 255).round();
      final g = (p.g * 255 / (b.g + 1)).clamp(0, 255).round();
      final bb = (p.b * 255 / (b.b + 1)).clamp(0, 255).round();

      image.setPixelRgb(x, y, r, g, bb);
    }
  }
}

  // ─── Post-processing pipeline (top-level for compute()) ──────────────────

  /// Full CamScanner "Color Scan" quality pipeline.
  /// Top-level static so it can be passed to [compute()].
  static Uint8List _postProcess(Uint8List jpegBytes) {
    img.Image? image = img.decodeImage(jpegBytes);
    if (image == null) return jpegBytes;

    final w = image.width;
    final h = image.height;
    final n = w * h;

    // Steps 1–3: LAB CLAHE ─────────────────────────────────────────────────
    final labL = Float32List(n);
    final labA = Float32List(n);
    final labB = Float32List(n);

    _rgbToLab(image, labL, labA, labB);
    _claheOnL(labL, w, h, clipLimit: 3.8, tileSize: 8);
    _labToRgb(image, labL, labA, labB);

    _adaptiveContrastStretch(image);
    _removeIllumination(image);

    // Step 4: Background normalisation ────────────────────────────────────
    _normalizeBackground(image);

    // Step 6: Unsharp mask ─────────────────────────────────────────────────
    _unsharpMask(image, radius: 2, amount: 1.15);
    _unsharpMask(image, radius: 1, amount: 0.60);

    // Step 7: Light bilateral filter ──────────────────────────────────────
    _bilateralFilter(image, radius: 2, sigmaSpace: 2.0, sigmaColor: 15.0);

    return Uint8List.fromList(img.encodeJpg(image, quality: 93));
  }

  // ─── LAB colour-space helpers ─────────────────────────────────────────────

  /// sRGB → CIE L*a*b* (D65 illuminant). Stores results in [outL/A/B].
  static void _rgbToLab(
    img.Image image,
    Float32List outL,
    Float32List outA,
    Float32List outB,
  ) {
    // D65 reference white
    const xn = 0.95047, yn = 1.00000, zn = 1.08883;
    final w = image.width;
    for (var py = 0; py < image.height; py++) {
      for (var px = 0; px < w; px++) {
        final p = image.getPixel(px, py);
        final rl = _linearize(p.r.toDouble());
        final gl = _linearize(p.g.toDouble());
        final bl = _linearize(p.b.toDouble());

        // sRGB linear → XYZ (D65)
        final X = (0.4124564 * rl + 0.3575761 * gl + 0.1804375 * bl) / xn;
        final Y = (0.2126729 * rl + 0.7151522 * gl + 0.0721750 * bl) / yn;
        final Z = (0.0193339 * rl + 0.1191920 * gl + 0.9503041 * bl) / zn;

        final fx = _labF(X);
        final fy = _labF(Y);
        final fz = _labF(Z);

        final i = py * w + px;
        outL[i] = 116.0 * fy - 16.0;
        outA[i] = 500.0 * (fx - fy);
        outB[i] = 200.0 * (fy - fz);
      }
    }
  }

  /// CIE L*a*b* → sRGB. Writes directly into [image].
  static void _labToRgb(
    img.Image image,
    Float32List labL,
    Float32List labA,
    Float32List labB,
  ) {
    const xn = 0.95047, yn = 1.00000, zn = 1.08883;
    final w = image.width;
    for (var py = 0; py < image.height; py++) {
      for (var px = 0; px < w; px++) {
        final i = py * w + px;
        final fy = (labL[i] + 16.0) / 116.0;
        final fx = labA[i] / 500.0 + fy;
        final fz = fy - labB[i] / 200.0;

        final X = xn * _labFInv(fx);
        final Y = yn * _labFInv(fy);
        final Z = zn * _labFInv(fz);

        // XYZ → linear sRGB (D65)
        final rl = (3.2404542 * X - 1.5371385 * Y - 0.4985314 * Z).clamp(0.0, 1.0);
        final gl = (-0.9692660 * X + 1.8760108 * Y + 0.0415560 * Z).clamp(0.0, 1.0);
        final bl = (0.0556434 * X - 0.2040259 * Y + 1.0572252 * Z).clamp(0.0, 1.0);

        image.setPixelRgb(
          px, py,
          (_delinearize(rl) * 255.0).round().clamp(0, 255),
          (_delinearize(gl) * 255.0).round().clamp(0, 255),
          (_delinearize(bl) * 255.0).round().clamp(0, 255),
        );
      }
    }
  }

  /// sRGB [0–255] → linear [0–1] (IEC 61966-2-1).
  static double _linearize(double c) {
    c /= 255.0;
    return c <= 0.04045
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  /// Linear [0–1] → sRGB [0–1] gamma correction.
  static double _delinearize(double c) {
    return c <= 0.0031308
        ? 12.92 * c
        : 1.055 * math.pow(c, 1.0 / 2.4).toDouble() - 0.055;
  }

  /// CIE f(t) function used in XYZ → L*a*b* conversion.
  static double _labF(double t) {
    const delta = 6.0 / 29.0;
    return t > delta * delta * delta
        ? math.pow(t, 1.0 / 3.0).toDouble()
        : t / (3.0 * delta * delta) + 4.0 / 29.0;
  }

  /// Inverse of [_labF].
  static double _labFInv(double t) {
    const delta = 6.0 / 29.0;
    return t > delta ? t * t * t : 3.0 * delta * delta * (t - 4.0 / 29.0);
  }

  // ─── CLAHE on L channel ──────────────────────────────────────────────────

  /// Contrast Limited Adaptive Histogram Equalisation applied **only** to the
  /// L* channel (luminance).  Leaves a* and b* (colour) untouched.
  ///
  /// [labL]      – L* values in [0, 100], modified in-place.
  /// [clipLimit] – histogram clip ratio (3.5–4.0 recommended).
  /// [tileSize]  – pixels per tile edge (8 → 8×8 grid).
  static void _claheOnL(
    Float32List labL,
    int w,
    int h, {
    required double clipLimit,
    required int tileSize,
  }) {
    final n = w * h;

    // Normalise L* [0,100] → uint8 [0,255] for histogram processing.
    final lNorm = Uint8List(n);
    for (var i = 0; i < n; i++) {
      lNorm[i] = (labL[i] * 255.0 / 100.0).round().clamp(0, 255);
    }

    final tilesX = (w + tileSize - 1) ~/ tileSize;
    final tilesY = (h + tileSize - 1) ~/ tileSize;
    final numTiles = tilesX * tilesY;

    // Build a 256-entry equalisation LUT for every tile.
    final tileMaps = List.generate(numTiles, (_) => Uint8List(256));

    for (var ty = 0; ty < tilesY; ty++) {
      for (var tx = 0; tx < tilesX; tx++) {
        final x0 = tx * tileSize;
        final y0 = ty * tileSize;
        final x1 = (x0 + tileSize).clamp(0, w);
        final y1 = (y0 + tileSize).clamp(0, h);

        // Histogram of tile pixels.
        final hist = List.filled(256, 0);
        var tileCount = 0;
        for (var py = y0; py < y1; py++) {
          for (var px = x0; px < x1; px++) {
            hist[lNorm[py * w + px]]++;
            tileCount++;
          }
        }

        // Clip histogram and redistribute excess uniformly.
        final clipCount = math.max(1, (clipLimit * tileCount / 256).round());
        var excess = 0;
        for (var i = 0; i < 256; i++) {
          if (hist[i] > clipCount) {
            excess += hist[i] - clipCount;
            hist[i] = clipCount;
          }
        }
        final redistPerBin = excess ~/ 256;
        var remainder = excess - redistPerBin * 256;
        for (var i = 0; i < 256; i++) {
          hist[i] += redistPerBin;
          if (remainder > 0) {
            hist[i]++;
            remainder--;
          }
        }

        // Build cumulative distribution function.
        final cdf = List.filled(256, 0);
        var cumsum = 0;
        for (var i = 0; i < 256; i++) {
          cumsum += hist[i];
          cdf[i] = cumsum;
        }
        // cdfMin = first non-zero CDF value = hist[0] (always > 0 after redistribution).
        final cdfMin = cdf[0];
        final denom = tileCount - cdfMin;
        if (denom <= 0) continue;

        // Normalised LUT: maps input [0,255] → output [0,255].
        final map = tileMaps[ty * tilesX + tx];
        for (var i = 0; i < 256; i++) {
          map[i] = (((cdf[i] - cdfMin) * 255.0) / denom).round().clamp(0, 255);
        }
      }
    }

    // Apply bilinear interpolation between four surrounding tile centres.
    for (var py = 0; py < h; py++) {
      for (var px = 0; px < w; px++) {
        // Position in tile-index space (tile centre offset by 0.5).
        final tfx = px.toDouble() / tileSize - 0.5;
        final tfy = py.toDouble() / tileSize - 0.5;

        final tx0 = tfx.floor().clamp(0, tilesX - 1);
        final tx1 = (tx0 + 1).clamp(0, tilesX - 1);
        final ty0 = tfy.floor().clamp(0, tilesY - 1);
        final ty1 = (ty0 + 1).clamp(0, tilesY - 1);

        final wx = (tfx - tx0).clamp(0.0, 1.0);
        final wy = (tfy - ty0).clamp(0.0, 1.0);

        final val = lNorm[py * w + px];
        final v00 = tileMaps[ty0 * tilesX + tx0][val].toDouble();
        final v10 = tileMaps[ty0 * tilesX + tx1][val].toDouble();
        final v01 = tileMaps[ty1 * tilesX + tx0][val].toDouble();
        final v11 = tileMaps[ty1 * tilesX + tx1][val].toDouble();

        // Bilinear blend.
        final mapped = v00 * (1 - wx) * (1 - wy) +
            v10 * wx * (1 - wy) +
            v01 * (1 - wx) * wy +
            v11 * wx * wy;

        // Convert back to L* [0,100].
        labL[py * w + px] = mapped * 100.0 / 255.0;
      }
    }
  }

  // ─── Background normalisation ─────────────────────────────────────────────

  /// Pushes high-brightness pixels (R,G,B > 200) toward pure white (#FDFDFD–
  /// #FFFFFF), eliminating shadow gradients from uneven illumination.
  /// Pixels below the threshold are unchanged so text/colours are preserved.
  static void _normalizeBackground(img.Image image) {
    for (var py = 0; py < image.height; py++) {
      for (var px = 0; px < image.width; px++) {
        final p = image.getPixel(px, py);
        final r = p.r.toInt();
        final g = p.g.toInt();
        final b = p.b.toInt();

        if (r > 200 && g > 200 && b > 200) {
          // Blend strength ramps from 0 at brightness=200 to 0.85 at brightness=255.
          final brightness = (r + g + b) / 3.0;
          final t = ((brightness - 200.0) / 55.0).clamp(0.0, 1.0);
          final strength = t * 0.85;
          image.setPixelRgb(
            px, py,
            (r + (255 - r) * strength).round().clamp(0, 255),
            (g + (255 - g) * strength).round().clamp(0, 255),
            (b + (255 - b) * strength).round().clamp(0, 255),
          );
        }
      }
    }
  }

  // ─── Adaptive contrast stretch ────────────────────────────────────────────

  /// Stretches the luminance histogram so the 1st-percentile dark value maps
  /// to black and the image retains full dynamic range.  Applied uniformly
  /// across all channels to avoid hue shifts.
  static void _adaptiveContrastStretch(img.Image image) {
    final hist = List.filled(256, 0);
    final total = image.width * image.height;

    for (var py = 0; py < image.height; py++) {
      for (var px = 0; px < image.width; px++) {
        final p = image.getPixel(px, py);
        final lum = (p.r * 0.299 + p.g * 0.587 + p.b * 0.114)
            .round()
            .clamp(0, 255);
        hist[lum]++;
      }
    }

    // Find the 1st-percentile dark endpoint.
    var cumsum = 0;
    var darkEnd = 0;
    for (var i = 0; i < 256; i++) {
      cumsum += hist[i];
      if (cumsum < total * 0.01) darkEnd = i;
    }

    // Skip if already well-stretched or document is intrinsically dark.
    if (darkEnd < 5) return;

    final scale = 255.0 / (255.0 - darkEnd);
    for (var py = 0; py < image.height; py++) {
      for (var px = 0; px < image.width; px++) {
        final p = image.getPixel(px, py);
        image.setPixelRgb(
          px, py,
          ((p.r.toInt() - darkEnd) * scale).clamp(0.0, 255.0).round(),
          ((p.g.toInt() - darkEnd) * scale).clamp(0.0, 255.0).round(),
          ((p.b.toInt() - darkEnd) * scale).clamp(0.0, 255.0).round(),
        );
      }
    }
  }

  // ─── Unsharp mask ─────────────────────────────────────────────────────────

  /// Unsharp mask: output = original + amount × (original − blurred).
  /// [radius] 1 → 3×3-equivalent Gaussian; [amount] 0.6–0.8 for text.
  static void _unsharpMask(
    img.Image src, {
    required int radius,
    required double amount,
  }) {
    final blurred = img.gaussianBlur(src, radius: radius);
    for (var py = 0; py < src.height; py++) {
      for (var px = 0; px < src.width; px++) {
        final p = src.getPixel(px, py);
        final bx = blurred.getPixel(px, py);
        src.setPixelRgb(
          px, py,
          (p.r + amount * (p.r - bx.r)).clamp(0.0, 255.0).round(),
          (p.g + amount * (p.g - bx.g)).clamp(0.0, 255.0).round(),
          (p.b + amount * (p.b - bx.b)).clamp(0.0, 255.0).round(),
        );
      }
    }
  }

  // ─── Bilateral filter ─────────────────────────────────────────────────────

  /// Edge-preserving smoothing that removes paper grain/texture while keeping
  /// text edges and colour boundaries sharp.
  ///
  /// [radius]     – kernel half-size (2 → 5×5 kernel).
  /// [sigmaSpace] – spatial falloff (smaller = more local).
  /// [sigmaColor] – colour-range sensitivity; low values preserve edges.
  static void _bilateralFilter(
    img.Image image, {
    required int radius,
    required double sigmaSpace,
    required double sigmaColor,
  }) {
    final w = image.width;
    final h = image.height;
    final kSize = 2 * radius + 1;

    // Snapshot original pixels to avoid read-after-write artefacts.
    final orig = Uint8List(w * h * 3);
    for (var py = 0; py < h; py++) {
      for (var px = 0; px < w; px++) {
        final p = image.getPixel(px, py);
        final idx = (py * w + px) * 3;
        orig[idx] = p.r.toInt();
        orig[idx + 1] = p.g.toInt();
        orig[idx + 2] = p.b.toInt();
      }
    }

    // Precompute spatial Gaussian weights (constant per kernel position).
    final spatialW = Float64List(kSize * kSize);
    final inv2Ss2 = 1.0 / (2.0 * sigmaSpace * sigmaSpace);
    for (var dy = -radius; dy <= radius; dy++) {
      for (var dx = -radius; dx <= radius; dx++) {
        spatialW[(dy + radius) * kSize + (dx + radius)] =
            math.exp(-(dx * dx + dy * dy) * inv2Ss2);
      }
    }

    final inv2Sc2 = 1.0 / (2.0 * sigmaColor * sigmaColor);

    for (var py = 0; py < h; py++) {
      for (var px = 0; px < w; px++) {
        final ci = (py * w + px) * 3;
        final cr = orig[ci], cg = orig[ci + 1], cb = orig[ci + 2];

        double sumR = 0, sumG = 0, sumB = 0, sumWt = 0;

        for (var dy = -radius; dy <= radius; dy++) {
          final ny = (py + dy).clamp(0, h - 1);
          for (var dx = -radius; dx <= radius; dx++) {
            final nx = (px + dx).clamp(0, w - 1);
            final ni = (ny * w + nx) * 3;

            final nr = orig[ni], ng = orig[ni + 1], nb = orig[ni + 2];
            final dr = cr - nr, dg = cg - ng, dbv = cb - nb;
            final colorDist2 = (dr * dr + dg * dg + dbv * dbv).toDouble();

            final sw = spatialW[(dy + radius) * kSize + (dx + radius)];
            final wt = sw * math.exp(-colorDist2 * inv2Sc2);

            sumR += nr * wt;
            sumG += ng * wt;
            sumB += nb * wt;
            sumWt += wt;
          }
        }

        if (sumWt > 0) {
          image.setPixelRgb(
            px, py,
            (sumR / sumWt).round().clamp(0, 255),
            (sumG / sumWt).round().clamp(0, 255),
            (sumB / sumWt).round().clamp(0, 255),
          );
        }
      }
    }
  }
}
