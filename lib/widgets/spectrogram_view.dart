import 'package:flutter/material.dart';

import '../models/spectrogram_data.dart';
import '../theme/app_theme.dart';
import 'section_card.dart';

/// Maps an energy value (0..1) to a colour: dark green (quiet) ->
/// green -> amber -> red (loud), matching the app's palette.
Color spectrogramColor(double t) {
  const stops = <double>[0.0, 0.35, 0.65, 0.85, 1.0];
  const colors = <Color>[
    Color(0xFF0B1F17),
    AppColors.primaryLight,
    Color(0xFF95D5B2),
    Color(0xFFF2B84B),
    AppColors.danger,
  ];
  final v = t.clamp(0.0, 1.0).toDouble();
  for (var i = 0; i < stops.length - 1; i++) {
    if (v <= stops[i + 1]) {
      final local = (v - stops[i]) / (stops[i + 1] - stops[i]);
      return Color.lerp(colors[i], colors[i + 1], local)!;
    }
  }
  return colors.last;
}

/// Draws a full spectrogram: time runs left -> right, frequency runs
/// bottom ([kMinHz]) -> top ([kMaxHz]). The termite band is outlined.
///
/// Set [showAxes] to false for a small thumbnail (e.g. in History).
class SpectrogramView extends StatelessWidget {
  final SpectrogramData data;
  final double height;
  final bool showAxes;
  final bool highlightBand;

  /// Optional 0..1 position of a "now" line (used while a scan is live).
  final double? playhead;

  const SpectrogramView({
    super.key,
    required this.data,
    this.height = 220,
    this.showAxes = true,
    this.highlightBand = true,
    this.playhead,
  });

  @override
  Widget build(BuildContext context) {
    final canvas = ClipRRect(
      borderRadius: BorderRadius.circular(showAxes ? 12 : 10),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _SpectrogramPainter(data, highlightBand, playhead),
        ),
      ),
    );

    if (!showAxes) return canvas;

    const labelStyle = TextStyle(fontSize: 10, color: AppColors.mutedText);
    final seconds = data.duration.inMilliseconds / 1000;
    // Evenly spaced labels across the wider display axis
    // (kDisplayMinHz..kDisplayMaxHz), top = kDisplayMaxHz, bottom = 0.
    final yLabels = List.generate(5, (i) {
      final hz = kDisplayMinHz + (kDisplayMaxHz - kDisplayMinHz) * (4 - i) / 4;
      final khz = hz / 1000;
      final text =
          khz % 1 == 0 ? khz.toStringAsFixed(0) : khz.toStringAsFixed(1);
      return Text('$text kHz', style: labelStyle);
    });

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 38,
              height: height,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: yLabels,
              ),
            ),
            Expanded(child: canvas),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 38),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('0 s', style: labelStyle),
              Text('${(seconds / 2).toStringAsFixed(0)} s', style: labelStyle),
              Text('${seconds.toStringAsFixed(0)} s', style: labelStyle),
            ],
          ),
        ),
      ],
    );
  }
}

class _SpectrogramPainter extends CustomPainter {
  final SpectrogramData data;
  final bool highlightBand;
  final double? playhead;

