import 'dart:typed_data';
import 'dart:ui' as ui;

/// The live tone histogram behind the Brightness + Gamma bars
/// (eq_imp.md §7a): you see where the picture's tones actually sit, and
/// where an adjustment pushes them — the camera-scope feel, drawn behind the
/// two controls that move them.
///
/// The picture is read through mpv's own screenshot (no new native
/// dependency, §7a's own note), decoded by Flutter's image codec, and binned
/// here. This file is the pure half: a buffer in, shares out — so the binning
/// is unit-testable with no player, no window and no file.
class ToneHistogram {
  const ToneHistogram(this.bins);

  /// Tone buckets, black → white. 32 reads well behind a 20 px bar and is
  /// more resolution than an eye can use on a 64 px-wide sample.
  static const int binCount = 32;

  /// Pixel counts, `bins[0]` = the darkest tone.
  final List<int> bins;

  int get total {
    int sum = 0;
    for (final int b in bins) {
      sum += b;
    }
    return sum;
  }

  bool get isEmpty => total == 0;

  /// The share of the frame sitting in bin [i], 0…1.
  double share(int i) {
    final int all = total;
    if (all == 0 || i < 0 || i >= bins.length) return 0;
    return bins[i] / all;
  }

  /// The frame's mean tone, 0…1 — the number Brightness really moves.
  double get meanTone {
    final int all = total;
    if (all == 0) return 0;
    double weighted = 0;
    for (int i = 0; i < bins.length; i++) {
      weighted += bins[i] * (i + 0.5);
    }
    return weighted / all / bins.length;
  }

  /// The tallest bin's share — what the drawing scales against, so a
  /// low-contrast frame still reads as a shape.
  double get peakShare {
    final int all = total;
    if (all == 0) return 0;
    int peak = 0;
    for (final int b in bins) {
      if (b > peak) peak = b;
    }
    return peak / all;
  }

  /// Bins a decoded frame. [rgba] is `rawRgba` (4 bytes a pixel, sRGB-ish,
  /// straight from Flutter's codec) and the stride is `width * 4`.
  ///
  /// Rec. 709 luma, which is what a video picture means by "brightness" —
  /// the same weighting the Brightness slider is perceived through.
  static ToneHistogram fromRgba(
    Uint8List rgba, {
    required int width,
    required int height,
  }) {
    final List<int> bins = List<int>.filled(binCount, 0);
    if (width <= 0 || height <= 0) return ToneHistogram(bins);
    final int pixels = width * height;
    for (int i = 0; i < pixels; i++) {
      final int o = i * 4;
      if (o + 3 >= rgba.length) break;
      final int r = rgba[o], g = rgba[o + 1], b = rgba[o + 2];
      // Stored as (luma × binCount) so the bin is an integer comparison.
      final int luma = (2126 * r + 7152 * g + 722 * b) ~/ 10000; // 0…255
      int bin = luma * binCount ~/ 256;
      if (bin < 0) bin = 0;
      if (bin >= binCount) bin = binCount - 1;
      bins[bin]++;
    }
    return ToneHistogram(bins);
  }

  /// The smoothed shape the bars draw: a small triangular blur, so 32 bins
  /// do not read as a comb. Pure, and normalised to the peak.
  List<double> get shape {
    final int all = total;
    if (all == 0) return List<double>.filled(binCount, 0);
    final List<double> out = List<double>.filled(binCount, 0);
    for (int i = 0; i < binCount; i++) {
      final double a = bins[i] / all;
      final double l = i > 0 ? bins[i - 1] / all : a;
      final double r = i < binCount - 1 ? bins[i + 1] / all : a;
      out[i] = a * 0.6 + l * 0.2 + r * 0.2;
    }
    final double peak = out.reduce((double a, double b) => a > b ? a : b);
    if (peak > 0) {
      for (int i = 0; i < binCount; i++) {
        out[i] = out[i] / peak;
      }
    }
    return out;
  }
}

/// Reads the playing frame and bins it. The capture is injected (the engine
/// owns the mpv side), so this class holds only the decode-and-bin step, and
/// a test can hand it a synthetic image.
class ToneHistogramSampler {
  const ToneHistogramSampler({required this.capture});

  final Future<ui.Image?> Function() capture;

  /// One reading, `null` when there was nothing to read. The image is
  /// disposed here — the caller only ever sees the bins.
  Future<ToneHistogram?> sample() async {
    final ui.Image? image = await capture();
    if (image == null) return null;
    try {
      final ByteData? data =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      return ToneHistogram.fromRgba(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        width: image.width,
        height: image.height,
      );
    } finally {
      image.dispose();
    }
  }
}
