/// Where saved scan results live in Firebase Realtime Database.
///
/// Used by the history service (to save/load scans) and by the ESP32
/// status check (to ignore this node, so saving a scan is never
/// mistaken for live data from the hardware).
const String kHistoryNode = 'termiguard_history';