  _SpectrogramPainter(this.data, this.highlightBand, this.playhead);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF0B1F17),
    );
    if (data.frames == 0 || data.bins == 0) return;

    final cellW = size.width / data.frames;
    const displayRange = kDisplayMaxHz - kDisplayMinHz;
    final paint = Paint()..isAntiAlias = false;

    // Convert a real Hz value to its y position on the padded
    // kDisplayMinHz..kDisplayMaxHz canvas (0 Hz at the bottom).
    double yForHz(double hz) =>
        size.height - ((hz - kDisplayMinHz) / displayRange) * size.height;

    for (var f = 0; f < data.frames; f++) {
      for (var b = 0; b < data.bins; b++) {
        final v = data.valueAt(f, b);
        // Silent cells are just the background, already painted.
        if (v < 0.01) continue;
        paint.color = spectrogramColor(v);
        // Bin b covers [kMinHz + b*binHz, kMinHz + (b+1)*binHz) —
        // mapped onto the wider display axis, real data (0.5-20kHz)
        // only fills its true slice of the canvas, never the padding
        // above kMaxHz.
        final binLowHz = kMinHz + b * data.binHz;
        final binHighHz = kMinHz + (b + 1) * data.binHz;
        final top = yForHz(binHighHz);
        final bottom = yForHz(binLowHz);
        canvas.drawRect(
          Rect.fromLTWH(f * cellW, top, cellW + 0.6, bottom - top + 0.6),
          paint,
        );
      }
    }

    if (highlightBand) {
      // Marks the real reading range (kMinHz..kMaxHz) at its true
      // position inside the wider 0-40kHz display axis.
      final bandTop = yForHz(kMaxHz);
      final bandBottom = yForHz(kMinHz);
      final line = Paint()
        ..color = Colors.white.withAlpha(200)
        ..strokeWidth = 1.2;
      _dashedLine(canvas, Offset(0, bandTop), Offset(size.width, bandTop), line);
      _dashedLine(
          canvas, Offset(0, bandBottom), Offset(size.width, bandBottom), line);

      if (size.height > 90) {
        final tp = TextPainter(
          text: TextSpan(
            text: kFrequencyRangeKHzLabel,
            style: TextStyle(
              color: Colors.white.withAlpha(230),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(size.width - tp.width - 6, bandTop + 3));
      }
    }

    _paintPlayhead(canvas, size);
  }

  void _paintPlayhead(Canvas canvas, Size size) {
    final p = playhead;
    if (p == null) return;
    final x = (p.clamp(0.0, 1.0).toDouble()) * size.width;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = Colors.white.withAlpha(220)
        ..strokeWidth = 1.5,
    );
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 6.0;
    const gap = 4.0;
    var x = a.dx;
    while (x < b.dx) {
      canvas.drawLine(
        Offset(x, a.dy),
        Offset((x + dash).clamp(a.dx, b.dx).toDouble(), a.dy),
        paint,
      );
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrogramPainter old) =>
      old.data != data ||
      old.highlightBand != highlightBand ||
      old.playhead != playhead;
}

/// Live equaliser-style bars for the single most recent audio frame,
/// shown while the scan is listening.
class LiveSpectrumBars extends StatelessWidget {
  final List<double> frame;
  final double height;

  const LiveSpectrumBars({super.key, required this.frame, this.height = 110});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: height,
        width: double.infinity,
        color: const Color(0xFF0B1F17),
        child: CustomPaint(painter: _BarsPainter(frame)),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  final List<double> frame;
  _BarsPainter(this.frame);

  @override
  void paint(Canvas canvas, Size size) {
    if (frame.isEmpty) return;
    final binHz = (kMaxHz - kMinHz) / frame.length;
    final slot = size.width / frame.length;
    final paint = Paint();

    for (var b = 0; b < frame.length; b++) {
      final hz = kMinHz + (b + 0.5) * binHz;
      final inBand = hz >= kBandLowHz && hz <= kBandHighHz;
      final h = (frame[b].clamp(0.0, 1.0).toDouble()) * size.height;
      paint.color = inBand ? const Color(0xFFF2B84B) : AppColors.secondary;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(b * slot + 1.5, size.height - h, slot - 3, h),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter old) => true;
}

/// Small colour legend: quiet -> loud.
class SpectrogramLegend extends StatelessWidget {
  const SpectrogramLegend({super.key});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 11, color: AppColors.mutedText);
    return Row(
      children: [
        const Text('Quiet', style: style),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: LinearGradient(
                colors: [
                  for (var i = 0; i <= 10; i++) spectrogramColor(i / 10),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        const Text('Loud', style: style),
      ],
    );
  }
}

/// A [SectionCard] holding a spectrogram, its colour legend and a
/// one-line caption. Used on both the Spectrogram and Result screens.
class SpectrogramCard extends StatelessWidget {
  final SpectrogramData data;
  final double height;

  const SpectrogramCard({super.key, required this.data, this.height = 220});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SpectrogramView(data: data, height: height),
          const SizedBox(height: 12),
          const SpectrogramLegend(),
          const SizedBox(height: 10),
          Text(
            'Time runs left to right, frequency bottom to top. Dashed lines '
            'mark the $kFrequencyRangeKHzLabel reading range.',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.mutedText,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}