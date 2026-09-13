import 'dart:async';
import 'package:flutter/material.dart';
import 'package:refresh_rate/refresh_rate.dart';

/// One repeatable animation rendered identically under both preferences.
class BenchmarkWorkload extends StatefulWidget {
  const BenchmarkWorkload({super.key});
  @override
  State<BenchmarkWorkload> createState() => _BenchmarkWorkloadState();
}

class _BenchmarkWorkloadState extends State<BenchmarkWorkload>
    with SingleTickerProviderStateMixin {
  late final _animation =
      AnimationController(vsync: this, duration: const Duration(seconds: 2));
  double _expectedFps = 60;
  bool _running = false;
  String _status =
      'Choose the continuous workload budget, then run both cases.';
  SessionReport? _baseline, _requested;
  RefreshRateSession? _session;
  RefreshRateLease? _lease;

  Future<SessionReport> _run(RatePreference preference) async {
    final lease = RefreshRate.request(preference,
        owner: 'example-comparison', priority: 1000);
    _lease = lease;
    try {
      final outcome = await lease.ready;
      if (!mounted) throw StateError('Comparison closed');
      setState(() => _status =
          '${preference.kind.name}: ${outcome.status.name} (${outcome.backend})');
      _animation.value = 0;
      _animation.repeat();
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted) throw StateError('Comparison closed');
      final session = RefreshRate.startSession('controlled_animation',
          expectedFps: _expectedFps);
      _session = session;
      session.setTag('preference', preference.kind.name);
      await Future<void>.delayed(const Duration(seconds: 4));
      // Keep the workload running while the final timing batch arrives.
      final report = await session.end();
      _session = null;
      return report;
    } finally {
      if (mounted) _animation.stop();
      await lease.release();
      if (identical(_lease, lease)) _lease = null;
    }
  }

  Future<void> _compare() async {
    RefreshRate.hideOverlay();
    setState(() {
      _running = true;
      _baseline = _requested = null;
    });
    try {
      final baseline = await _run(const RatePreference.system());
      if (!mounted) return;
      final requested = await _run(const RatePreference.high());
      if (!mounted) return;
      final comparison = requested.compareTo(baseline,
          environmentKey: 'same-device-renderer-workload',
          baselineEnvironmentKey: 'same-device-renderer-workload');
      setState(() {
        _baseline = baseline;
        _requested = requested;
        _status = comparison.inconclusive
            ? 'Comparison inconclusive: inspect coverage and use a profile build.'
            : 'Comparable runs captured. Inspect cadence and phase costs below.';
      });
    } catch (error) {
      if (mounted) setState(() => _status = '$error');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  void dispose() {
    _session?.end();
    _lease?.release();
    _animation.dispose();
    super.dispose();
  }

  Widget _summary(String label, SessionReport? report) => report == null
      ? const SizedBox.shrink()
      : Text(
          '$label: ${report.flutterFrameCadenceFps?.toStringAsFixed(1) ?? "unknown"} Flutter FPS; '
          '${report.phaseOverrunPercent?.toStringAsFixed(1) ?? "unknown"}% phase overruns; '
          '${report.frameBudgetMs.toStringAsFixed(2)} ms budget; '
          'coverage ${report.boundaryCoverageComplete}; verdict ${report.verdict.name}');

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('System default vs requested high')),
        body: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              DropdownButton<double>(
                value: _expectedFps,
                items: [60.0, 90.0, 120.0]
                    .map((rate) => DropdownMenuItem(
                        value: rate,
                        child: Text(
                            '${rate.toInt()} FPS workload (${(1000 / rate).toStringAsFixed(2)} ms)')))
                    .toList(),
                onChanged: _running
                    ? null
                    : (rate) => setState(() => _expectedFps = rate!),
              ),
              FilledButton(
                  onPressed: _running ? null : _compare,
                  child: Text(
                      _running ? 'Running both cases…' : 'Run comparison')),
              const SizedBox(height: 12),
              Text(_status),
              const Text(
                  'Same animation and budget in both runs. A request is not a guarantee; unsupported controls are reported. Overlay is disabled during capture.'),
              Expanded(
                  child: RepaintBoundary(
                      child: AnimatedBuilder(
                          animation: _animation,
                          builder: (_, __) => CustomPaint(
                              size: const Size(300, 300),
                              painter: _WorkloadPainter(_animation.value))))),
              _summary('System default', _baseline),
              _summary('Requested high', _requested),
            ])),
      );
}

class _WorkloadPainter extends CustomPainter {
  _WorkloadPainter(this.position);
  final double position;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.cyan;
    for (var i = 0; i < 80; i++) {
      canvas.drawCircle(
          Offset((position * size.width + i * 37) % size.width,
              (i * 31.0) % size.height),
          6,
          paint);
    }
  }

  @override
  bool shouldRepaint(_WorkloadPainter old) => old.position != position;
}
