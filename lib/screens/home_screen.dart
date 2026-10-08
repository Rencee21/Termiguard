import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/section_card.dart';
import '../widgets/status_pill.dart';
import 'hardware_screen.dart';

/// Flutter equivalent of index.php — the home / landing page.
class HomeScreen extends StatelessWidget {
  final VoidCallback? onScanPressed;

  const HomeScreen({super.key, this.onScanPressed});

  static const _steps = [
    (
      icon: Icons.settings_input_antenna,
      title: '1. Connect Hardware',
      body: 'Connect the Termiguard sensor device (ESP32 + microphone) '
          'before starting the scan.',
    ),
    (
      icon: Icons.hearing,
      title: '2. Scan',
      body: 'Termiguard listens to the audio picked up by the sensor for '
          'sound patterns associated with termite activity inside the '
          'structure.',
    ),
    (
      icon: Icons.graphic_eq,
      title: '3. Spectrogram',
      body: 'See the recorded audio as a spectrogram (frequency over '
          'time) so termite activity stands out visually.',
    ),
    (
      icon: Icons.fact_check_outlined,
      title: '4. History Result',
      body: 'Get a clear detection result and confidence score, and '
          'review every saved scan in your history.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Termiguard')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ===================== HERO SECTION =====================
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Termiguard',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'An Early Termite Activity Detection System',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Termiguard helps you detect early signs of termite '
                  'activity inside wood, walls, and wooden structures by '
                  'listening with acoustic sensing hardware and showing '
                  'what it hears as a spectrogram.',
                  style: TextStyle(color: Colors.white, height: 1.5),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primaryDark,
                  ),
                  onPressed: onScanPressed ??
                      () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const HardwareScreen()),
                        );
                      },
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan Wood'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ================= HOW IT WORKS SECTION =================
          const SectionTitle(title: 'How Termiguard Works'),
          ..._steps.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SectionCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.successBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(s.icon, color: AppColors.primary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.heading,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            s.body,
                            style: const TextStyle(
                              color: AppColors.mutedText,
                              height: 1.4,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ================= SYSTEM STATUS SECTION =================
          const SectionTitle(title: 'System Status'),
          const SectionCard(
            child: Row(
              children: [
                StatusPill(label: 'System Ready', tone: PillTone.success),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Last scan: —   •   Hardware last seen: —',
                    style: TextStyle(color: AppColors.mutedText, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
