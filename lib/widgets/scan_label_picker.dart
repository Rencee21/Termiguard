import 'package:flutter/material.dart';

import '../models/scan_result.dart';

/// Three tap-to-select chips: Termite / Clean wood / Background noise.
/// Tap the selected chip again to clear the label.
class ScanLabelPicker extends StatefulWidget {
  final ScanLabel? initial;
  final ValueChanged<ScanLabel?> onChanged;

  const ScanLabelPicker({
    super.key,
    required this.onChanged,
    this.initial,
  });

  @override
  State<ScanLabelPicker> createState() => _ScanLabelPickerState();
}

class _ScanLabelPickerState extends State<ScanLabelPicker> {
  ScanLabel? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  @override
  void didUpdateWidget(covariant ScanLabelPicker old) {
    super.didUpdateWidget(old);
    if (old.initial != widget.initial) {
      setState(() => _selected = widget.initial);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'What was really being scanned?',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final l in ScanLabel.values)
              ChoiceChip(
                label: Text(l.display),
                selected: _selected == l,
                onSelected: (on) {
                  final next = on ? l : null;
                  setState(() => _selected = next);
                  widget.onChanged(next);
                },
              ),
          ],
        ),
      ],
    );
  }
}
