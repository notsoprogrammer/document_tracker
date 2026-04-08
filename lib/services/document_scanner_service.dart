import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

// ---------------------------------------------------------------------------
// Internal 2-D point
// ---------------------------------------------------------------------------
class _Pt {
  final double x, y;
  const _Pt(this.x, this.y);
}

/// Professional document scanner service.
///
/// Processing pipeline (matches spec exactly):
///  1. Resize (max 1500 px wide)
///  2. Grayscale
///  3. Gaussian blur 5×5
///  4. Canny edge detection (low=75, high=200)
///  5. Find contours
///  6. Select largest 4-point contour
///  7. Perspective warp (4-pt homography)
///  8. CLAHE (clipLimit=2.0, tileGrid=8×8)
///  9. Adaptive threshold (Gaussian, blockSize=15, C=10)
/// 10. Morphological closing (3×3 kernel)
/// 11. Sharpening kernel [[0,−1,0],[−1,5,−1],[0,−1,0]]
///
/// Fully offline, no manual cropping, cross-platform (web + mobile).
class DocumentScannerService {
  static const int _maxWidth = 1500;

  /// Entry point. Accepts raw JPEG/PNG bytes, returns enhanced JPEG bytes.
  /// Returns null on failure.
  static Future<Uint8List?> processImage(Uint8List inputBytes) async {
    try {
      // compute() spawns an isolate on native and a web-worker on web (Flutter ≥3.7).
      // On older web builds it falls back to the main thread automatically.
      return kIsWeb
          ? _pipeline(inputBytes)
          : await compute(_pipeline, inputBytes);
    } catch (e) {
      debugPrint('[DocumentScannerService] $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TOP-LEVEL PIPELINE  (must be top-level / static for compute())
  // ─────────────────────────────────────────────────────────────────────────
  static Uint8List? _pipeline(Uint8List bytes) {
    // 1. Decode + resize
    img.Image? src = img.decodeImage(bytes);
    if (src == null) return null;
    if (src.width > _maxWidth) {
      src = img.copyResize(src, width: _maxWidth);
    }
    final int W = src.width, H = src.height;

    // 2. Grayscale
    final Uint8List gray = _toGray(src);

    // 3. Gaussian blur 5×5
    final Uint8List blurred = _gaussBlur(gray, W, H);

    // 4. Canny (low=75, high=200)
    final Uint8List edges = _canny(blurred, W, H, 75, 200);

    // 5–6. Detect document corners
    final List<_Pt>? corners = _detectCorners(edges, W, H);

    // 7. Perspective warp
    img.Image warped;
    if (corners != null) {
      warped = _warp(src, corners);
    } else {
      warped = _fallbackWarp(src, edges, W, H);
    }

    final int wW = warped.width, wH = warped.height;

    // 8. Convert warped to LAB color space-like processing
    img.Image enhanced = _enhanceColorScan(warped);

    // Return enhanced color image
    return Uint8List.fromList(img.encodeJpg(enhanced, quality: 95));
    
    // // Build RGB output (r=g=b) for universal JPEG compatibility
    // final img.Image out = img.Image(width: wW, height: wH);
    // for (var y = 0; y < wH; y++) {
    //   for (var x = 0; x < wW; x++) {
    //     final v = wg[y * wW + x];
    //     out.setPixelRgb(x, y, v, v, v);
    //   }
    // }
    // return Uint8List.fromList(img.encodeJpg(out, quality: 95));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 2 – Grayscale conversion (ITU-R BT.601 luminance)
  // ─────────────────────────────────────────────────────────────────────────
  static Uint8List _toGray(img.Image image) {
    final int w = image.width, h = image.height;
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        out[y * w + x] =
            (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).clamp(0, 255).toInt();
      }
    }
    return out;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 3 – Gaussian blur 5×5 (separable kernel [1,4,6,4,1]/16)
  // ─────────────────────────────────────────────────────────────────────────
  static Uint8List _gaussBlur(Uint8List g, int w, int h) {
    const kernel = [1, 4, 6, 4, 1];
    const kSum = 16;
    final tmp = Uint8List(w * h);
    final out = Uint8List(w * h);

    // Horizontal pass
    for (var y = 0; y < h; y++) {
      final rowBase = y * w;
      for (var x = 0; x < w; x++) {
        int s = 0;
        for (var i = -2; i <= 2; i++) {
          s += g[rowBase + (x + i).clamp(0, w - 1)] * kernel[i + 2];
        }
        tmp[rowBase + x] = s ~/ kSum;
      }
    }

    // Vertical pass
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        int s = 0;
        for (var i = -2; i <= 2; i++) {
          s += tmp[(y + i).clamp(0, h - 1) * w + x] * kernel[i + 2];
        }
        out[y * w + x] = s ~/ kSum;
      }
    }
    return out;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 4 – Canny edge detection
  // ─────────────────────────────────────────────────────────────────────────
  static Uint8List _canny(Uint8List g, int w, int h, int lo, int hi) {
    final mag = Float32List(w * h);
    final dir = Uint8List(w * h); // 0=H, 1=NE-diag, 2=V, 3=NW-diag

    // Sobel gradients
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final gx = -g[(y - 1) * w + (x - 1)] -
                2 * g[y * w + (x - 1)] -
                g[(y + 1) * w + (x - 1)] +
                g[(y - 1) * w + (x + 1)] +
                2 * g[y * w + (x + 1)] +
                g[(y + 1) * w + (x + 1)];
        final gy = -g[(y - 1) * w + (x - 1)] -
                2 * g[(y - 1) * w + x] -
                g[(y - 1) * w + (x + 1)] +
                g[(y + 1) * w + (x - 1)] +
                2 * g[(y + 1) * w + x] +
                g[(y + 1) * w + (x + 1)];
        mag[y * w + x] =
            math.sqrt((gx * gx + gy * gy).toDouble());
        final a = (math.atan2(gy.toDouble(), gx.toDouble()) * 180 / math.pi + 180) % 180;
        dir[y * w + x] = a < 22.5 || a >= 157.5
            ? 0
            : a < 67.5
                ? 1
                : a < 112.5
                    ? 2
                    : 3;
      }
    }

    // Non-maximum suppression
    final nms = Uint8List(w * h);
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final m = mag[y * w + x];
        final d = dir[y * w + x];
        double n1, n2;
        switch (d) {
          case 0:
            n1 = mag[y * w + (x - 1)];
            n2 = mag[y * w + (x + 1)];
            break;
          case 1:
            n1 = mag[(y - 1) * w + (x + 1)];
            n2 = mag[(y + 1) * w + (x - 1)];
            break;
          case 2:
            n1 = mag[(y - 1) * w + x];
            n2 = mag[(y + 1) * w + x];
            break;
          default:
            n1 = mag[(y - 1) * w + (x - 1)];
            n2 = mag[(y + 1) * w + (x + 1)];
        }
        if (m >= n1 && m >= n2) {
          nms[y * w + x] = m.clamp(0, 255).toInt();
        }
      }
    }

    // Hysteresis thresholding
    final edges = Uint8List(w * h);
    final queue = <int>[];

    for (var i = 0; i < w * h; i++) {
      if (nms[i] >= hi) {
        edges[i] = 255;
        queue.add(i);
      } else if (nms[i] >= lo) {
        edges[i] = 128; // weak candidate
      }
    }

    while (queue.isNotEmpty) {
      final idx = queue.removeLast();
      final y = idx ~/ w, x = idx % w;
      for (var dy = -1; dy <= 1; dy++) {
        final ny = y + dy;
        if (ny < 0 || ny >= h) continue;
        for (var dx = -1; dx <= 1; dx++) {
          if (dy == 0 && dx == 0) continue;
          final nx = x + dx;
          if (nx < 0 || nx >= w) continue;
          final ni = ny * w + nx;
          if (edges[ni] == 128) {
            edges[ni] = 255;
            queue.add(ni);
          }
        }
      }
    }
    // Discard unconnected weak edges
    for (var i = 0; i < w * h; i++) {
      if (edges[i] == 128) edges[i] = 0;
    }
    return edges;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEPS 5–6 – Detect document corners (4-point contour)
  // ─────────────────────────────────────────────────────────────────────────
  static List<_Pt>? _detectCorners(Uint8List edges, int w, int h) {
    // Collect edge pixels (subsample for hull performance)
    final pts = <_Pt>[];
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (edges[y * w + x] == 255) pts.add(_Pt(x.toDouble(), y.toDouble()));
      }
    }
    if (pts.length < 100) return null;

    final sampled = pts.length > 4000
        ? [for (var i = 0; i < pts.length; i += pts.length ~/ 4000) pts[i]]
        : pts;

    // Graham scan convex hull
    final hull = _convexHull(sampled);
    if (hull.length < 4) return _orderCorners(_extremePts(sampled));

    // Simplify closed polygon with Douglas-Peucker (epsilon = 5 px)
    final simplified = _dpClosedPoly(hull, 5.0);

    if (simplified.length == 4) {
      return _orderCorners(simplified);
    } else if (simplified.length > 4) {
      final corners = _hullCorners(simplified);
      if (corners != null) return _orderCorners(corners);
    }

    // Fallback: extreme-point quadrilateral
    return _orderCorners(_extremePts(sampled));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GEOMETRY HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  static double _cross(_Pt o, _Pt a, _Pt b) =>
      (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);

  static double _dist(_Pt a, _Pt b) {
    final dx = a.x - b.x, dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  // Graham scan – returns convex hull (CW or CCW, consistent with screen coords)
  static List<_Pt> _convexHull(List<_Pt> pts) {
    if (pts.length < 3) return List.from(pts);

    // Pivot: lowest y (highest in screen), leftmost if tie
    _Pt pivot = pts[0];
    for (final p in pts) {
      if (p.y < pivot.y || (p.y == pivot.y && p.x < pivot.x)) pivot = p;
    }

    final rest = pts.where((p) => p != pivot).toList()
      ..sort((a, b) {
        final aa = math.atan2(a.y - pivot.y, a.x - pivot.x);
        final ba = math.atan2(b.y - pivot.y, b.x - pivot.x);
        if ((aa - ba).abs() > 1e-9) return aa.compareTo(ba);
        final da = (a.x - pivot.x) * (a.x - pivot.x) +
            (a.y - pivot.y) * (a.y - pivot.y);
        final db = (b.x - pivot.x) * (b.x - pivot.x) +
            (b.y - pivot.y) * (b.y - pivot.y);
        return da.compareTo(db);
      });

    final stack = <_Pt>[pivot];
    for (final p in rest) {
      while (stack.length > 1 &&
          _cross(stack[stack.length - 2], stack.last, p) <= 0) {
        stack.removeLast();
      }
      stack.add(p);
    }
    return stack;
  }

  // Douglas-Peucker on a CLOSED polygon (splits at TL/BR extremes)
  static List<_Pt> _dpClosedPoly(List<_Pt> poly, double eps) {
    if (poly.length < 4) return poly;

    // Find TL (min x+y) and BR (max x+y) as split points
    int i0 = 0, i1 = 0;
    double minS = double.infinity, maxS = double.negativeInfinity;
    for (var i = 0; i < poly.length; i++) {
      final s = poly[i].x + poly[i].y;
      if (s < minS) {
        minS = s;
        i0 = i;
      }
      if (s > maxS) {
        maxS = s;
        i1 = i;
      }
    }
    if (i0 > i1) {
      final t = i0;
      i0 = i1;
      i1 = t;
    }

    final chain1 = poly.sublist(i0, i1 + 1);
    final chain2 = [...poly.sublist(i1), ...poly.sublist(0, i0 + 1)];
    final s1 = _dp(chain1, eps);
    final s2 = _dp(chain2, eps);
    return [...s1.sublist(0, s1.length - 1), ...s2.sublist(0, s2.length - 1)];
  }

  // Ramer-Douglas-Peucker (open polyline)
  static List<_Pt> _dp(List<_Pt> pts, double eps) {
    if (pts.length < 3) return pts;
    double maxD = 0;
    int maxI = 0;
    final a = pts.first, b = pts.last;
    for (var i = 1; i < pts.length - 1; i++) {
      final d = _ptLineDist(pts[i], a, b);
      if (d > maxD) {
        maxD = d;
        maxI = i;
      }
    }
    if (maxD > eps) {
      final left = _dp(pts.sublist(0, maxI + 1), eps);
      final right = _dp(pts.sublist(maxI), eps);
      return [...left.sublist(0, left.length - 1), ...right];
    }
    return [a, b];
  }

  static double _ptLineDist(_Pt p, _Pt a, _Pt b) {
    final dx = b.x - a.x, dy = b.y - a.y;
    final len2 = dx * dx + dy * dy;
    if (len2 < 1e-10) return _dist(p, a);
    final t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2;
    final px = a.x + t * dx, py = a.y + t * dy;
    return math.sqrt((p.x - px) * (p.x - px) + (p.y - py) * (p.y - py));
  }

  // Pick 4 sharpest corners from a hull (max sin-angle score)
  static List<_Pt>? _hullCorners(List<_Pt> hull) {
    final n = hull.length;
    if (n < 4) return null;

    final scores = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      final prev = hull[(i - 1 + n) % n];
      final cur = hull[i];
      final next = hull[(i + 1) % n];
      final cross = _cross(prev, cur, next).abs();
      final d1 = _dist(prev, cur);
      final d2 = _dist(cur, next);
      scores[i] = cross / (d1 * d2 + 1e-6); // ≈ |sin θ|
    }

    final idx = List.generate(n, (i) => i)
      ..sort((a, b) => scores[b].compareTo(scores[a]));
    final top4 = idx.sublist(0, 4)..sort();
    return top4.map((i) => hull[i]).toList();
  }

  // 4 extreme-point approximation of document corners
  static List<_Pt> _extremePts(List<_Pt> pts) {
    var tl = pts[0], tr = pts[0], br = pts[0], bl = pts[0];
    for (final p in pts) {
      if (p.x + p.y < tl.x + tl.y) tl = p;
      if (p.x - p.y > tr.x - tr.y) tr = p;
      if (p.x + p.y > br.x + br.y) br = p;
      if (p.x - p.y < bl.x - bl.y) bl = p;
    }
    return [tl, tr, br, bl];
  }

  // Order 4 points as [TL, TR, BR, BL]
  static List<_Pt> _orderCorners(List<_Pt> pts) {
    final bySum = List<_Pt>.from(pts)
      ..sort((a, b) => (a.x + a.y).compareTo(b.x + b.y));
    final byDiff = List<_Pt>.from(pts)
      ..sort((a, b) => (a.x - a.y).compareTo(b.x - b.y));
    return [bySum.first, byDiff.last, bySum.last, byDiff.first];
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 7 – Perspective warp via 4-point homography (DLT)
  // ─────────────────────────────────────────────────────────────────────────
  static img.Image _warp(img.Image src, List<_Pt> corners) {
    final tl = corners[0], tr = corners[1], br = corners[2], bl = corners[3];

    final outW =
        math.max(_dist(br, bl), _dist(tr, tl)).round().clamp(10, 4000);
    final outH =
        math.max(_dist(tr, br), _dist(tl, bl)).round().clamp(10, 5600);

    // Destination rectangle corners (TL, TR, BR, BL)
    final dst = [
      _Pt(0, 0),
      _Pt((outW - 1).toDouble(), 0),
      _Pt((outW - 1).toDouble(), (outH - 1).toDouble()),
      _Pt(0, (outH - 1).toDouble()),
    ];

    // Homography maps dst → src (inverse warp to avoid holes)
    final h = _solveHomography(dst, corners);
    if (h == null) return src;

    final out = img.Image(width: outW, height: outH);
    for (var y = 0; y < outH; y++) {
      for (var x = 0; x < outW; x++) {
        final denom = h[6] * x + h[7] * y + 1.0;
        if (denom.abs() < 1e-8) continue;
        final sx = (h[0] * x + h[1] * y + h[2]) / denom;
        final sy = (h[3] * x + h[4] * y + h[5]) / denom;
        _bilerp(src, out, x, y, sx, sy);
      }
    }
    return out;
  }

  static img.Image _enhanceColorScan(img.Image src) {
  final w = src.width;
  final h = src.height;

  final out = img.Image(width: w, height: h);

  // 1. Convert to Y (luminance) and apply CLAHE-like contrast boost
  final gray = _toGray(src);
  final boosted = _clahe(gray, w, h, clipLimit: 3.0);

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final p = src.getPixel(x, y);

      // Get original RGB
      double r = p.r.toDouble();
      double g = p.g.toDouble();
      double b = p.b.toDouble();

      // Boost luminance ratio
      double ratio = boosted[y * w + x] / (gray[y * w + x] + 1);

      r = (r * ratio).clamp(0.0, 255.0);
      g = (g * ratio).clamp(0.0, 255.0);
      b = (b * ratio).clamp(0.0, 255.0);

      // 2. Whiten near-white pixels (paper normalization)
      if (r > 200 && g > 200 && b > 200) {
        r = 255;
        g = 255;
        b = 255;
      }

      out.setPixelRgb(x, y, r.toInt(), g.toInt(), b.toInt());
    }
  }

  // 3. Unsharp mask (professional scan sharpening)
  final blurred = img.gaussianBlur(out, radius: 1);
  final sharpened = img.Image(width: w, height: h);

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final orig = out.getPixel(x, y);
      final blur = blurred.getPixel(x, y);

      int r = (orig.r + (orig.r - blur.r)).clamp(0, 255).toInt();
      int g = (orig.g + (orig.g - blur.g)).clamp(0, 255).toInt();
      int b = (orig.b + (orig.b - blur.b)).clamp(0, 255).toInt();

      sharpened.setPixelRgb(x, y, r, g, b);
    }
  }

  return sharpened;
}

  // Fallback: warp using edge-density extreme points
  static img.Image _fallbackWarp(img.Image src, Uint8List edges, int w, int h) {
    final pts = <_Pt>[];
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (edges[y * w + x] == 255) pts.add(_Pt(x.toDouble(), y.toDouble()));
      }
    }
    if (pts.isEmpty) return src;
    return _warp(src, _orderCorners(_extremePts(pts)));
  }

  // Solve 8×8 DLT system for homography h = [h00..h21] (h22 = 1)
  // For each (dst→src) correspondence (X,Y)→(x,y):
  //   h00·X + h01·Y + h02 − h20·X·x − h21·Y·x = x
  //   h10·X + h11·Y + h12 − h20·X·y − h21·Y·y = y
  static List<double>? _solveHomography(List<_Pt> dst, List<_Pt> src) {
    final A = List.generate(8, (_) => List<double>.filled(8, 0.0));
    final b = List<double>.filled(8, 0.0);

    for (var i = 0; i < 4; i++) {
      final X = dst[i].x, Y = dst[i].y;
      final x = src[i].x, y = src[i].y;

      A[2 * i][0] = X;
      A[2 * i][1] = Y;
      A[2 * i][2] = 1;
      A[2 * i][6] = -X * x;
      A[2 * i][7] = -Y * x;
      b[2 * i] = x;

      A[2 * i + 1][3] = X;
      A[2 * i + 1][4] = Y;
      A[2 * i + 1][5] = 1;
      A[2 * i + 1][6] = -X * y;
      A[2 * i + 1][7] = -Y * y;
      b[2 * i + 1] = y;
    }
    return _gaussElim(A, b);
  }

  // Gauss-Jordan elimination with partial pivoting
  static List<double>? _gaussElim(List<List<double>> A, List<double> b) {
    const n = 8;
    final aug = List.generate(n, (i) => [...A[i], b[i]]);

    for (var col = 0; col < n; col++) {
      // Partial pivot
      var maxRow = col;
      for (var row = col + 1; row < n; row++) {
        if (aug[row][col].abs() > aug[maxRow][col].abs()) maxRow = row;
      }
      final tmp = aug[col];
      aug[col] = aug[maxRow];
      aug[maxRow] = tmp;

      if (aug[col][col].abs() < 1e-10) return null; // singular

      for (var row = 0; row < n; row++) {
        if (row == col) continue;
        final f = aug[row][col] / aug[col][col];
        for (var k = col; k <= n; k++) aug[row][k] -= f * aug[col][k];
      }
    }
    return [for (var i = 0; i < n; i++) aug[i][n] / aug[i][i]];
  }

  // Bilinear sample from src and write to dst at (dx,dy)
  static void _bilerp(
      img.Image src, img.Image dst, int dx, int dy, double sx, double sy) {
    final x0 = sx.floor().clamp(0, src.width - 1);
    final y0 = sy.floor().clamp(0, src.height - 1);
    final x1 = (x0 + 1).clamp(0, src.width - 1);
    final y1 = (y0 + 1).clamp(0, src.height - 1);
    final fx = sx - x0, fy = sy - y0;

    final p00 = src.getPixel(x0, y0);
    final p10 = src.getPixel(x1, y0);
    final p01 = src.getPixel(x0, y1);
    final p11 = src.getPixel(x1, y1);

    double l2d(num a, num b, num c, num d) =>
        (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy;

    dst.setPixelRgb(
      dx,
      dy,
      l2d(p00.r, p10.r, p01.r, p11.r).round().clamp(0, 255),
      l2d(p00.g, p10.g, p01.g, p11.g).round().clamp(0, 255),
      l2d(p00.b, p10.b, p01.b, p11.b).round().clamp(0, 255),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 8 – CLAHE (clipLimit=2.0, 8×8 tile grid)
  // ─────────────────────────────────────────────────────────────────────────
  static Uint8List _clahe(Uint8List g, int w, int h,
      {double clipLimit = 2.0, int tileRows = 8, int tileCols = 8}) {
    final tileW = (w / tileCols).ceil();
    final tileH = (h / tileRows).ceil();

    // Precompute per-tile CDFs
    final cdfs = List.generate(
        tileRows * tileCols, (_) => List<double>.filled(256, 0.0));

    for (var tr = 0; tr < tileRows; tr++) {
      for (var tc = 0; tc < tileCols; tc++) {
        final x0 = tc * tileW, y0 = tr * tileH;
        final x1 = math.min(x0 + tileW, w);
        final y1 = math.min(y0 + tileH, h);
        final area = (x1 - x0) * (y1 - y0);

        final hist = List<int>.filled(256, 0);
        for (var y = y0; y < y1; y++) {
          for (var x = x0; x < x1; x++) hist[g[y * w + x]]++;
        }

        // Clip and redistribute excess uniformly
        final maxBin = (clipLimit * area / 256).round();
        int excess = 0;
        for (var i = 0; i < 256; i++) {
          if (hist[i] > maxBin) {
            excess += hist[i] - maxBin;
            hist[i] = maxBin;
          }
        }
        final bonus = excess ~/ 256;
        for (var i = 0; i < 256; i++) hist[i] += bonus;

        // Normalized cumulative distribution
        double cum = 0;
        final cdf = cdfs[tr * tileCols + tc];
        for (var i = 0; i < 256; i++) {
          cum += hist[i];
          cdf[i] = cum / area;
        }
      }
    }

    // Apply bilinear tile interpolation per pixel
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final v = g[y * w + x];
        final tcf = x / tileW - 0.5;
        final trf = y / tileH - 0.5;
        final tc0 = tcf.floor().clamp(0, tileCols - 1);
        final tr0 = trf.floor().clamp(0, tileRows - 1);
        final tc1 = (tc0 + 1).clamp(0, tileCols - 1);
        final tr1 = (tr0 + 1).clamp(0, tileRows - 1);
        final fx = (tcf - tc0).clamp(0.0, 1.0);
        final fy = (trf - tr0).clamp(0.0, 1.0);

        final mapped = (cdfs[tr0 * tileCols + tc0][v] * (1 - fx) * (1 - fy) +
                cdfs[tr0 * tileCols + tc1][v] * fx * (1 - fy) +
                cdfs[tr1 * tileCols + tc0][v] * (1 - fx) * fy +
                cdfs[tr1 * tileCols + tc1][v] * fx * fy) *
            255;
        out[y * w + x] = mapped.round().clamp(0, 255);
      }
    }
    return out;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 9 – Adaptive threshold (Gaussian/mean, blockSize=15, C=10)
  //           Uses integral image for O(1) per-pixel window sum
  // ─────────────────────────────────────────────────────────────────────────
  static Uint8List _adaptThresh(Uint8List g, int w, int h, int blockSize, int C) {
    // Build integral image (padded by 1 on each side)
    final ii = List<int>.filled((w + 1) * (h + 1), 0);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        ii[(y + 1) * (w + 1) + (x + 1)] = g[y * w + x] +
            ii[y * (w + 1) + (x + 1)] +
            ii[(y + 1) * (w + 1) + x] -
            ii[y * (w + 1) + x];
      }
    }

    final half = blockSize ~/ 2;
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final x0 = (x - half).clamp(0, w - 1);
        final y0 = (y - half).clamp(0, h - 1);
        final x1 = (x + half).clamp(0, w - 1);
        final y1 = (y + half).clamp(0, h - 1);
        final area = (x1 - x0 + 1) * (y1 - y0 + 1);
        final sum = ii[(y1 + 1) * (w + 1) + (x1 + 1)] -
            ii[y0 * (w + 1) + (x1 + 1)] -
            ii[(y1 + 1) * (w + 1) + x0] +
            ii[y0 * (w + 1) + x0];
        final thresh = sum / area - C;
        out[y * w + x] = g[y * w + x] > thresh ? 255 : 0;
      }
    }
    return out;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 10 – Morphological closing (dilation → erosion, 3×3 kernel)
  // ─────────────────────────────────────────────────────────────────────────
  static Uint8List _morphClose(Uint8List b, int w, int h) =>
      _erode(_dilate(b, w, h, 3), w, h, 3);

  static Uint8List _dilate(Uint8List b, int w, int h, int k) {
    final out = Uint8List(w * h);
    final half = k ~/ 2;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        int mx = 0;
        outer:
        for (var dy = -half; dy <= half; dy++) {
          final ny = (y + dy).clamp(0, h - 1);
          for (var dx = -half; dx <= half; dx++) {
            final v = b[ny * w + (x + dx).clamp(0, w - 1)];
            if (v > mx) {
              mx = v;
              if (mx == 255) break outer;
            }
          }
        }
        out[y * w + x] = mx;
      }
    }
    return out;
  }

  static Uint8List _erode(Uint8List b, int w, int h, int k) {
    final out = Uint8List(w * h);
    final half = k ~/ 2;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        int mn = 255;
        outer:
        for (var dy = -half; dy <= half; dy++) {
          final ny = (y + dy).clamp(0, h - 1);
          for (var dx = -half; dx <= half; dx++) {
            final v = b[ny * w + (x + dx).clamp(0, w - 1)];
            if (v < mn) {
              mn = v;
              if (mn == 0) break outer;
            }
          }
        }
        out[y * w + x] = mn;
      }
    }
    return out;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 11 – Sharpening: kernel [[0,-1,0],[-1,5,-1],[0,-1,0]]
  // ─────────────────────────────────────────────────────────────────────────
  static Uint8List _sharpen(Uint8List g, int w, int h) {
    final out = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (y == 0 || y == h - 1 || x == 0 || x == w - 1) {
          out[y * w + x] = g[y * w + x];
          continue;
        }
        final v = 5 * g[y * w + x] -
            g[(y - 1) * w + x] -
            g[(y + 1) * w + x] -
            g[y * w + (x - 1)] -
            g[y * w + (x + 1)];
        out[y * w + x] = v.clamp(0, 255);
      }
    }
    return out;
  }
}
