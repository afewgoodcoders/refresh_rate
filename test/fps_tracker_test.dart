import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:refresh_rate/src/verification/fps_tracker.dart';
import 'package:refresh_rate/src/verification/session_scorer.dart';
import 'package:refresh_rate/refresh_rate.dart';

FrameSample sample(int vsync,
        {int build = 1000,
        int raster = 1000,
        int total = 2000,
        double? target = 60}) =>
    FrameSample(
        buildUs: build,
        rasterUs: raster,
        totalUs: total,
        vsyncUs: vsync,
        timestamp: DateTime.fromMicrosecondsSinceEpoch(1700000000000000 + vsync,
            isUtc: true),
        targetHz: target);

void main() {
  test('tail fraction rejects invalid inputs and handles missing samples', () {
    final histogram = TimingHistogram();
    for (final fraction in [0.0, -1.0, 1.01, double.nan, double.infinity]) {
      expect(() => histogram.lowFps(fraction), throwsArgumentError);
    }
    expect(histogram.lowFps(.01), isNull);
  });
  test('60 FPS cadence and 2ms latency never produce 500 low FPS', () {
    final tracker = FpsTracker();
    for (var i = 0; i < 201; i++) {
      tracker.addSample(sample(i * 16667));
    }
    expect(tracker.avgFps, closeTo(60, .01));
    expect(tracker.onePercentLowFps, closeTo(60, .01));
    expect(tracker.fivePercentLowFps, closeTo(60, .01));
    expect(tracker.pipeline.percentileMs(99), 2);
  });
  test('pipeline latency does not imply phase overruns', () {
    final tracker = FpsTracker();
    for (var i = 0; i < 121; i++) {
      tracker.addSample(sample(i * 8333,
          build: 6000, raster: 6000, total: 12000, target: 120));
    }
    expect(tracker.phaseOverruns, 0);
    expect(tracker.pipelineOverruns, 121);
    expect(tracker.cadenceGaps, 0);
    expect(tracker.jankyFrameCount(120), 0);
  });
  test('whole-session counts and early stalls survive rolling eviction', () {
    final tracker = FpsTracker();
    for (var i = 0; i < 1200; i++) {
      tracker.addSample(sample(i * 16667,
          build: i < 10 ? 50000 : 1000, total: i < 10 ? 51000 : 2000));
    }
    expect(tracker.sampleCount, 1200);
    expect(tracker.samples.length, 600);
    expect(tracker.buildOverruns, 10);
    expect(tracker.worstFrames.first.buildUs, 50000);
    expect(tracker.avgBuildMs, closeTo((10 * 50 + 1190) / 1200, .0001));
  });
  test('excluded and changed-target segments do not create gaps', () {
    final tracker = FpsTracker();
    tracker.addSample(sample(0));
    tracker.addSample(sample(16667));
    tracker.breakSegment();
    tracker.addSample(sample(10000000));
    tracker.addSample(sample(10016667));
    tracker.addSample(sample(10025000, target: 120));
    tracker.addSample(sample(10033333, target: 120));
    expect(tracker.intervals.count, 3);
    expect(tracker.cadenceGaps, 0);
  });
  test('low FPS is unavailable when tail has insufficient evidence', () {
    final tracker = FpsTracker();
    for (var i = 0; i < 10; i++) {
      tracker.addSample(sample(i * 16667));
    }
    expect(tracker.intervals.lowFps(.01), isNull);
    expect(tracker.pointOnePercentLowFps, isNull);
  });
  test('histograms are bounded and preserve known percentile populations', () {
    final histogram = TimingHistogram();
    for (var i = 0; i < 10000; i++) {
      histogram.add(i < 9500 ? 2000 : 40000);
    }
    expect(histogram.percentileMs(50), 2);
    expect(histogram.percentileMs(99), 40);
    expect(histogram.lowFps(.01), 25);
  });
  test('out of order timestamps are rejected', () {
    final tracker = FpsTracker();
    tracker.addSample(sample(200));
    tracker.addSample(sample(100));
    expect(tracker.sampleCount, 1);
    expect(tracker.invalidSampleCount, 1);
  });
  test('FrameTiming wall clock mapping uses phase offsets', () {
    final frame = FrameSample.fromTiming(FrameTiming(
        vsyncStart: 100,
        buildStart: 200,
        buildFinish: 300,
        rasterStart: 400,
        rasterFinish: 500,
        rasterFinishWallTime: 1700000000000500));
    expect(frame.timestamp.microsecondsSinceEpoch, 1700000000000100);
    expect(frame.hasEventTime, true);
  });
  test('unknown workload and environmental flags do not establish causality',
      () {
    final tracker = FpsTracker();
    for (var i = 0; i < 201; i++) {
      tracker.addSample(sample(i * 16667, target: null));
    }
    final report = SessionScorer.compute(
        sessionName: 'idle',
        tracker: tracker,
        targetHz: 0,
        validDuration: const Duration(seconds: 4),
        excludedDuration: Duration.zero,
        exclusionReasons: {},
        deviceState: const DeviceStateSnapshot(
            isLowPowerMode: true, thermalState: ThermalState.serious),
        boundaryCoverageComplete: true,
        debugBuild: false);
    expect(report.likelyBottleneck, Bottleneck.none);
    expect(report.verdict, Verdict.inconclusive);
    expect(report.observedAvgHz, isNull);
    expect(report.presentedFps, isNull);
    expect(report.phaseOverrunPercent, isNull);
    expect(
        report
            .evaluate(RefreshRateThresholds(maxPhaseOverrunPercent: 5))
            .inconclusive,
        true);
    expect(report.toJson(), contains('flutterFrameTiming'));
  });
  test('complete qualified workload supports named CI thresholds', () {
    final tracker = FpsTracker();
    for (var i = 0; i < 201; i++) {
      tracker.addSample(sample(i * 16667));
    }
    final report = SessionScorer.compute(
        sessionName: 'scroll',
        tracker: tracker,
        targetHz: 60,
        expectedWorkloadFrameCount: 201,
        validDuration: const Duration(seconds: 4),
        excludedDuration: Duration.zero,
        exclusionReasons: {},
        deviceState:
            const DeviceStateSnapshot(thermalState: ThermalState.nominal),
        boundaryCoverageComplete: true,
        debugBuild: false);
    expect(report.verdict, Verdict.excellent);
    expect(
        report
            .evaluate(
                RefreshRateThresholds(minAverageFps: 59, maxP99RasterMs: 5))
            .passed,
        true);
    expect(report.evaluate(RefreshRateThresholds(minAverageFps: 120)).passed,
        false);
  });
  test(
      'brief smooth rendering followed by idle cannot pass a continuous workload',
      () {
    final tracker = FpsTracker();
    for (var i = 0; i < 201; i++) {
      tracker.addSample(sample(i * 16667));
    }
    final report = SessionScorer.compute(
        sessionName: 'continuous',
        tracker: tracker,
        targetHz: 60,
        expectedWorkloadFrameCount: 60 * 3600,
        validDuration: const Duration(hours: 1),
        excludedDuration: Duration.zero,
        exclusionReasons: {},
        deviceState:
            const DeviceStateSnapshot(thermalState: ThermalState.nominal),
        boundaryCoverageComplete: true,
        debugBuild: false);
    expect(report.verdict, Verdict.poor);
    expect(report.evaluate(RefreshRateThresholds(minAverageFps: 59)).passed,
        false);
  });
}
