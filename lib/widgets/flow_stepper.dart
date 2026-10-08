import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The four steps of a scan, shown at the top of each screen in the
/// flow so it's always clear where you are.
class FlowStepper extends StatelessWidget {
  /// 0 = Connect Hardware, 1 = Scan, 2 = Spectrogram, 3 = Result.
  final int current;

  const FlowStepper({super.key, required this.current});

  static const _labels = ['Connect', 'Scan', 'Spectrogram', 'Result'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _labels.length; i++) ...[
          Expanded(child: _Step(index: i, label: _labels[i], current: current)),
          if (i < _labels.length - 1)
            Container(
              width: 10,
              height: 2,
              margin: const EdgeInsets.only(bottom: 18),
              color: i < current ? AppColors.secondary : AppColors.border,
            ),
        ],
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final int index;
  final String label;
  final int current;

  const _Step({required this.index, required this.label, required this.current});

  @override
  Widget build(BuildContext context) {
    final done = index < current;
    final active = index == current;
    final filled = done || active;

    return Column(
      children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: filled ? AppColors.primary : AppColors.neutralBg,
          child: done
              ? const Icon(Icons.check, size: 15, color: Colors.white)
              : Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: filled ? Colors.white : AppColors.mutedText,
                  ),
                ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? AppColors.heading : AppColors.mutedText,
          ),
        ),
      ],
    );
  }
}
