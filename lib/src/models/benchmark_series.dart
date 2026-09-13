import 'session_report.dart';

/// Descriptive repeated-run comparison; not a statistical significance claim.
class BenchmarkSeriesComparison {
  /// Stores compatibility failures and distribution evidence.
  BenchmarkSeriesComparison(
      {required List<String> missingEvidence,
      required this.baseline,
      required this.current,
      required this.regressionPercent,
      required this.maxRegressionPercent})
      : missingEvidence = List.unmodifiable(missingEvidence);

  /// A gate cannot pass when coverage or workload identity is missing.
  final List<String> missingEvidence;

  /// Per-run distributions for the selected metric.
  final Map<String, double>? baseline, current;

  /// Median relative regression; positive means worse for the selected metric.
  final double? regressionPercent;

  /// Caller-selected allowed regression percentage.
  final double maxRegressionPercent;

  /// True only when all compared runs are qualified and the threshold holds.
  bool get passed =>
      missingEvidence.isEmpty &&
      regressionPercent != null &&
      regressionPercent! <= maxRegressionPercent;

  /// Missing evidence stays distinct from an observed regression.
  bool get inconclusive => missingEvidence.isNotEmpty;
}

/// Named distribution metrics with explicit direction of improvement.
enum BenchmarkMetric {
  /// Higher Flutter frame cadence is better for the same continuous workload.
  flutterCadence,

  /// Lower frame raster P99 is better.
  rasterP99,

  /// Lower fraction of phase-budget overruns is better.
  phaseOverrunPercent,
}

/// A bounded set of repeated executions in one caller-identified environment.
class BenchmarkSeries {
  /// Environment must identify device/build/renderer/scenario consistently.
  BenchmarkSeries(
      {required Iterable<SessionReport> reports,
      required this.environmentKey}) {
    final retained = <SessionReport>[];
    for (final report in reports) {
      if (retained.length == 100) {
        throw ArgumentError('At most 100 benchmark runs');
      }
      retained.add(report);
    }
    this.reports = List.unmodifiable(retained);
  }

  /// Independent workload executions, not individual frame samples.
  late final List<SessionReport> reports;

  /// Stable, application-supplied compatibility identity.
  final String environmentKey;

  /// Compares medians and exposes P50/P90/P95/P99 plus extrema over runs.
  /// At least three qualified runs in each series are required by default.
  BenchmarkSeriesComparison compareTo(BenchmarkSeries baseline,
      {BenchmarkMetric metric = BenchmarkMetric.rasterP99,
      double maxRegressionPercent = 5,
      int minRuns = 3}) {
    if (minRuns < 3 ||
        !maxRegressionPercent.isFinite ||
        maxRegressionPercent < 0) {
      throw ArgumentError('Invalid repeated-run gate');
    }
    final missing = <String>{};
    if (reports.length < minRuns || baseline.reports.length < minRuns) {
      missing.add('runCount');
    }
    if (environmentKey.isEmpty || environmentKey != baseline.environmentKey) {
      missing.add('environment');
    }
    final reference = baseline.reports.isEmpty ? null : baseline.reports.first;
    final a = <double>[], b = <double>[];
    for (final pair in [(reports, a), (baseline.reports, b)]) {
      for (final report in pair.$1) {
        final gate = report.evaluate(RefreshRateThresholds());
        if (gate.inconclusive || gate.failures.isNotEmpty) {
          missing.add('coverage');
        }
        if (reference != null &&
            report
                .compareTo(reference,
                    environmentKey: environmentKey,
                    baselineEnvironmentKey: baseline.environmentKey)
                .inconclusive) {
          missing.add('workloadCompatibility');
        }
        final value = switch (metric) {
          BenchmarkMetric.flutterCadence => report.flutterFrameCadenceFps,
          BenchmarkMetric.rasterP99 => report.percentilesMs['rasterP99'],
          BenchmarkMetric.phaseOverrunPercent => report.phaseOverrunPercent,
        };
        if (value == null || !value.isFinite) {
          missing.add('metric');
        } else {
          pair.$2.add(value);
        }
      }
    }
    Map<String, double> distribution(List<double> values) {
      values.sort();
      double percentile(double p) =>
          values[((p * values.length).ceil() - 1).clamp(0, values.length - 1)];
      final middle = values.length ~/ 2;
      final median = values.length.isOdd
          ? values[middle]
          : (values[middle - 1] + values[middle]) / 2;
      return {
        'min': values.first,
        'p50': median,
        'p90': percentile(.9),
        'p95': percentile(.95),
        'p99': percentile(.99),
        'max': values.last
      };
    }

    final currentDistribution = a.isEmpty ? null : distribution(a);
    final baselineDistribution = b.isEmpty ? null : distribution(b);
    double? delta;
    if (missing.isEmpty) {
      final before = baselineDistribution!['p50']!,
          after = currentDistribution!['p50']!;
      if (before == 0 && after != 0) {
        missing.add('zeroBaselineUseAbsoluteThreshold');
      } else {
        delta = before == 0
            ? 0
            : (after - before) /
                before *
                100 *
                (metric == BenchmarkMetric.flutterCadence ? -1 : 1);
      }
    }
    return BenchmarkSeriesComparison(
        missingEvidence: missing.toList(),
        baseline: baselineDistribution,
        current: currentDistribution,
        regressionPercent: delta,
        maxRegressionPercent: maxRegressionPercent);
  }
}
