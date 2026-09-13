import 'package:flutter/material.dart';
import '../refresh_rate.dart';
import '../control/rate_controller.dart';
import 'fps_tracker.dart';

Widget _panel(BuildContext context, Widget child) => Positioned(
    top: MediaQueryData.fromView(View.of(context)).padding.top + 4,
    right: 8,
    child: IgnorePointer(
        child: RepaintBoundary(
            child: Material(
                color: Colors.transparent,
                child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: const Color(0xDD000000),
                        borderRadius: BorderRadius.circular(6)),
                    child: DefaultTextStyle(
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontFeatures: [FontFeature.tabularFigures()]),
                        child: child))))));
String _rate(double? value) => value?.toStringAsFixed(1) ?? 'unknown';

String _preference(RatePreference preference) => switch (preference.kind) {
      PreferenceKind.content =>
        'content ${preference.fps!.toStringAsFixed(3)} FPS',
      PreferenceKind.atLeast => 'at least ${_rate(preference.fps)} FPS',
      PreferenceKind.category =>
        'category ${['none', 'low', 'normal', 'high'][preference.category!]}',
      _ => preference.kind.name,
    };

/// Event-driven Flutter cadence badge.
class FpsOverlayWidget extends StatelessWidget {
  /// Creates a [FpsOverlayWidget] with the supplied configuration.
  const FpsOverlayWidget(
      {super.key, required this.tracker, this.stale = false});

  /// Accumulator supplying the displayed recent metrics.
  final FpsTracker tracker;

  /// Whether recent cadence is idle or too old to display.
  final bool stale;
  @override
  Widget build(BuildContext context) => _panel(
      context,
      Text(stale
          ? 'Flutter FPS: idle / stale'
          : 'Flutter ${tracker.recentFps().toStringAsFixed(0)} FPS'));
}

/// Native display information badge that does not collect Flutter frames.
class HzOverlayWidget extends StatelessWidget {
  /// Creates a [HzOverlayWidget] with the supplied configuration.
  const HzOverlayWidget({super.key, required this.tracker});

  /// Accumulator supplying the displayed recent metrics.
  final FpsTracker tracker;
  @override
  Widget build(BuildContext context) {
    final info = RefreshRate.info;
    return _panel(
        context,
        Text(info.displayServer == 'web'
            ? 'Browser callback ${_rate(info.nativeCallbackCadenceHz)} Hz'
            : 'OS display ${_rate(info.nativeReportedDisplayHz)} Hz${info.isStale ? " (stale)" : ""}'));
  }
}

/// Diagnostic overlay showing separately named measurements.
class FullOverlayWidget extends StatelessWidget {
  /// Creates a [FullOverlayWidget] with the supplied configuration.
  const FullOverlayWidget(
      {super.key, required this.tracker, this.stale = false, this.expectedFps});

  /// Application-declared workload cadence; absent means unknown budget.
  final double? expectedFps;

  /// Accumulator supplying the displayed recent metrics.
  final FpsTracker tracker;

  /// Whether recent cadence is idle or too old to display.
  final bool stale;
  @override
  Widget build(BuildContext context) => _panel(
      context,
      Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(stale
                ? 'Flutter: idle / stale'
                : 'Flutter ${tracker.recentFps().toStringAsFixed(0)} FPS'),
            Text('Requested: ${_preference(RefreshRate.requestedPreference)}'),
            Text(expectedFps == null
                ? 'Workload: unknown · budget: unknown'
                : 'Workload: ${_rate(expectedFps)} FPS · budget: ${(1000 / expectedFps!).toStringAsFixed(2)} ms'),
            Text(tracker.budgetedFrameCount == 0 || stale
                ? 'Phase overruns: unknown'
                : 'Phase overruns: ${(100 * tracker.phaseOverruns / tracker.budgetedFrameCount).toStringAsFixed(1)}%'),
            Text(
                'OS display: ${_rate(RefreshRate.info.nativeReportedDisplayHz)} Hz'),
            Text(
                'build ${tracker.avgBuildMs.toStringAsFixed(1)}ms  raster ${tracker.avgRasterMs.toStringAsFixed(1)}ms'),
            Text('p99 raster ${_rate(tracker.raster.percentileMs(99))}ms'),
            Text('thermal: ${RefreshRate.thermalState.name}'),
            if (RefreshRate.isLowPowerMode) const Text('Low Power Mode'),
            SizedBox(
                width: 160,
                height: 32,
                child: CustomPaint(
                    painter: _FrameGraph(tracker.samples,
                        expectedFps == null ? null : 1000 / expectedFps!))),
            const Text('Observer enabled · presentation unavailable',
                style: TextStyle(fontSize: 9)),
          ]));
}

class _FrameGraph extends CustomPainter {
  _FrameGraph(this.frames, this.budgetMs);
  final double? budgetMs;
  final List<FrameSample> frames;
  @override
  void paint(Canvas canvas, Size size) {
    if (frames.length < 2) return;
    if (budgetMs != null) {
      final y = size.height * (1 - (budgetMs! / 50).clamp(0, 1));
      canvas.drawLine(
          Offset(0, y), Offset(size.width, y), Paint()..color = Colors.amber);
    }
    final path = Path();
    final start = frames.length > 120 ? frames.length - 120 : 0;
    for (var i = start; i < frames.length; i++) {
      final x = (i - start) / (frames.length - start - 1) * size.width;
      final y = size.height * (1 - (frames[i].totalUs / 50000).clamp(0, 1));
      if (i == start) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = Colors.lightBlueAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_FrameGraph oldDelegate) =>
      oldDelegate.frames != frames || oldDelegate.budgetMs != budgetMs;
}
