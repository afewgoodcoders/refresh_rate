import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../control/rate_controller.dart';
import '../models/session_report.dart';

/// Inspects an already completed session without collecting or scheduling frames.
/// Embed in a separate diagnostics route after the workload has finished.
class RefreshRateReportView extends StatelessWidget {
  /// Optional decisions are explicit snapshots from the application's arbiter.
  const RefreshRateReportView(
      {super.key, required this.report, this.decisions = const []});

  /// Completed, bounded session evidence.
  final SessionReport report;

  /// Related request decisions; their timing does not establish causality.
  final List<RefreshRateDecision> decisions;
  @override
  Widget build(BuildContext context) {
    String number(double? value) => value?.toStringAsFixed(2) ?? 'unavailable';
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(report.sessionName, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      Text(
          '${report.frameCount} Flutter frames · ${number(report.flutterFrameCadenceFps)} cadence FPS'),
      const Text('Physical presentation FPS: unavailable'),
      const SizedBox(height: 16),
      const Text('Recent frame costs (ms) · build / raster / pipeline'),
      const Text(
          'Blue: build · purple: raster · orange: pipeline · grey: workload budget'),
      SizedBox(height: 180, child: CustomPaint(painter: _FrameCosts(report))),
      SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              for (final name in ['Milliseconds', 'P50', 'P90', 'P95', 'P99'])
                DataColumn(label: Text(name))
            ],
            rows: [
              for (final phase in ['build', 'raster', 'pipeline', 'interval'])
                DataRow(cells: [
                  DataCell(Text(phase)),
                  for (final p in [50, 90, 95, 99])
                    DataCell(Text(number(report.percentilesMs['${phase}P$p'])))
                ])
            ],
          )),
      const SizedBox(height: 16),
      Text(
          'Stutter episodes: ${report.stutters['episodeCount'] ?? 'unavailable'}'),
      Text(
          'Longest interval: ${report.stutters['longestIntervalMs'] ?? 'unavailable'} ms'),
      Text(
          'Consecutive bad intervals: ${report.stutters['maxConsecutiveBadIntervals'] ?? 'unavailable'}'),
      const SizedBox(height: 16),
      for (final finding in report.findings) Text(finding),
      if (decisions.isNotEmpty) ...[
        const SizedBox(height: 16),
        const Text('Request history'),
        for (final decision
            in decisions.skip(math.max(0, decisions.length - 200)))
          ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                  '${decision.owner}: ${decision.result.preference.kind.name}'),
              subtitle: Text(
                  '${decision.timestamp.toIso8601String()} · ${decision.result.backend} · ${decision.result.status.name}')),
      ],
    ]);
  }
}

class _FrameCosts extends CustomPainter {
  _FrameCosts(this.report);
  final SessionReport report;
  @override
  void paint(Canvas canvas, Size size) {
    final frames = report.recentFrames;
    if (frames.length < 2) return;
    final ceiling = frames.fold<double>(
        1,
        (value, f) => math.max(
            value,
            math.max(f.totalUs / 1000,
                f.targetHz == null ? 0 : 1000 / f.targetHz!)));
    void line(Color color, double? Function(int) value) {
      final path = Path();
      var connected = false;
      for (var i = 0; i < frames.length; i++) {
        final amount = value(i);
        if (amount == null || !amount.isFinite) {
          connected = false;
          continue;
        }
        final x = i * size.width / (frames.length - 1);
        final y = size.height * (1 - amount / ceiling);
        if (!connected) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
        connected = true;
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.25);
    }

    line(Colors.grey,
        (i) => frames[i].targetHz == null ? null : 1000 / frames[i].targetHz!);
    line(Colors.orange, (i) => frames[i].totalUs / 1000);
    line(Colors.purple, (i) => frames[i].rasterUs / 1000);
    line(Colors.blue, (i) => frames[i].buildUs / 1000);
  }

  @override
  bool shouldRepaint(_FrameCosts oldDelegate) => oldDelegate.report != report;
}
