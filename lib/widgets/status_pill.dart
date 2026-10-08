import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum PillTone { success, warning, danger, info, neutral }

class _ToneColors {
  final Color fg;
  final Color bg;
  final Color border;
  const _ToneColors(this.fg, this.bg, this.border);
}

const _toneMap = {
  PillTone.success:
      _ToneColors(AppColors.success, AppColors.successBg, AppColors.successBorder),
  PillTone.warning:
      _ToneColors(AppColors.warning, AppColors.warningBg, AppColors.warningBorder),
  PillTone.danger:
      _ToneColors(AppColors.danger, AppColors.dangerBg, AppColors.dangerBorder),
  PillTone.info: _ToneColors(AppColors.info, AppColors.infoBg, AppColors.infoBorder),
  PillTone.neutral:
      _ToneColors(AppColors.neutral, AppColors.neutralBg, AppColors.neutralBorder),
};

/// A small rounded status pill, e.g. "System Ready", "Connected",
/// "Checking...", used across the home / hardware / results screens —
/// the Flutter equivalent of `.status-badge[data-state]` in the CSS.
class StatusPill extends StatelessWidget {
  final String label;
  final PillTone tone;
  final bool showDot;

  const StatusPill({
    super.key,
    required this.label,
    required this.tone,
    this.showDot = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _toneMap[tone]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: colors.fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: colors.fg,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
