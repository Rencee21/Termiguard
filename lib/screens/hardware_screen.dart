import 'dart:async';

import 'package:flutter/material.dart';

import '../models/scan_result.dart';
import '../services/esp32_service.dart';
import '../theme/app_theme.dart';
import '../widgets/flow_stepper.dart';
import '../widgets/section_card.dart';
import '../widgets/status_pill.dart';
import 'scanning_screen.dart';

/// Step 1 of the flow — verifies the Termiguard hardware before a
/// scan can start.
///
/// The status is REAL: it watches the ESP32's data in Firebase (see
/// [Esp32Service]). "Connected" only shows while fresh data keeps
/// arriving. If the ESP32 is unplugged, or this device is offline,
/// it switches to "Disconnected" and Start Scanning is disabled.
class HardwareScreen extends StatefulWidget {
  const HardwareScreen({super.key});

  @override
  State<HardwareScreen> createState() => _HardwareScreenState();
}

class _HardwareScreenState extends State<HardwareScreen> {
  static const _deviceNames = [
    'ESP32 Microcontroller',
    'Microphone / Acoustic Sensor',
    'Power Supply',
  ];

  final _service = Esp32Service();
  StreamSubscription<Esp32Status>? _sub;
  Esp32Status _status = Esp32Status.checking;

  bool get _checking => _status == Esp32Status.checking;
  bool get _allConnected => _status == Esp32Status.online;

  // We can only observe one thing: is the ESP32's data alive? So all
  // three components share that state.
  HardwareState get _deviceState {
    switch (_status) {
      case Esp32Status.online:
        return HardwareState.connected;
      case Esp32Status.checking:
        return HardwareState.checking;
      case Esp32Status.deviceOffline:
      case Esp32Status.appOffline:
      case Esp32Status.error:
        return HardwareState.disconnected;
    }
  }

  String get _statusMessage {
    switch (_status) {
      case Esp32Status.online:
        return 'All devices connected';
      case Esp32Status.checking:
        return 'Checking devices…';
      case Esp32Status.deviceOffline:
        return 'No live data from the Termiguard device. Make sure the '
            'ESP32 is powered on and connected to Wi-Fi, then tap '
            '"Check Connection".';
      case Esp32Status.appOffline:
        return 'This device is offline. Check your internet connection, '
            'then tap "Check Connection".';
      case Esp32Status.error:
        return 'Could not read from Firebase. Check your database rules '
            'and setup, then tap "Check Connection".';
    }
  }

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    // Start the live click feed now, so a scan can begin instantly.
    _service.startEventFeed();
    _sub?.cancel();
    _sub = _service.watch().listen((status) {
      if (!mounted) return;
      setState(() => _status = status);
    });
  }

  /// Restarts the check (the "Check Connection" button). The status
  /// also keeps updating live on its own, so unplugging the ESP32
  /// flips it to Disconnected without pressing anything.
  void _checkConnection() {
    setState(() => _status = Esp32Status.checking);
    _listen();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _startScanning() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ScanningScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connect Hardware')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const FlowStepper(current: 0),
          const SizedBox(height: 20),
          const Text(
            'Make sure the Termiguard sensor device is connected and '
            'powered on before starting the scan.',
            style: TextStyle(color: AppColors.mutedText, height: 1.4),
          ),
          const SizedBox(height: 20),

          // ================= CONNECTION INSTRUCTIONS =================
          const SectionTitle(title: 'Connection Instructions'),
          const SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InstructionStep(1,
                    'Power on the ESP32 device and place the microphone/acoustic sensor against the wood or wall surface.'),
                _InstructionStep(2,
                    'Make sure the ESP32 is connected to Wi-Fi and this device has an internet connection.'),
                _InstructionStep(
                    3, 'Tap "Check Connection" to verify each component below.'),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ================= HARDWARE STATUS PANEL =================
          const SectionTitle(title: 'Device Status'),
          ..._deviceNames.map(
            (name) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SectionCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    _pillFor(_deviceState),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SectionCard(
            child: Row(
              children: [
                const Icon(Icons.dns_outlined, color: AppColors.mutedText),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _statusMessage,
                    style: const TextStyle(color: AppColors.mutedText),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ===================== ACTIONS =====================
          Row(
            children: [
              // "Back" only makes sense when this screen was pushed on
              // top of another one (not when it is the Scan tab).
              if (Navigator.of(context).canPop()) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: OutlinedButton(
                  onPressed: _checking ? null : _checkConnection,
                  child: Text(_checking ? 'Checking…' : 'Check Connection'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _allConnected ? _startScanning : null,
              child: const Text('Start Scanning'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pillFor(HardwareState state) {
    switch (state) {
      case HardwareState.connected:
        return const StatusPill(label: 'Connected', tone: PillTone.success);
      case HardwareState.disconnected:
        return const StatusPill(label: 'Disconnected', tone: PillTone.danger);
      case HardwareState.checking:
        return const StatusPill(label: 'Checking...', tone: PillTone.warning);
    }
  }
}

class _InstructionStep extends StatelessWidget {
  final int number;
  final String text;
  const _InstructionStep(this.number, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: AppColors.successBg,
            child: Text(
              '$number',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
        ],
      ),
    );
  }
}
