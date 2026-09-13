import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:refresh_rate/refresh_rate.dart';

// These checks use the registered plugin and real engine callbacks. They do
// not assert physical refresh rates or benchmark performance in debug builds.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> waitFor(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!condition() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(condition(), isTrue, reason: 'Condition did not become true in 10s');
  }

  void checkSubmission(RateRequestResult result, bool supported) {
    expect(result.status,
        supported ? RequestStatus.submitted : RequestStatus.unsupported);
    expect(result.fulfilmentObserved, isFalse);
    if (supported) {
      expect(result.backend, isNot('unavailable'));
      expect(result.scope, isNot('unknown'));
    }
  }

  tearDown(() async {
    RefreshRate.hideOverlay();
    await RefreshRate.preferDefault();
  });

  testWidgets('registered plugin reports qualified display information',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Workload()));
    final info = await RefreshRate.refresh();
    expect(info.observedAt, isNotNull);
    expect(info.supportedRates.every((hz) => hz.isFinite && hz > 0), isTrue);
    final diagnostics = await RefreshRate.diagnostics(view: tester.view);
    expect(diagnostics.presentedFps, isNull);
    expect(diagnostics.capabilities.presentationObservation, isFalse);
    expect(diagnostics.engineReportedDisplayHz.source, 'flutterDisplay');
    if (kIsWeb) {
      expect(info.nativeReportedDisplayHz, isNull);
      expect(info.displayModeMaxHz, isNull);
      expect(info.nativeCallbackCadenceHz, greaterThan(0));
    } else {
      expect(info.nativeReportedDisplayHz ?? info.displayModeMaxHz,
          greaterThan(0));
    }
    final caps = diagnostics.capabilities;
    checkSubmission(await RefreshRate.preferMax(),
        caps.surfaceVoting || caps.windowPreferences || caps.engineControl);
    checkSubmission(
        await RefreshRate.category(RateCategory.normal), caps.categoryHints);
    checkSubmission(await RefreshRate.preferAtLeast(60), caps.atLeast);
    debugPrint('E2E display: $info');
  });

  testWidgets('overlapping native requests preserve content and restore owners',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Workload()));
    final caps = await RefreshRate.capabilities();
    final content = RefreshRateContentController();
    addTearDown(content.dispose);
    await RefreshRate.preferMax();
    checkSubmission(
        await content.update(sourceFps: 24000 / 1001), caps.contentMatching);
    final boost = RefreshRate.request(const RatePreference.high(),
        owner: 'integration-boost',
        priority: 200,
        duration: const Duration(milliseconds: 200));
    addTearDown(boost.release);
    await boost.ready;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(RefreshRate.requestedPreference.fps, closeTo(24000 / 1001, 0.0001));
    await RefreshRate.preferDefault();
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.content);
    checkSubmission(
        await content.update(sourceFps: 30000 / 1001), caps.contentMatching);
    checkSubmission(
        await content.update(sourceFps: 30000 / 1001), caps.contentMatching);
    await content.update(sourceFps: 30000 / 1001, buffering: true);
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.system);
  });

  testWidgets('route visibility and scroll lifetime release their requests',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        home: const RefreshRateScope(
            preference: RatePreference.high(), child: _Workload())));
    await waitFor(
        () => RefreshRate.requestedPreference.kind == PreferenceKind.high);
    unawaited(navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Second route')))));
    await waitFor(
        () => RefreshRate.requestedPreference.kind == PreferenceKind.system);
    navigator.currentState!.pop();
    await waitFor(
        () => RefreshRate.requestedPreference.kind == PreferenceKind.high);
    await tester.pumpWidget(const SizedBox());
    await waitFor(
        () => RefreshRate.requestedPreference.kind == PreferenceKind.system);

    final policyCaps = await RefreshRate.capabilities();
    final policy =
        RefreshRate.auto(idleDelay: const Duration(milliseconds: 200));
    addTearDown(policy.dispose);
    await tester.pumpWidget(MaterialApp(
        home: RefreshRateInteraction(
            controller: policy,
            child: Scaffold(
                body: ListView.builder(
                    itemExtent: 72,
                    itemCount: 100,
                    itemBuilder: (_, i) => Text('Row $i'))))));
    await tester.fling(find.byType(ListView), const Offset(0, -300), 1500);
    expect(
        RefreshRate.requestedPreference.kind,
        policyCaps.surfaceVoting ||
                policyCaps.windowPreferences ||
                policyCaps.engineControl
            ? PreferenceKind.high
            : PreferenceKind.system);
    await waitFor(
        () => RefreshRate.requestedPreference.kind == PreferenceKind.system);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('real frames reach sessions, exports and removable overlays',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Workload()));
    final delivered = <FrameSample>[];
    final telemetry = FrameTelemetry(
        sampleEvery: 1,
        flushInterval: const Duration(milliseconds: 100),
        sink: (frames) async => delivered.addAll(frames));
    addTearDown(telemetry.dispose);
    final session =
        RefreshRate.startSession('integration-animation', expectedFps: 60);
    addTearDown(session.end);
    session.setTag('screen', 'integration');
    session.mark('animation-started');
    session.markInteraction('animation-input');
    session.markReady();
    // Real animations keep the engine producing frames while callbacks arrive.
    await waitFor(() => delivered.length >= 20);
    session.pause();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    session.resume();
    for (final show in [
      RefreshRate.showFPS,
      RefreshRate.showHz,
      RefreshRate.showOverlay
    ]) {
      show();
      await waitFor(() => RefreshRate.isOverlayVisible);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    RefreshRate.hideOverlay();
    expect(RefreshRate.isOverlayVisible, isFalse);
    final report = await session.end();
    expect(report.frameCount, greaterThan(0));
    expect(report.intervalCount, greaterThan(0));
    expect(report.flutterFrameCadenceFps, greaterThan(0));
    expect(report.worstFrames.every((f) => f.hasEventTime), isTrue);
    expect(report.worstFrames.first.timestampSource,
        kIsWeb ? 'performanceTimeOrigin' : 'rasterFinishWallTime');
    expect(report.presentedFps, isNull);
    expect(report.observedAvgHz, isNull);
    expect(report.verdict, Verdict.inconclusive);
    expect(report.excludedDuration.inMilliseconds, greaterThanOrEqualTo(200));
    expect(report.worstFrames.any((f) => f.tags['screen'] == 'integration'),
        isTrue);
    expect((jsonDecode(report.toJson()) as Map)['schemaVersion'], 2);
    expect(report.toCsv(), contains('flutterFrameCadenceFps'));
    expect(report.milestones['firstObservedFlutterFrameAt'], isNotNull);
    expect(report.milestones['applicationReadyAt'], isNotNull);
    expect(
        (report.milestones['interactions'] as List).first['nextFrameLatencyMs'],
        isNotNull);
    expect(report.stutters['episodeCount'], isA<int>());
    final bundle = await RefreshRate.diagnosticBundle(
        session: report,
        environment: {'scenario': 'integration'},
        policy: TelemetryExportPolicy(allowedTags: {'screen'}));
    expect(jsonDecode(bundle.toJson())['session']['frameCount'],
        report.frameCount);
    expect(report.toMarkdown(), contains('presentation unavailable'));
    expect(report.evaluate(RefreshRateThresholds()).inconclusive, isTrue);
    await telemetry.dispose();
    final stoppedCount = delivered.length;
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(delivered.length, stoppedCount);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['session'] = report.toMap();
    debugPrint('E2E timing: ${report.frameCount} frames, '
        '${report.intervalCount} intervals, '
        'complete boundaries: ${report.boundaryCoverageComplete}');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('native performance capabilities and independent ownership',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Workload()));
    final caps = await RefreshRate.capabilities();
    final first = await RefreshRate.thermalHeadroom();
    final second = await RefreshRate.thermalHeadroom();
    if (caps.thermalHeadroom) {
      expect(second.cached, isTrue);
      expect(second.observedAt, first.observedAt);
    } else {
      expect(first.value, isNull);
      expect(first.unavailableReason, isNotNull);
    }
    final one = RefreshRate.sustainedPerformance(previousEnabled: false);
    final two = RefreshRate.sustainedPerformance(previousEnabled: false);
    addTearDown(one.release);
    addTearDown(two.release);
    expect(
        (await one.ready).status,
        caps.sustainedPerformance
            ? RequestStatus.submitted
            : RequestStatus.unsupported);
    expect(
        (await two.ready).status,
        caps.sustainedPerformance
            ? RequestStatus.submitted
            : RequestStatus.unsupported);
    await one.release();
    if (caps.sustainedPerformance) {
      final data = await RefreshRate.diagnostics();
      expect(data.nativeMetadata['ownedSustainedRequests'], 1);
    }
    await two.release();
    if (caps.touchBoost) {
      final before =
          (await RefreshRate.diagnostics()).nativeMetadata['touchBoostEnabled'];
      await RefreshRate.setTouchBoost(false);
      expect(
          (await RefreshRate.diagnostics()).nativeMetadata['touchBoostEnabled'],
          false);
      await RefreshRate.resetTouchBoost();
      expect(
          (await RefreshRate.diagnostics()).nativeMetadata['touchBoostEnabled'],
          before);
    }
    final shadow = RefreshRate.auto(shadowMode: true);
    addTearDown(shadow.dispose);
    final token = shadow.beginActivity();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(shadow.history, isNotEmpty);
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.system);
    shadow.endActivity(token);
    final doctor = await RefreshRate.doctor(view: tester.view);
    expect(
        doctor.findings.any((f) => f.code == 'presentationUnavailable'), true);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('bounded callback observation reports its actual samples',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Workload()));
    final observation = await RefreshRate.observeNativeCadence();
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.iOS) {
      expect(observation.value, greaterThan(0));
      expect(observation.sampleCount, greaterThan(1));
      expect(observation.window, isNotNull);
    } else {
      expect(observation.value, isNull);
      expect(observation.unavailableReason, isNotNull);
    }
    await tester.pumpWidget(const SizedBox());
  });
}

class _Workload extends StatefulWidget {
  const _Workload();
  @override
  State<_Workload> createState() => _WorkloadState();
}

class _WorkloadState extends State<_Workload>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))
        ..repeat();
  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      body: Center(
          child: RotationTransition(
              turns: animation,
              child: const SizedBox(
                  width: 120,
                  height: 120,
                  child: ColoredBox(color: Colors.blue)))));
}
