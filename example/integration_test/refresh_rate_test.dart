import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:refresh_rate/refresh_rate.dart';
import 'package:refresh_rate/src/verification/frame_collector.dart';

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
      for (final rate in [
        info.nativeReportedDisplayHz,
        info.displayModeMaxHz
      ]) {
        if (rate != null) expect(rate, greaterThan(0));
      }
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
    await policy.ready;
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
        !RefreshRate.isLowPowerMode &&
                ![ThermalState.serious, ThermalState.critical]
                    .contains(RefreshRate.thermalState) &&
                (policyCaps.surfaceVoting ||
                    policyCaps.windowPreferences ||
                    policyCaps.engineControl)
            ? PreferenceKind.high
            : PreferenceKind.system);
    if (RefreshRate.requestedPreference.kind == PreferenceKind.system) {
      expect(policy.history.last.reason,
          anyOf('powerOrThermal', 'unsupportedPolicy'));
    }
    await waitFor(
        () => RefreshRate.requestedPreference.kind == PreferenceKind.system);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('real frames reach sessions, exports and removable overlays',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Workload()));
    final delivered = <FrameSample>[];
    final stopProbe = FrameCollector.instance.subscribe(delivered.addAll);
    addTearDown(stopProbe);
    final session =
        RefreshRate.startSession('integration-animation', expectedFps: 60);
    addTearDown(session.end);
    session.setTag('screen', 'integration');
    session.mark('animation-started');
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
    expect(report.stutters['episodeCount'], isA<int>());
    final bundle = await RefreshRate.diagnosticBundle(
        session: report,
        environment: {'scenario': 'integration'},
        policy: TelemetryExportPolicy(allowedTags: {'screen'}));
    expect(jsonDecode(bundle.toJson())['session']['frameCount'],
        report.frameCount);
    expect(report.toMarkdown(), contains('presentation unavailable'));
    expect(report.evaluate(RefreshRateThresholds()).inconclusive, isTrue);
    stopProbe();
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

  testWidgets('touch restoration, shadow decisions and configuration checks',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Workload()));
    final caps = await RefreshRate.capabilities();
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
    if (!caps.touchBoost) {
      expect((await RefreshRate.resetTouchBoost()).status,
          RequestStatus.unsupported);
      if (!kIsWeb) {
        await expectLater(
            RefreshRate.setTouchBoost(true), throwsA(isA<Exception>()));
      }
    }
    final shadow = RefreshRate.auto(shadowMode: true);
    addTearDown(shadow.dispose);
    final token = shadow.beginActivity();
    await shadow.ready;
    expect(shadow.history, isNotEmpty);
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.system);
    shadow.endActivity(token);
    final doctor = await RefreshRate.doctor(view: tester.view);
    expect(
        doctor.findings.any((f) => f.code == 'presentationUnavailable'), true);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'legacy entry points and all preference categories have explicit outcomes',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Workload()));
    final caps = await RefreshRate.capabilities();
    final high =
        caps.surfaceVoting || caps.windowPreferences || caps.engineControl;
    checkSubmission(await RefreshRate.enable(), high);
    await RefreshRate.disable();
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.system);
    for (final category in RateCategory.values) {
      checkSubmission(await RefreshRate.category(category), caps.categoryHints);
    }
    for (final strategy in FrameRateSwitchStrategy.values) {
      final result =
          await RefreshRate.matchContent(24000 / 1001, strategy: strategy);
      final supported = caps.contentMatching &&
          (strategy == FrameRateSwitchStrategy.seamlessOnly ||
              (RefreshRate.info.androidApiLevel ?? 0) >= 31);
      checkSubmission(result, supported);
      expect(result.preference.fps, closeTo(23.976023976, .00001));
    }
    await RefreshRate.preferDefault();
    checkSubmission(
        await RefreshRate.boost(const Duration(milliseconds: 150)), high);
    await waitFor(
        () => RefreshRate.requestedPreference.kind == PreferenceKind.system);
    expect(RefreshRate.info.isStale, isFalse);
    expect(RefreshRate.displays, isNotEmpty);
    expect(RefreshRate.supportsHighRefreshRate,
        RefreshRate.info.supportsHighRefreshRate);
    expect(RefreshRate.isProMotionConfigured,
        RefreshRate.info.iosProMotionEnabled);
    expect(
        RefreshRate.isLowPowerMode, RefreshRate.info.isLowPowerMode ?? false);
    expect(RefreshRate.thermalState, RefreshRate.info.thermalState);
  });

  testWidgets(
      'unchanged requests do not write again and forced reconciliation retries',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Workload()));
    final caps = await RefreshRate.capabilities();
    final high =
        caps.surfaceVoting || caps.windowPreferences || caps.engineControl;
    await RefreshRate.preferMax();
    final before =
        (await RefreshRate.diagnostics()).nativeMetadata['submissionCount'];
    for (var i = 0; i < 12; i++) {
      final result = await RefreshRate.preferMax();
      expect(result.reused, high);
    }
    final after =
        (await RefreshRate.diagnostics()).nativeMetadata['submissionCount'];
    if (before != null) expect(after, before);
    final forced = await RefreshRate.controller.reconcile(force: true);
    expect(forced.reused, false);
    if (before is int) {
      expect(
          (await RefreshRate.diagnostics()).nativeMetadata['submissionCount'],
          before + 1);
    }
  });

  testWidgets(
      'animation stop, restart, reverse and disposal release owned boosts',
      (tester) async {
    final key = GlobalKey<_WorkloadState>();
    await tester.pumpWidget(MaterialApp(home: _Workload(key: key)));
    final animation = key.currentState!.animation;
    final detach = RefreshRate.boostDuring(animation);
    addTearDown(detach);
    await waitFor(
        () => RefreshRate.requestedPreference.kind == PreferenceKind.high);
    animation.stop();
    await waitFor(
        () => RefreshRate.requestedPreference.kind == PreferenceKind.system);
    animation.repeat(reverse: true);
    await waitFor(
        () => RefreshRate.requestedPreference.kind == PreferenceKind.high);
    animation.stop(canceled: false);
    await waitFor(
        () => RefreshRate.requestedPreference.kind == PreferenceKind.system);
    animation.reverse(from: .2);
    await waitFor(
        () => RefreshRate.requestedPreference.kind == PreferenceKind.high);
    await waitFor(
        () => RefreshRate.requestedPreference.kind == PreferenceKind.system);
    animation.repeat();
    await waitFor(
        () => RefreshRate.requestedPreference.kind == PreferenceKind.high);
    detach();
    detach();
    await waitFor(
        () => RefreshRate.requestedPreference.kind == PreferenceKind.system);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'all automatic policies initialize and release multiple activities',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Workload()));
    final caps = await RefreshRate.capabilities();
    for (final mode in RefreshRatePolicy.values) {
      final policy = RefreshRate.auto(
          policy: mode, idleDelay: const Duration(milliseconds: 100));
      final first = policy.beginActivity(), second = policy.beginActivity();
      expect(RefreshRate.requestedPreference.kind, PreferenceKind.system);
      await policy.ready;
      final constrained = RefreshRate.isLowPowerMode ||
          [ThermalState.serious, ThermalState.critical]
              .contains(RefreshRate.thermalState);
      final expected = constrained || mode == RefreshRatePolicy.system
          ? PreferenceKind.system
          : mode == RefreshRatePolicy.battery
              ? (caps.categoryHints
                  ? PreferenceKind.category
                  : PreferenceKind.system)
              : caps.surfaceVoting ||
                      caps.windowPreferences ||
                      caps.engineControl
                  ? PreferenceKind.high
                  : PreferenceKind.system;
      expect(RefreshRate.requestedPreference.kind, expected);
      policy.endActivity(first);
      expect(RefreshRate.requestedPreference.kind, expected);
      policy.endActivity(second);
      await waitFor(
          () => RefreshRate.requestedPreference.kind == PreferenceKind.system);
      await policy.dispose();
    }
  });

  testWidgets(
      'overlay shows explicit budgets and updates numeric requests while idle',
      (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: Text('idle'))));
    RefreshRate.showOverlay(expectedFps: 120);
    await waitFor(() => RefreshRate.isOverlayVisible);
    await RefreshRate.matchContent(24000 / 1001);
    await waitFor(
        () => find.text('Requested: content 23.976 FPS').evaluate().isNotEmpty);
    expect(find.text('Workload: 120.0 FPS · budget: 8.33 ms'), findsOneWidget);
    await RefreshRate.preferDefault();
    await waitFor(() => find.text('Requested: system').evaluate().isNotEmpty);
    RefreshRate.hideOverlay();
    RefreshRate.showOverlay();
    await waitFor(() =>
        find.text('Workload: unknown · budget: unknown').evaluate().isNotEmpty);
    RefreshRate.hideOverlay();
    RefreshRate.showHz();
    await waitFor(() => RefreshRate.isOverlayVisible);
    expect(FrameCollector.instance.subscriberCount, 0);
    RefreshRate.hideOverlay();
    RefreshRate.showFPS(expectedFps: 60);
    RefreshRate.hideOverlay();
    await tester.pump();
    expect(RefreshRate.isOverlayVisible, false);
    expect(FrameCollector.instance.subscriberCount, 0);
  });

  testWidgets('nested and inactive scopes preserve independent ownership',
      (tester) async {
    final outer = RefreshRate.request(const RatePreference.high(),
        owner: 'outer', priority: 10);
    addTearDown(outer.release);
    Widget app(bool active, bool ticker) => MaterialApp(
        home: TickerMode(
            enabled: ticker,
            child: RefreshRateScope(
                active: active,
                preference: RatePreference.content(30),
                child: const _Workload())));
    await tester.pumpWidget(app(true, true));
    await waitFor(
        () => RefreshRate.requestedPreference.kind == PreferenceKind.content);
    await tester.pumpWidget(app(false, true));
    await waitFor(
        () => RefreshRate.requestedPreference.kind == PreferenceKind.high);
    await tester.pumpWidget(app(true, false));
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.high);
    await tester.pumpWidget(const SizedBox());
    await outer.release();
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.system);
  });

  testWidgets(
      'content playback speed, visibility and stop restore the remaining owner',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Workload()));
    final content = RefreshRateContentController();
    addTearDown(content.dispose);
    await RefreshRate.preferMax();
    await content.update(sourceFps: 24, playbackSpeed: 1.25);
    expect(RefreshRate.requestedPreference.fps, 30);
    await content.update(sourceFps: 24, visible: false);
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.high);
    await content.update(sourceFps: 24);
    await content.update(sourceFps: 24, playing: false);
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.high);
    await content.dispose();
    expect(() => content.update(sourceFps: 24), throwsStateError);
  });

  testWidgets(
      'whole-session statistics survive history eviction and exports preserve privacy',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Workload()));
    var count = 0;
    final stop =
        FrameCollector.instance.subscribe((frames) => count += frames.length);
    addTearDown(stop);
    final session = RefreshRate.startSession('long-animation', expectedFps: 60);
    addTearDown(session.end);
    session.setTag('scenario', 'animation');
    session.setTag('user', 'private-id');
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (count < 750 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    final report = await session.end();
    expect(report.frameCount, greaterThan(600));
    expect(report.recentFrames.length, lessThanOrEqualTo(600));
    expect(report.intervalCount, greaterThan(100));
    expect(jsonDecode(report.toJson())['onePercentLowFps'], greaterThan(0));
    expect(report.percentilesMs['rasterP99'], isNotNull);
    final bundle = await RefreshRate.diagnosticBundle(
        session: report,
        reproduction: 'secret',
        policy: TelemetryExportPolicy(
            allowedTags: {'scenario'},
            maxBytes: 1000000,
            redact: (_, value) => value == 'secret' ? null : value));
    expect(bundle.toJson(), isNot(contains('private-id')));
    expect(jsonDecode(bundle.toNdjson())['reproduction'], isNull);
    expect(jsonDecode(report.toNdjson())['frameCount'], report.frameCount);
    expect(
        report
            .compareTo(report,
                environmentKey: 'same', baselineEnvironmentKey: 'different')
            .inconclusive,
        true);
    expect(report.evaluate(RefreshRateThresholds()).inconclusive, true);
    stop();
  });

  testWidgets(
      'workload target changes and explicit pauses are exported as separate segments',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Workload()));
    final session = RefreshRate.startSession('targets', expectedFps: 60);
    addTearDown(session.end);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    session.setExpectedFps(30);
    session.mark('target-change');
    await Future<void>.delayed(const Duration(milliseconds: 600));
    session.pause();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    session.resume();
    session.setExpectedFps(null);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final ending = session.end();
    expect(identical(ending, session.end()), true);
    final report = await ending;
    expect(report.segments.map((s) => s['targetHz']),
        containsAll([60.0, 30.0, null]));
    expect(report.excludedDuration.inMilliseconds, greaterThanOrEqualTo(180));
    expect(report.markers.any((m) => m['label'] == 'target-change'), true);
    expect(() => session.resume(), throwsStateError);
    expect(FrameCollector.instance.subscriberCount, 0);
  });

  testWidgets(
      'real slow Flutter builds produce phase overruns and cadence stutters',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Workload(stress: true)));
    final session =
        RefreshRate.startSession('intentional-slow-build', expectedFps: 60);
    addTearDown(session.end);
    await Future<void>.delayed(const Duration(seconds: 2));
    final report = await session.end();
    expect(report.frameCount, greaterThan(5));
    expect(report.buildOverrunCount, greaterThan(0));
    expect(report.stutters['episodeCount'], greaterThan(0));
    expect(report.phaseOverrunPercent, greaterThan(0));
    expect(report.presentedFps, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('bounded callback observation reports its actual samples',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Workload()));
    final caps = await RefreshRate.capabilities();
    expect(caps.callbackObservation,
        kIsWeb || defaultTargetPlatform == TargetPlatform.iOS);
    final observation = await RefreshRate.observeNativeCadence();
    if (caps.callbackObservation) {
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
  const _Workload({super.key, this.stress = false});
  final bool stress;
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
        child: AnimatedBuilder(
            animation: animation,
            child: const SizedBox(
                width: 120, height: 120, child: ColoredBox(color: Colors.blue)),
            builder: (_, child) {
              if (widget.stress) {
                final stall = Stopwatch()..start();
                while (stall.elapsedMilliseconds < 40) {
                  /* Deliberate bounded UI work. */
                }
              }
              return Transform.rotate(
                  angle: animation.value * 6.283185, child: child);
            }),
      ));
}
