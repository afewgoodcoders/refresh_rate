import 'package:web/web.dart' as web;

import 'frame_clock.dart' as native;

/// Flutter web's FrameTimingRecorder uses performance.now() for every phase,
/// including rasterFinishWallTime. Bridge that clock using its actual origin.
({DateTime timestamp, String source})? frameEventTime(
    int vsync, int finish, int wall) {
  if (wall != finish) return native.frameEventTime(vsync, finish, wall);
  final origin = web.window.performance.timeOrigin;
  if (!origin.isFinite ||
      origin <= 0 ||
      vsync < 0 ||
      finish <= 0 ||
      finish < vsync) {
    return null;
  }
  return (
    timestamp: DateTime.fromMicrosecondsSinceEpoch(
        (origin * 1000).round() + vsync,
        isUtc: true),
    source: 'performanceTimeOrigin'
  );
}
