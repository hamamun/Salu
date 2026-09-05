/// Time formatting for the timeline labels, OSD deck and Resume toast.
library;

/// Formats a [Duration] as `hh:mm:ss` — zero-padded hours so every label
/// keeps the same width while the numbers tick (no wiggle).
String formatClock(Duration d) {
  final int h = d.inHours;
  final int m = d.inMinutes.remainder(60);
  final int s = d.inSeconds.remainder(60);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(h)}:${two(m)}:${two(s)}';
}

/// Compact clock for the Resume toast — `12:34`, `1:02:34`. No
/// zero-padded hours: nothing ticks inside the toast, so there is no
/// width wiggle to guard against.
String formatClockCompact(Duration d) {
  final int h = d.inHours;
  final int m = d.inMinutes.remainder(60);
  final int s = d.inSeconds.remainder(60);
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}
