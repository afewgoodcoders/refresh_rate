import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refresh_rate/refresh_rate.dart';
import 'package:refresh_rate/src/verification/fps_tracker.dart';
import 'package:refresh_rate/src/verification/frame_collector.dart';
import 'package:refresh_rate/src/verification/session_clock.dart';
import 'package:refresh_rate/src/verification/session_scorer.dart';
import 'refresh_rate_api_test.dart' show FakeHostApi;

FrameSample frame(int time, {double? target = 60}) => FrameSample(
    buildUs: 1000,
    rasterUs: 1000,
    totalUs: 2000,
    vsyncUs: time,
    timestamp: DateTime.utc(2026).add(Duration(microseconds: time)),
    targetHz: target);

class MissingHostApi extends FakeHostApi {
  @override
  Never getDisplayInfo() =>
      throw MissingPluginException('No native registration');
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    RefreshRate.setApiForTesting(FakeHostApi());
  });
  tearDown(RefreshRate.clearApiForTesting);

  test('cadence episodes recover, survive eviction, and stop at boundaries',
      () {
    final tracker = FpsTracker(historyLimit: 2);
    for (final us in [0, 16667, 116667, 156667, 173334]) {
      tracker.addSample(frame(us));
    }
    expect(tracker.stutters.episodeCount, 1);
    expect(tracker.stutters.longStallCount, 1);
    expect(tracker.stutters.episodes.single.badIntervals, 2);
    expect(tracker.stutters.episodes.single.recovered, true);
    expect(tracker.stutters.episodes.single.durationUs, 156667);
    tracker.addSample(frame(273334));
    tracker.breakSegment();
    tracker.addSample(frame(9000000));
    expect(tracker.stutters.episodes.last.recovered, false);
    expect(tracker.stutters.episodeCount, 2);
    expect(tracker.samples.length, 2);
  });
  test('intentional low-cadence work is not classified as a long stall', () {
    final tracker = FpsTracker();
    tracker.addSample(frame(0, target: 5));
    tracker.addSample(frame(200000, target: 5));
    expect(tracker.stutters.episodeCount, 0);
    expect(tracker.stutters.longStallCount, 0);
    var time = 200000;
    for (var i = 0; i < 250; i++) {
      time += 400000;
      tracker.addSample(frame(time, target: 5));
      time += 200000;
      tracker.addSample(frame(time, target: 5));
    }
    expect(tracker.stutters.episodeCount, 250);
    expect(tracker.stutters.longStallCount, 250);
    expect(tracker.stutters.episodes.length, 100);
    expect(tracker.stutters.droppedEpisodes, 150);
  });
  test('wall-clock jumps cannot change elapsed session duration', () {
    var wall = DateTime.utc(2026);
    var elapsed = Duration.zero;
    final clock = SessionClock(wallClock: () => wall, elapsed: () => elapsed);
    final start = clock.now();
    elapsed = const Duration(seconds: 2);
    wall = wall.subtract(const Duration(hours: 1));
    expect(clock.now().difference(start), const Duration(seconds: 2));
    expect(clock.discontinuity, true);
  });
  test('input proxy respects exclusions and readiness stays separate',
      () async {
    var now = DateTime.utc(2026);
    final session = RefreshRateSession.create('input', DisplayInfo.fallback,
        clock: () => now, expectedFps: 60, finalizationTimeout: Duration.zero);
    session.markInteraction('tap');
    session.addSamplesForTesting([frame(10000)]);
    now = now.add(const Duration(milliseconds: 20));
    session.markReady();
    session.markInteraction('unanswered');
    session.pause();
    now = now.add(const Duration(seconds: 1));
    session.resume();
    session.addSamplesForTesting([frame(1100000)]);
    now = now.add(const Duration(seconds: 1));
    final report = await session.end();
    final interactions = report.milestones['interactions'] as List;
    expect(interactions.first['nextFrameLatencyMs'], 10);
    expect(interactions.last['nextFrameLatencyMs'], isNull);
    expect(report.milestones['firstObservedFlutterFrameMs'], 10);
    expect(report.milestones['applicationReadyMs'], 20);
    expect(jsonDecode(report.toNdjson()), report.toMap());
  });
  test('privacy filtering covers nested tags and arbitrary sensitive text', () {
    final policy = TelemetryExportPolicy(
        allowedTags: {'route'},
        redact: (_, value) => value.contains('secret') ? null : value);
    final original = {
      'segments': [
        {
          'tags': {'route': 'feed', 'user': '123'}
        }
      ],
      'reproduction': 'secret-token'
    };
    final exported = jsonDecode(policy.encode(original));
    expect(exported['segments'][0]['tags'], {'route': 'feed'});
    expect(exported['reproduction'], isNull);
    expect(original['reproduction'], 'secret-token');
    expect(() => TelemetryExportPolicy(maxBytes: 256).encode({'x': 'a' * 300}),
        throwsStateError);
  });
  test('doctor and diagnostic bundle expose limitations and preserve unknowns',
      () async {
    final doctor = await RefreshRate.doctor();
    expect(
        doctor.findings.any((f) => f.code == 'presentationUnavailable'), true);
    final bundle = await RefreshRate.diagnosticBundle(
        environment: {'scenario': 'feed'},
        reproduction: 'secret',
        policy: TelemetryExportPolicy(
            redact: (_, value) => value == 'secret' ? null : value));
    final data = jsonDecode(bundle.toJson());
    expect(data['reproduction'], isNull);
    expect(data['configuration']['diagnostics']['presentedFps'], isNull);
    expect(data['environment']['scenario'], 'feed');
  });
  test('shadow mode records proposals without acquiring real preferences',
      () async {
    final changes = StreamController<DisplayInfo>.broadcast();
    final submitted = <RatePreference>[];
    final arbiter = RateController((p) async {
      submitted.add(p);
      return RateRequestResult(status: RequestStatus.submitted, preference: p);
    });
    final policy = RefreshRateAutoController(arbiter, changes.stream,
        shadowMode: true,
        initialInfo: DisplayInfo.fallback,
        idleDelay: const Duration(milliseconds: 100));
    final token = policy.beginActivity();
    expect(policy.history.last.preference.kind, PreferenceKind.high);
    expect(policy.history.last.shadowMode, true);
    expect(arbiter.effectiveLease, isNull);
    policy.endActivity(token);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(policy.history.last.preference.kind, PreferenceKind.system);
    expect(submitted, isEmpty);
    await policy.dispose();
    arbiter.dispose();
    await changes.close();
  });
  test('battery policy does not submit unsupported categories', () async {
    final changes = StreamController<DisplayInfo>.broadcast();
    final policy = RefreshRateAutoController(
        RefreshRate.controller, changes.stream,
        policy: RefreshRatePolicy.battery,
        capabilities: const RefreshRateCapabilities(),
        initialInfo: DisplayInfo.fallback);
    policy.beginActivity();
    expect(policy.history.last.reason, 'unsupportedPolicy');
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.system);
    await policy.dispose();
    await changes.close();
  });
  test('quality advice requires sustained work and sustained recovery',
      () async {
    final changes = StreamController<DisplayInfo>.broadcast();
    final received = <QualityRecommendation>[];
    final quality = RefreshRateQualityController(
        onRecommendation: received.add,
        changes: changes.stream,
        initialInfo: DisplayInfo.fallback,
        badFrames: 3,
        recoveryFrames: 5);
    quality.setWorkload(60);
    final epoch = DateTime.now().toUtc().microsecondsSinceEpoch + 1000;
    var vsync = 0;
    void deliver(int count, int cost) {
      PlatformDispatcher.instance.onReportTimings!(List.generate(count, (_) {
        vsync += 16667;
        return FrameTiming(
            vsyncStart: vsync,
            buildStart: vsync,
            buildFinish: vsync + cost,
            rasterStart: vsync + cost,
            rasterFinish: vsync + cost + 1000,
            rasterFinishWallTime: epoch + vsync + cost + 1000);
      }));
    }

    deliver(2, 20000);
    expect(received, isEmpty);
    deliver(1, 20000);
    expect(received.single.level, QualityLevel.reduced);
    deliver(4, 1000);
    expect(received.length, 1);
    deliver(1, 1000);
    expect(received.last.level, QualityLevel.normal);
    quality.setWorkload(null);
    expect(FrameCollector.instance.subscriberCount, 0);
    await quality.dispose();
    await changes.close();
  });
  test('rendering context is opt-in per subscriber', () {
    List<FrameSample>? plain, detailed;
    final stopPlain = FrameCollector.instance.subscribe((f) => plain = f);
    final stopDetailed = FrameCollector.instance
        .subscribe((f) => detailed = f, includeRenderingContext: true);
    PlatformDispatcher.instance.onReportTimings!([
      FrameTiming(
          vsyncStart: 1,
          buildStart: 1,
          buildFinish: 2,
          rasterStart: 2,
          rasterFinish: 3,
          rasterFinishWallTime: 1700000000000003,
          layerCacheCount: 7,
          layerCacheBytes: 400,
          pictureCacheCount: 3,
          pictureCacheBytes: 200)
    ]);
    expect(plain!.single.renderingContext, isNull);
    expect(detailed!.single.renderingContext!['layerCacheCount'], 7);
    stopPlain();
    stopDetailed();
    expect(FrameCollector.instance.subscriberCount, 0);
  });
  test(
      'repeated-run gates reject mismatched environments and observe regressions',
      () {
    SessionReport report(int rasterUs) {
      final tracker = FpsTracker();
      for (var i = 0; i < 120; i++) {
        tracker.addSample(FrameSample(
            buildUs: 1000,
            rasterUs: rasterUs,
            totalUs: 1000 + rasterUs,
            vsyncUs: i * 16667,
            timestamp:
                DateTime.utc(2026).add(Duration(microseconds: i * 16667)),
            targetHz: 60));
      }
      return SessionScorer.compute(
          sessionName: 'feed',
          tracker: tracker,
          targetHz: 60,
          validDuration: const Duration(seconds: 2),
          excludedDuration: Duration.zero,
          exclusionReasons: {},
          deviceState:
              const DeviceStateSnapshot(thermalState: ThermalState.nominal),
          expectedWorkloadFrameCount: 120,
          boundaryCoverageComplete: true,
          debugBuild: false);
    }

    final baseline = BenchmarkSeries(
        reports: [report(1000), report(2000), report(3000)],
        environmentKey: 'device-build');
    final current = BenchmarkSeries(
        reports: [report(2000), report(3000), report(4000)],
        environmentKey: 'device-build');
    final result = current.compareTo(baseline);
    expect(result.inconclusive, false);
    expect(result.passed, false);
    expect(result.regressionPercent, closeTo(50, 1));
    expect(
        current
            .compareTo(BenchmarkSeries(
                reports: baseline.reports, environmentKey: 'different-device'))
            .inconclusive,
        true);
    expect(
        BenchmarkSeries(reports: [report(1000)], environmentKey: 'device-build')
            .compareTo(baseline)
            .inconclusive,
        true);
  });
  testWidgets('completed report inspection does not collect or sustain frames',
      (tester) async {
    final report = SessionScorer.compute(
        sessionName: 'completed-session',
        tracker: FpsTracker(),
        targetHz: 60,
        validDuration: Duration.zero,
        excludedDuration: Duration.zero,
        exclusionReasons: {},
        deviceState:
            const DeviceStateSnapshot(thermalState: ThermalState.unknown));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: RefreshRateReportView(report: report))));
    await tester.pumpAndSettle();
    expect(find.text('completed-session'), findsOneWidget);
    expect(find.text('Physical presentation FPS: unavailable'), findsOneWidget);
    expect(FrameCollector.instance.subscriberCount, 0);
    expect(tester.binding.hasScheduledFrame, false);
  });
  test('doctor returns actionable evidence when native registration is missing',
      () async {
    RefreshRate.setApiForTesting(MissingHostApi());
    final report = await RefreshRate.doctor();
    expect(report.findings.single.code, 'queryFailed');
    expect(report.diagnostics.capabilities.query, false);
    expect(report.diagnostics.nativeReportedDisplayHz.value, isNull);
    expect(
        jsonDecode((await RefreshRate.diagnosticBundle()).toJson())[
            'configuration']['findings'][0]['code'],
        'queryFailed');
  });
}
