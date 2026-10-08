import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Lowest frequency shown on the spectrogram (Hz).
const double kMinHz = 500;

/// Highest frequency shown on the spectrogram (Hz). The ESP32 samples
/// at 40 kHz, so 20 kHz stays exactly at Nyquist and is a real,
/// measurable FFT ceiling (not just a display value).
const double kMaxHz = 20000;

/// The spectrogram widget's visual axis runs from [kDisplayMinHz] to
/// [kDisplayMaxHz] — wider than the real measured range above, purely
/// for display headroom. No data is ever drawn outside [kMinHz]..
/// [kMaxHz]; the space beyond stays empty background. This is what lets
/// the white dashed markers (drawn at the real kMinHz/kMaxHz positions)
/// sit inside the canvas instead of right on its edges.
const double kDisplayMinHz = 0;
const double kDisplayMaxHz = 40000;

/// The frequency band where termite activity is expected (Hz). This
/// band is highlighted on every spectrogram and is what the "band
/// hits" count is measured against.
const double kBandLowHz = 3000;
const double kBandHighHz = 5000;

String _kHz(double hz) =>
    hz % 1000 == 0 ? '${hz ~/ 1000}' : (hz / 1000).toStringAsFixed(1);

/// Human-readable band, e.g. "3–5 kHz". Follows the constants above.
final String kBandLabel = '${_kHz(kBandLowHz)}–${_kHz(kBandHighHz)} kHz';

/// Formats a frequency with a thousands separator, e.g. 20000 -> "20,000 Hz".
String _formatHz(double hz) {
  final digits = hz.round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '${buffer.toString()} Hz';
}

/// Human-readable scanning range, e.g. "500 Hz – 20,000 Hz". Follows
/// [kMinHz]/[kMaxHz] above.
final String kFrequencyRangeLabel =
    '${_formatHz(kMinHz)} – ${_formatHz(kMaxHz)}';

/// Compact kHz form of the scanning range, e.g. "0.5kHz - 20kHz". Used
/// as the label next to the white dashed reading-range markers on the
/// spectrogram itself.
final String kFrequencyRangeKHzLabel = '${_kHz(kMinHz)}kHz - ${_kHz(kMaxHz)}kHz';

/// A scan counts as "termite activity detected" when at least this
/// many frames contain a click inside the band.
const int kMinHitsToDetect = 3;

/// A frame whose peak energy inside the band is at or above this
/// (0..1) counts as one "hit".
const double kHitThreshold = 0.5;

/// A recorded audio spectrogram: [frames] time slices, each with
/// [bins] frequency bins spanning [kMinHz]..[kMaxHz]. Energy is stored
/// as one byte (0..255) per cell so it stays small enough to save in
/// scan history.
class SpectrogramData {
  final int frames;
  final int bins;
  final int frameMs;

  /// Row-major by frame: index = frame * bins + bin.
  final Uint8List cells;

  SpectrogramData({
    required this.frames,
    required this.bins,
    required this.frameMs,
    required this.cells,
  }) : assert(cells.length == frames * bins);

  /// Builds a spectrogram from per-frame energies (each 0..1).
  factory SpectrogramData.fromFrames(
    List<List<double>> frames, {
    required int frameMs,
  }) {
    final bins = frames.isEmpty ? 0 : frames.first.length;
    final bytes = Uint8List(frames.length * bins);
    for (var f = 0; f < frames.length; f++) {
      for (var b = 0; b < bins; b++) {
        bytes[f * bins + b] = (frames[f][b].clamp(0.0, 1.0) * 255).round();
      }
    }
    return SpectrogramData(
      frames: frames.length,
      bins: bins,
      frameMs: frameMs,
      cells: bytes,
    );
  }

  /// Which frequency bin a frequency (Hz) falls in. A frequency exactly
  /// on the band's upper edge (e.g. 5000 Hz) belongs to the band.
  static int binForHz(double hz, int bins) {
    final binHz = (kMaxHz - kMinHz) / bins;
    final bin = ((hz - kMinHz - 0.001) / binHz).floor();
    return max(0, min(bins - 1, bin));
  }

  double get binHz => (kMaxHz - kMinHz) / bins;
  Duration get duration => Duration(milliseconds: frames * frameMs);

  /// First bin inside the highlighted band (inclusive).
  int get bandLowBin => ((kBandLowHz - kMinHz) / binHz).floor();

  /// Last bin inside the highlighted band (exclusive).
  int get bandHighBin => min(bins, ((kBandHighHz - kMinHz) / binHz).ceil());

  /// Energy at ([frame], [bin]) as 0..1.
  double valueAt(int frame, int bin) => cells[frame * bins + bin] / 255.0;

  SpectrogramAnalysis analyze() {
    var hits = 0;
    final binTotals = List<double>.filled(bins, 0);
    var grandTotal = 0.0;

    for (var f = 0; f < frames; f++) {
      var bandPeak = 0.0;
      for (var b = 0; b < bins; b++) {
        final v = valueAt(f, b);
        binTotals[b] += v;
        grandTotal += v;
        if (b >= bandLowBin && b < bandHighBin && v > bandPeak) {
          bandPeak = v;
        }
      }
      if (bandPeak >= kHitThreshold) hits++;
    }

    var dominantBin = 0;
    for (var b = 1; b < bins; b++) {
      if (binTotals[b] > binTotals[dominantBin]) dominantBin = b;
    }

    final meanLevel = (frames * bins) == 0 ? 0.0 : grandTotal / (frames * bins);

    return SpectrogramAnalysis(
      bandHits: hits,
      totalFrames: frames,
      dominantHz: grandTotal == 0 ? 0 : kMinHz + (dominantBin + 0.5) * binHz,
      // Purely a display scale: 0 -> -60 dB, 1 -> 0 dB.
      averageDb: -60 + meanLevel * 60,
    );
  }

  Map<String, dynamic> toJson() => {
        'frames': frames,
        'bins': bins,
        'frameMs': frameMs,
        'cells': base64Encode(cells),
      };

  factory SpectrogramData.fromJson(Map<String, dynamic> json) {
    final bytes = base64Decode(json['cells'] as String);
    return SpectrogramData(
      frames: json['frames'] as int,
      bins: json['bins'] as int,
      frameMs: json['frameMs'] as int,
      cells: Uint8List.fromList(bytes),
    );
  }
}

class SpectrogramAnalysis {
  final int bandHits;
  final int totalFrames;
  final double dominantHz;
  final double averageDb;

  const SpectrogramAnalysis({
    required this.bandHits,
    required this.totalFrames,
    required this.dominantHz,
    required this.averageDb,
  });

  double get hitRatio => totalFrames == 0 ? 0 : bandHits / totalFrames;

  String get dominantLabel =>
      dominantHz == 0 ? '—' : '${dominantHz.round()} Hz';
  String get averageDbLabel => '${averageDb.toStringAsFixed(0)} dB avg';
}