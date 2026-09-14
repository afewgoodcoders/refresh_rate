import 'package:flutter/material.dart';
import '../models/enums.dart';
import '../refresh_rate.dart';
import '../control/rate_controller.dart';
import 'fps_tracker.dart';

const _green = Color(0xFF76E88D);
const _amber = Color(0xFFFFC857);
const _red = Color(0xFFFF6270);
const _cyan = Color(0xFF64B5F6);
const _orange = Color(0xFFFFAB66);
const _violet = Color(0xFFD6A2FF);
const _muted = Color(0xFF9DA7B5);

Widget _panel(BuildContext context, Widget child, {bool full = false}) {
  final view = MediaQueryData.fromView(View.of(context));
  return Positioned(
    top: view.padding.top + 4,
    right: view.padding.right + 8,
    child: IgnorePointer(
      child: RepaintBoundary(
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            constraints: BoxConstraints(
                maxWidth: (view.size.width - view.padding.horizontal - 16)
                    .clamp(0.0, double.infinity)),
            padding: full
                ? const EdgeInsets.all(10)
                : const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: const Color(0xDD000000),
                borderRadius: BorderRadius.circular(6)),
            child: DefaultTextStyle(
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  height: 1.3,
                  fontFamily: 'monospace',
                  fontFeatures: [FontFeature.tabularFigures()]),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

String _rate(double? value) => value?.toStringAsFixed(1) ?? '—';

String _hz(double? value) {
  if (value == null) return '— Hz';
  return '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1)} Hz';
}

// This reference is only for the color indicator. Display metadata must never
// become an implicit workload target or phase budget.
double? _colorReference(BuildContext context, double? expectedFps) {
  if (expectedFps != null && expectedFps.isFinite && expectedFps > 0) {
    return expectedFps;
  }
  final info = RefreshRate.info;
  final native = info.isStale ? null : info.nativeReportedDisplayHz;
  final reported = native ?? View.of(context).display.refreshRate;
  return reported.isFinite && reported > 0 ? reported : null;
}

Color _fpsColor(double fps, double? reference) {
  if (reference == null) return _cyan;
  if (fps >= reference * .95) return _green;
  if (fps >= reference * .75) return _amber;
  return _red;
}

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
      {super.key, required this.tracker, this.stale = false, this.expectedFps});

  /// Accumulator supplying the displayed recent metrics.
  final FpsTracker tracker;

  /// Application-declared cadence used as the preferred color reference.
  final double? expectedFps;

  /// Whether recent cadence is idle or too old to display.
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final fps = tracker.recentFps();
    final available = !stale && tracker.sampleCount >= 2;
    final label = stale ? 'FPS idle' : '${available ? fps.round() : '—'} FPS';
    return _panel(
        context,
        Text(label,
            semanticsLabel: stale
                ? 'Flutter frame cadence: idle or stale'
                : 'Flutter frame cadence: ${available ? fps.round() : 'unknown'} FPS',
            style: TextStyle(
                color: stale
                    ? _amber
                    : available
                        ? _fpsColor(fps, _colorReference(context, expectedFps))
                        : _muted,
                fontSize: 13,
                fontWeight: FontWeight.bold)));
  }
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
    final web = info.displayServer == 'web';
    final hz =
        web ? info.nativeCallbackCadenceHz : info.nativeReportedDisplayHz;
    final stale = hz != null && info.isStale;
    final label =
        '${_hz(hz)}${web ? ' · callback' : ''}${stale ? ' · stale' : ''}';
    return _panel(
        context,
        Text(label,
            semanticsLabel:
                '${web ? 'Browser callback cadence' : 'OS-reported display rate'}: ${hz == null ? 'unknown' : label}',
            style: TextStyle(
                color: hz == null ? _muted : (stale ? _amber : _cyan),
                fontSize: 13,
                fontWeight: FontWeight.bold)));
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
  Widget build(BuildContext context) {
    final info = RefreshRate.info;
    final web = info.displayServer == 'web';
    final hz =
        web ? info.nativeCallbackCadenceHz : info.nativeReportedDisplayHz;
    final displayStale = hz != null && info.isStale;
    final available = !stale && tracker.sampleCount >= 2;
    final fps = tracker.recentFps();
    final budget = expectedFps == null ? null : 1000 / expectedFps!;
    final overruns = !available || tracker.budgetedFrameCount == 0
        ? null
        : 100 * tracker.phaseOverruns / tracker.budgetedFrameCount;
    final thermalColor = switch (info.thermalState) {
      ThermalState.nominal => _green,
      ThermalState.fair => _amber,
      ThermalState.serious || ThermalState.critical => _red,
      ThermalState.unknown => _muted,
    };
    Color phaseColor(double ms, Color normal) => !available
        ? _muted
        : budget != null && ms > budget
            ? _red
            : normal;

    return _panel(
      context,
      SizedBox(
        width: 224 * MediaQuery.textScalerOf(context).scale(11) / 11,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: _readout(
                    available ? '${fps.round()} FPS' : '— FPS',
                    stale ? 'IDLE / STALE' : 'FRAME CADENCE',
                    stale
                        ? _amber
                        : available
                            ? _fpsColor(
                                fps, _colorReference(context, expectedFps))
                            : _muted),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _readout(
                    _hz(hz),
                    '${web ? 'CALLBACK' : 'OS DISPLAY'}${displayStale ? ' · STALE' : ''}',
                    hz == null ? _muted : (displayStale ? _amber : _cyan),
                    right: true),
              ),
            ]),
            const _Rule(),
            _stat('BUILD', available ? '${_rate(tracker.avgBuildMs)} ms' : '—',
                phaseColor(tracker.avgBuildMs, _orange)),
            _stat(
                'RASTER',
                available ? '${_rate(tracker.avgRasterMs)} ms' : '—',
                phaseColor(tracker.avgRasterMs, _violet)),
            _stat(
                'P99 RASTER',
                available
                    ? '${_rate(tracker.raster.percentileMs(99))} ms'
                    : '—',
                phaseColor(tracker.raster.percentileMs(99) ?? 0, _violet)),
            const SizedBox(height: 5),
            _stat(
                'WORKLOAD',
                expectedFps == null ? 'unknown' : '${_rate(expectedFps)} FPS',
                expectedFps == null ? _muted : _amber),
            _stat(
                'BUDGET',
                budget == null ? 'unknown' : '${budget.toStringAsFixed(2)} ms',
                budget == null ? _muted : _amber),
            _stat(
                'PHASE OVERRUNS',
                overruns == null
                    ? 'unknown'
                    : '${overruns.toStringAsFixed(1)}%',
                overruns == null ? _muted : (overruns > 0 ? _red : _green)),
            _stat(
                'REQUEST', _preference(RefreshRate.requestedPreference), _cyan),
            _stat('THERMAL', info.thermalState.name, thermalColor),
            if (RefreshRate.isLowPowerMode)
              _stat('POWER', 'Low Power Mode', _amber),
            const _Rule(),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                    child: Text('PIPELINE LATENCY',
                        style: TextStyle(color: _cyan, fontSize: 9))),
                SizedBox(width: 8),
                Text('0–50 ms', style: TextStyle(color: _muted, fontSize: 9)),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
                width: double.infinity,
                height: 32,
                child: CustomPaint(
                    painter: _FrameGraph(
                        available ? tracker.samples : const [], budget))),
            const SizedBox(height: 6),
            const Text(
                'Flutter timings · observer on\nPresentation FPS unavailable',
                style: TextStyle(color: _muted, fontSize: 9)),
          ],
        ),
      ),
      full: true,
    );
  }
}

Widget _readout(String value, String label, Color color,
        {bool right = false}) =>
    Column(
      crossAxisAlignment:
          right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(value,
            style: TextStyle(
                color: color, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: _muted, fontSize: 9)),
      ],
    );

Widget _stat(String label, String value, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: _muted)),
      const SizedBox(width: 12),
      Expanded(
          child: Text(value,
              textAlign: TextAlign.right,
              style: TextStyle(color: color, fontWeight: FontWeight.w600))),
    ]));

class _Rule extends StatelessWidget {
  const _Rule();
  @override
  Widget build(BuildContext context) => const Padding(
      padding: EdgeInsets.symmetric(vertical: 7),
      child: SizedBox(
          height: 1,
          width: double.infinity,
          child: ColoredBox(color: Color(0xFF34404D))));
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
          Offset(0, y), Offset(size.width, y), Paint()..color = _amber);
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
          ..color = _cyan
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_FrameGraph oldDelegate) =>
      oldDelegate.frames != frames || oldDelegate.budgetMs != budgetMs;
}
