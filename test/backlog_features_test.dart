import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refresh_rate/refresh_rate.dart';
import 'package:refresh_rate/src/verification/fps_tracker.dart';
import 'package:refresh_rate/src/verification/session_clock.dart';
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
