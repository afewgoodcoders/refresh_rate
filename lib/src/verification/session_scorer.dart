import 'package:flutter/foundation.dart';
import '../models/enums.dart';
import '../models/session_report.dart';
import 'fps_tracker.dart';

/// Analyzes Flutter cadence and phase costs without inferring OS causality.
abstract class SessionScorer {
  /// Builds a source-qualified report from whole-session aggregates.
  static SessionReport compute({
    required String sessionName,
    required FpsTracker tracker,
    required double targetHz,
    required Duration validDuration,
    required Duration excludedDuration,
    required Map<ExclusionReason, int> exclusionReasons,
    required DeviceStateSnapshot deviceState,
    double? expectedWorkloadFrameCount,
    bool boundaryCoverageComplete = false,
    bool debugBuild = kDebugMode,
    List<Map<String, Object?>> segments = const [],
    List<Map<String, Object?>> markers = const [],
  }) {
    final targetKnown = targetHz.isFinite && targetHz > 0;
    final count = tracker.budgetedFrameCount;
    final phaseOverruns = tracker.phaseOverruns;
    final overrunPct = count > 0 ? phaseOverruns / count * 100 : 0.0;
    final findings = <String>[
      'Flutter timing records do not establish physical presentation FPS.',
      if (!boundaryCoverageComplete) 'Session boundary coverage is incomplete.',
      if (debugBuild)
        'Debug build: use profile/release for performance qualification.',
      if (!targetKnown) 'No expected workload cadence was provided.',
      if (tracker.intervals.count < 100) 'Insufficient intervals for a 1% low.',
      if (deviceState.isLowPowerMode == true)
        'Low Power Mode observed; causality is not established.',
      if (deviceState.thermalState == ThermalState.serious ||
          deviceState.thermalState == ThermalState.critical)
        'Elevated thermal pressure observed; causality is not established.',
      if (tracker.invalidSampleCount > 0)
        'Invalid or unordered timing records were rejected.',
    ];
    var verdict = Verdict.inconclusive;
    if (count >= 100 &&
        tracker.expectedIntervalCount >= 99 &&
        boundaryCoverageComplete &&
        !debugBuild) {
      final gapPct = tracker.cadenceGaps / tracker.expectedIntervalCount * 100;
      final missingPct = expectedWorkloadFrameCount != null &&
              expectedWorkloadFrameCount > 0
          ? (100 * (1 - count / expectedWorkloadFrameCount)).clamp(0.0, 100.0)
          : 100.0;
      final bad =
          [overrunPct, gapPct, missingPct].reduce((a, b) => a > b ? a : b);
      verdict = bad < 2
          ? Verdict.excellent
          : bad < 5
              ? Verdict.good
              : bad < 15
                  ? Verdict.fair
                  : Verdict.poor;
    }
    final bottleneck = tracker.buildOverruns > tracker.rasterOverruns &&
            tracker.buildOverruns > 0
        ? Bottleneck.buildBound
        : tracker.rasterOverruns > 0
            ? Bottleneck.rasterBound
            : Bottleneck.none;
    return SessionReport(
        sessionName: sessionName,
        verdict: verdict,
        likelyBottleneck: bottleneck,
        targetHz: targetKnown ? targetHz : 0,
        observedAvgHz: null,
        frameBudgetMs: targetKnown ? 1000 / targetHz : 0,
        avgFps: tracker.avgFps,
        onePercentLowFps: tracker.onePercentLowFps,
        fivePercentLowFps: tracker.fivePercentLowFps,
        avgBuildMs: tracker.avgBuildMs,
        avgRasterMs: tracker.avgRasterMs,
        avgTotalFrameMs: tracker.avgTotalMs,
        jankyFrameCount: phaseOverruns,
        severeJankCount: tracker.severePhaseOverruns,
        missedFramePercent: overrunPct,
        validDuration: validDuration,
        excludedDuration: excludedDuration,
        exclusionReasons: exclusionReasons,
        deviceState: deviceState,
        frameCount: tracker.sampleCount,
        expectedWorkloadFrameCount: expectedWorkloadFrameCount,
        intervalCount: tracker.intervals.count,
        budgetedFrameCount: count,
        buildOverrunCount: tracker.buildOverruns,
        rasterOverrunCount: tracker.rasterOverruns,
        pipelineOverrunCount: tracker.pipelineOverruns,
        cadenceGapCount: tracker.cadenceGaps,
        boundaryCoverageComplete: boundaryCoverageComplete,
        isDebugBuild: debugBuild,
        findings: List.unmodifiable(findings),
        percentilesMs: Map.unmodifiable({
          for (final entry in {
            'build': tracker.build,
            'raster': tracker.raster,
            'pipeline': tracker.pipeline,
            'interval': tracker.intervals
          }.entries)
            for (final p in [50, 90, 95, 99])
              '${entry.key}P$p': entry.value.percentileMs(p.toDouble()),
        }),
        worstFrames: tracker.worstFrames,
        segments: segments,
        markers: markers,
        pointOnePercentLowFps: tracker.pointOnePercentLowFps);
  }
}
