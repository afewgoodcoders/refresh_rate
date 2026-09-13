import 'dart:convert';
import 'enums.dart';
import '../verification/fps_tracker.dart';

/// A point-in-time snapshot of device conditions recorded at session start.
///
/// Captured when a [RefreshRateSession] is created and embedded in the
/// resulting [SessionReport] so analysis can account for the environment.
class DeviceStateSnapshot {
  /// Whether the device was in Low Power Mode when the session started.
  ///
  /// `null` when the platform does not expose this information.
  final bool? isLowPowerMode;

  /// The thermal state of the device when the session started.
  final ThermalState thermalState;

  /// Whether the display supports an adaptive (variable) refresh rate.
  ///
  /// `null` when the platform does not expose this information.
  final bool? hasAdaptiveRefreshRate;

  /// The display server in use (Linux only, e.g. `"wayland"`).
  ///
  /// `null` on non-Linux platforms.
  final String? displayServer;

  /// Number of connected monitors (desktop platforms only).
  ///
  /// `null` on mobile platforms.
  final int? monitorCount;

  /// Creates a new [DeviceStateSnapshot].
  const DeviceStateSnapshot({
    this.isLowPowerMode,
    required this.thermalState,
    this.hasAdaptiveRefreshRate,
    this.displayServer,
    this.monitorCount,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceStateSnapshot &&
          isLowPowerMode == other.isLowPowerMode &&
          thermalState == other.thermalState &&
          hasAdaptiveRefreshRate == other.hasAdaptiveRefreshRate &&
          displayServer == other.displayServer &&
          monitorCount == other.monitorCount;

  @override
  int get hashCode => Object.hash(isLowPowerMode, thermalState,
      hasAdaptiveRefreshRate, displayServer, monitorCount);

  /// Serializes this snapshot to a JSON-compatible map.
  Map<String, dynamic> toMap() => {
        'isLowPowerMode': isLowPowerMode,
        'thermalState': thermalState.name,
        'hasAdaptiveRefreshRate': hasAdaptiveRefreshRate,
        'displayServer': displayServer,
        'monitorCount': monitorCount,
      };
}

/// The result produced when a [RefreshRateSession] ends.
///
/// Contains FPS statistics, frame timing breakdowns, a performance [verdict],
/// a likely [likelyBottleneck] hint, and excluded-window details.
class SessionReport {
  /// The name given to the session when it was started.
  final String sessionName;

  /// Overall quality assessment for this session.
  final Verdict verdict;

  /// The rendering stage most likely responsible for any frame drops.
  final Bottleneck likelyBottleneck;

  /// The target refresh rate in Hz at the time the session began.
  final double targetHz;

  /// Qualified display observation; absent for Flutter timing-only sessions.
  final double? observedAvgHz;

  /// The frame duration budget at [targetHz] (1000 / targetHz), in ms.
  final double frameBudgetMs;

  /// Average frames per second across all valid frames.
  final double avgFps;

  /// The 1st-percentile FPS (worst 1% of frames).
  final double onePercentLowFps;

  /// The 5th-percentile FPS (worst 5% of frames).
  final double fivePercentLowFps;

  /// Average build (UI thread) time per frame, in ms.
  final double avgBuildMs;

  /// Average raster thread time per frame, in ms.
  final double avgRasterMs;

  /// Average pipeline latency (vsync start to raster finish), in ms.
  final double avgTotalFrameMs;

  /// Number of frames that exceeded the frame budget.
  final int jankyFrameCount;

  /// Number of frames that exceeded twice the frame budget.
  final int severeJankCount;

  /// Legacy alias for phase budget overruns; not physical missed frames.
  final double missedFramePercent;

  /// Total duration of valid (non-excluded) measurement time.
  final Duration validDuration;

  /// Total duration excluded from measurement (background, warmup, etc.).
  final Duration excludedDuration;

  /// A breakdown of how many times each [ExclusionReason] occurred.
  final Map<ExclusionReason, int> exclusionReasons;

  /// Device state recorded at the start of the session.
  final DeviceStateSnapshot deviceState;

  /// Total accepted records across the entire session.
  final int frameCount;

  /// Cadence episodes and bounded milestone evidence.
  final Map<String, Object?> stutters, milestones;

  /// Expected Flutter frames integrated over explicitly budgeted active segments.
  final double? expectedWorkloadFrameCount;

  /// Produced records divided by expected workload frames, not presentations.
  double? get workloadCoverage =>
      expectedWorkloadFrameCount != null && expectedWorkloadFrameCount! > 0
          ? budgetedFrameCount / expectedWorkloadFrameCount!
          : null;

  /// Valid adjacent-frame intervals within active segments.
  final int intervalCount;

  /// Records with an explicitly specified workload frame budget.
  final int budgetedFrameCount;

  /// UI phases exceeding their event-time workload budget.
  final int buildOverrunCount;

  /// Raster phases exceeding their event-time workload budget.
  final int rasterOverrunCount;

  /// Pipeline spans exceeding the workload budget; not presentation misses.
  final int pipelineOverrunCount;

  /// Intervals exceeding 1.5 times their expected workload interval.
  final int cadenceGapCount;

  /// Whether boundary witnesses and accepted timing records establish coverage.
  final bool boundaryCoverageComplete;

  /// Whether debug overhead prevents normal performance qualification.
  final bool isDebugBuild;

  /// Observed facts and measurement limitations without inferred causality.
  final List<String> findings;

  /// Named phase and interval percentiles in milliseconds; bucket width <= 1%.
  final Map<String, double?> percentilesMs;

  /// Bounded worst pipeline-latency records retained across the full session.
  final List<FrameSample> worstFrames;

  /// Bounded recent frame history for post-session inspection.
  final List<FrameSample> recentFrames;

  /// Timestamped workload, lifecycle, tag and device-state segments.
  final List<Map<String, Object?>> segments;

  /// Bounded user markers with UTC timestamps and active tags.
  final List<Map<String, Object?>> markers;

  /// Slowest 0.1% interval-tail cadence; null below 1000 intervals.
  final double? pointOnePercentLowFps;

  /// Cadence of valid Flutter records, excluding gaps across segments.
  double? get flutterFrameCadenceFps => intervalCount > 0 ? avgFps : null;

  /// Unavailable: Flutter timing records alone do not establish presentation FPS.
  double? get presentedFps => null;

  /// Percentage of budgeted records with an overrun in either phase.
  double? get phaseOverrunPercent => budgetedFrameCount > 0
      ? jankyFrameCount / budgetedFrameCount * 100
      : null;

  /// Creates a new [SessionReport].
  const SessionReport({
    required this.sessionName,
    required this.verdict,
    required this.likelyBottleneck,
    required this.targetHz,
    required this.observedAvgHz,
    required this.frameBudgetMs,
    required this.avgFps,
    required this.onePercentLowFps,
    required this.fivePercentLowFps,
    required this.avgBuildMs,
    required this.avgRasterMs,
    required this.avgTotalFrameMs,
    required this.jankyFrameCount,
    required this.severeJankCount,
    required this.missedFramePercent,
    required this.validDuration,
    required this.excludedDuration,
    required this.exclusionReasons,
    required this.deviceState,
    this.frameCount = 0,
    this.stutters = const {},
    this.milestones = const {},
    this.expectedWorkloadFrameCount,
    this.intervalCount = 0,
    this.budgetedFrameCount = 0,
    this.buildOverrunCount = 0,
    this.rasterOverrunCount = 0,
    this.pipelineOverrunCount = 0,
    this.cadenceGapCount = 0,
    this.boundaryCoverageComplete = false,
    this.isDebugBuild = false,
    this.findings = const [],
    this.percentilesMs = const {},
    this.worstFrames = const [],
    this.recentFrames = const [],
    this.segments = const [],
    this.markers = const [],
    this.pointOnePercentLowFps,
  });

  /// Serializes this report to a JSON-compatible map.
  Map<String, dynamic> toMap() => {
        'schemaVersion': 2,
        'source': 'flutterFrameTiming',
        'metricDefinitions': {
          'flutterFrameCadenceFps':
              'Valid adjacent interval count * 1000000 / interval microsecond sum; exclusions and target boundaries break adjacency.',
          'lowFps':
              'Reciprocal mean of the slowest interval tail. Minimum samples: 1%=100, 5%=20, 0.1%=1000. Partial histogram tails are approximate.',
          'phaseOverrunPercent':
              'Budgeted frames with build or raster phase over workload budget, divided by budgeted frame count * 100.',
          'pipelineLatencyMs':
              'Vsync start to raster finish; not physical presentation latency.',
          'percentilesMs':
              'Nearest-rank phase/interval quantiles from histograms with <=1% relative bucket width.',
        },
        'presentationCoverage': 'unavailable',
        'histogramRelativeBucketWidth': 0.01,
        'frameCount': frameCount,
        'stutters': stutters,
        'milestones': milestones,
        'expectedWorkloadFrameCount': expectedWorkloadFrameCount,
        'workloadCoverage': workloadCoverage,
        'intervalCount': intervalCount,
        'budgetedFrameCount': budgetedFrameCount,
        'boundaryCoverageComplete': boundaryCoverageComplete,
        'isDebugBuild': isDebugBuild,
        'flutterFrameCadenceFps': flutterFrameCadenceFps,
        'phaseOverrunPercent': phaseOverrunPercent,
        'buildOverrunCount': buildOverrunCount,
        'rasterOverrunCount': rasterOverrunCount,
        'pipelineOverrunCount': pipelineOverrunCount,
        'cadenceGapCount': cadenceGapCount,
        'pointOnePercentLowFps': pointOnePercentLowFps,
        'percentilesMs': percentilesMs,
        'findings': findings,
        'worstFrames': worstFrames.map((f) => f.toMap()).toList(),
        'recentFrames': recentFrames.map((f) => f.toMap()).toList(),
        'segments': segments,
        'markers': markers,
        'sessionName': sessionName,
        'verdict': verdict.name,
        'likelyBottleneck': likelyBottleneck.name,
        'targetHz': targetHz,
        'observedAvgHz': observedAvgHz,
        'frameBudgetMs': frameBudgetMs,
        'avgFps': avgFps,
        'onePercentLowFps': intervalCount >= 100 ? onePercentLowFps : null,
        'fivePercentLowFps': intervalCount >= 20 ? fivePercentLowFps : null,
        'avgBuildMs': avgBuildMs,
        'avgRasterMs': avgRasterMs,
        'avgTotalFrameMs': avgTotalFrameMs,
        'jankyFrameCount': jankyFrameCount,
        'severeJankCount': severeJankCount,
        'missedFramePercent': missedFramePercent,
        'validDurationMs': validDuration.inMilliseconds,
        'excludedDurationMs': excludedDuration.inMilliseconds,
        'exclusionReasons': exclusionReasons.map((k, v) => MapEntry(k.name, v)),
        'deviceState': deviceState.toMap(),
      };

  /// Serializes this report to a JSON string.
  String toJson() => jsonEncode(toMap());

  /// One complete versioned report per line for streaming ingestion.
  String toNdjson() => '${toJson()}\n';

  /// Serializes this report to a CSV string.
  String toCsv() {
    final m = toMap();
    String esc(dynamic v) {
      final s = v is Map || v is List ? jsonEncode(v) : '$v';
      if (s.contains(',') ||
          s.contains('"') ||
          s.contains('\n') ||
          s.contains('\r')) {
        return '"${s.replaceAll('"', '""')}"';
      }
      return s;
    }

    final headers = m.keys.join(',');
    final values = m.values.map(esc).join(',');
    return '$headers\n$values';
  }

  /// Compares compatible named workloads. Device/build identity must be supplied
  /// by the caller; absent identity makes the comparison explicitly inconclusive.
  BenchmarkComparison compareTo(
    SessionReport baseline, {
    required String? environmentKey,
    required String? baselineEnvironmentKey,
  }) {
    final missing = <String>[];
    if (environmentKey == null ||
        baselineEnvironmentKey == null ||
        environmentKey != baselineEnvironmentKey) {
      missing.add('benchmarkEnvironment');
    }
    if (sessionName != baseline.sessionName ||
        targetHz != baseline.targetHz ||
        targetHz <= 0) {
      missing.add('workload');
    }
    if (!boundaryCoverageComplete || !baseline.boundaryCoverageComplete) {
      missing.add('boundaryCoverage');
    }
    if (isDebugBuild || baseline.isDebugBuild) missing.add('debugBuild');
    if (frameCount < 100 || baseline.frameCount < 100) {
      missing.add('sampleCount');
    }
    if (workloadCoverage == null || baseline.workloadCoverage == null) {
      missing.add('workloadCoverage');
    }
    if (deviceState != baseline.deviceState) missing.add('deviceState');
    // Changing-target scenarios need a scenario-specific comparator.
    bool mixed(SessionReport report) => report.segments.any((segment) =>
        segment['state'] == 'running' &&
        segment['targetHz'] != report.targetHz);
    if (mixed(this) || mixed(baseline)) missing.add('changingTarget');
    return BenchmarkComparison(
        missingEvidence: List.unmodifiable(missing),
        averageFpsDelta: missing.isEmpty ? avgFps - baseline.avgFps : null,
        phaseOverrunPercentagePointDelta: missing.isEmpty &&
                phaseOverrunPercent != null &&
                baseline.phaseOverrunPercent != null
            ? phaseOverrunPercent! - baseline.phaseOverrunPercent!
            : null);
  }

  /// Human-readable, source-qualified report.
  String toMarkdown() =>
      '# ${sessionName.replaceAll(RegExp(r"[\r\n]"), " ")}\n\n'
      'Source: Flutter FrameTiming (presentation unavailable).\n\n'
      '| Metric | Value |\n|---|---|\n'
      '| Frames | $frameCount |\n'
      '| Flutter cadence FPS | ${flutterFrameCadenceFps?.toStringAsFixed(2) ?? "unavailable"} |\n'
      '| Phase overrun % | ${phaseOverrunPercent?.toStringAsFixed(2) ?? "unavailable"} |\n'
      '| Complete boundaries | $boundaryCoverageComplete |\n\n'
      '${findings.map((f) => "- $f").join("\n")}';

  /// Missing data is inconclusive, never a passing performance gate.
  ThresholdResult evaluate(RefreshRateThresholds thresholds) {
    final failures = <String>[];
    final missing = <String>[];
    if (frameCount < thresholds.minFrames) missing.add('insufficientFrames');
    if (thresholds.requireCompleteBoundaries && !boundaryCoverageComplete) {
      missing.add('incompleteBoundaries');
    }
    if (isDebugBuild && !thresholds.allowDebugBuild) missing.add('debugBuild');
    void minimum(String name, double? actual, double? limit) {
      if (limit == null) return;
      if (actual == null) {
        missing.add(name);
      } else if (actual < limit) {
        failures.add('$name: $actual < $limit');
      }
    }

    void maximum(String name, double? actual, double? limit) {
      if (limit == null) return;
      if (actual == null) {
        missing.add(name);
      } else if (actual > limit) {
        failures.add('$name: $actual > $limit');
      }
    }

    minimum(
        'workloadCoverage', workloadCoverage, thresholds.minWorkloadCoverage);
    minimum('averageFps', flutterFrameCadenceFps, thresholds.minAverageFps);
    minimum('onePercentLowFps', intervalCount >= 100 ? onePercentLowFps : null,
        thresholds.minOnePercentLowFps);
    maximum('phaseOverrunPercent', phaseOverrunPercent,
        thresholds.maxPhaseOverrunPercent);
    maximum(
        'p99RasterMs', percentilesMs['rasterP99'], thresholds.maxP99RasterMs);
    return ThresholdResult(
        List.unmodifiable(failures), List.unmodifiable(missing));
  }
}

/// Thresholds are expressed in FPS, milliseconds and percentages as named.
class RefreshRateThresholds {
  /// Minimum accepted Flutter frame cadence in FPS.
  final double? minAverageFps;

  /// Minimum accepted slowest 1% interval-tail cadence.
  final double? minOnePercentLowFps;

  /// Maximum accepted UI/raster overrun percentage (0–100).
  final double? maxPhaseOverrunPercent;

  /// Maximum accepted raster p99 in milliseconds.
  final double? maxP99RasterMs;

  /// Minimum produced/expected workload frame ratio for continuous scenarios.
  final double minWorkloadCoverage;

  /// Minimum records required before the gate can pass.
  final int minFrames;

  /// Requires complete session boundary evidence before passing.
  final bool requireCompleteBoundaries;

  /// Explicitly permits debug measurements for non-production checks.
  final bool allowDebugBuild;

  /// Creates a [RefreshRateThresholds] with the supplied configuration.
  RefreshRateThresholds(
      {this.minAverageFps,
      this.minOnePercentLowFps,
      this.maxPhaseOverrunPercent,
      this.maxP99RasterMs,
      this.minFrames = 100,
      this.minWorkloadCoverage = 0.9,
      this.requireCompleteBoundaries = true,
      this.allowDebugBuild = false}) {
    for (final value in [
      minAverageFps,
      minOnePercentLowFps,
      maxPhaseOverrunPercent,
      maxP99RasterMs
    ]) {
      if (value != null && (!value.isFinite || value < 0)) {
        throw ArgumentError('Invalid threshold');
      }
    }
    if (!minWorkloadCoverage.isFinite ||
        minWorkloadCoverage < 0 ||
        minWorkloadCoverage > 1) {
      throw ArgumentError('Invalid coverage');
    }
    if (minFrames < 2 || (maxPhaseOverrunPercent ?? 0) > 100) {
      throw ArgumentError('Invalid threshold');
    }
  }
}

/// Failures and missing evidence remain distinguishable for CI.
class ThresholdResult {
  /// Unavailable or insufficient evidence that makes the result inconclusive.
  final List<String> failures, missingEvidence;

  /// Creates a [ThresholdResult] with the supplied configuration.
  const ThresholdResult(this.failures, this.missingEvidence);

  /// True only when every requested check has evidence and passes.
  bool get passed => failures.isEmpty && missingEvidence.isEmpty;

  /// Whether required evidence is missing.
  bool get inconclusive => missingEvidence.isNotEmpty;
}

/// Deltas are available only for explicitly compatible benchmark environments.
class BenchmarkComparison {
  /// Creates a comparison with named missing evidence or comparable deltas.
  const BenchmarkComparison(
      {required this.missingEvidence,
      this.averageFpsDelta,
      this.phaseOverrunPercentagePointDelta});

  /// Compatibility requirements that were not established.
  final List<String> missingEvidence;

  /// Current cadence minus baseline cadence, in FPS.
  final double? averageFpsDelta;

  /// Current minus baseline phase overruns, in percentage points.
  final double? phaseOverrunPercentagePointDelta;

  /// Whether comparison would rely on missing or incompatible evidence.
  bool get inconclusive => missingEvidence.isNotEmpty;
}
