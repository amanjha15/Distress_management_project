/// Converts a backend UTC ISO-8601 timestamp (e.g.
/// "2026-09-17T17:10:11.058733+00:00") into a local HH:MM:SS string for
/// display. The live-detection feed's timestamps come from the backend as
/// UTC; without converting to the viewer's local timezone before display,
/// the shown time is off by the viewer's UTC offset. Falls back to the raw
/// input if it isn't parseable.
String formatLocalTime(String isoUtc) {
  final parsed = DateTime.tryParse(isoUtc);
  if (parsed == null) return isoUtc;
  final local = parsed.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
