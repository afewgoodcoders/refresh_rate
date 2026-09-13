/// Maps native FrameTiming phases through the raster-finish wall clock.
({DateTime timestamp, String source})? frameEventTime(
    int vsync, int finish, int wall) {
  if (wall <= 0 || finish < vsync) return null;
  return (
    timestamp: DateTime.fromMicrosecondsSinceEpoch(wall - (finish - vsync),
        isUtc: true),
    source: 'rasterFinishWallTime'
  );
}
