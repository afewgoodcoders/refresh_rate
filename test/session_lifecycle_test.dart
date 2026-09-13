import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refresh_rate/refresh_rate.dart';
import 'package:refresh_rate/src/verification/frame_collector.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
      () => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
  test('late batches are filtered by event time and exclusions', () async {
    var now = DateTime.utc(2026);
    final start = now;
    final session = RefreshRateSession.create('segments', DisplayInfo.fallback,
        expectedFps: 60, clock: () => now, finalizationTimeout: Duration.zero);
    FrameSample frame(int us) => FrameSample(
        buildUs: 1000,
        rasterUs: 1000,
        totalUs: 2000,
        vsyncUs: us,
        timestamp: start.add(Duration(microseconds: us)));
    now = start.add(const Duration(seconds: 1));
    session.pause();
    now = start.add(const Duration(seconds: 3));
    session.resume();
    now = start.add(const Duration(seconds: 4));
    session.addSamplesForTesting([
      frame(-100),
      frame(0),
      frame(16667),
      frame(1500000),
      frame(3000000),
      frame(3016667)
    ]);
    final future = session.end();
    session.addSamplesForTesting([frame(3999999), frame(4000001)]);
    final report = await future;
    expect(report.frameCount, 5);
    expect(report.intervalCount, 3);
    expect(report.validDuration, const Duration(seconds: 2));
    expect(report.excludedDuration, const Duration(seconds: 2));
    expect(report.boundaryCoverageComplete, true);
    expect(identical(future, session.end()), true);
    expect(FrameCollector.instance.subscriberCount, 0);
  });
  test('ending in background accounts for the partial exclusion', () async {
    var now = DateTime.utc(2026);
    final session = RefreshRateSession.create(
        'background', DisplayInfo.fallback,
        clock: () => now, finalizationTimeout: Duration.zero);
    now = now.add(const Duration(seconds: 1));
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(seconds: 2));
    final report = await session.end();
    expect(report.validDuration, const Duration(seconds: 1));
    expect(report.excludedDuration, const Duration(seconds: 2));
    expect(report.boundaryCoverageComplete, false);
  });
  test('late frame receives historical tags and target', () async {
    var now = DateTime.utc(2026);
    final start = now;
    final session = RefreshRateSession.create('tags', DisplayInfo.fallback,
        expectedFps: 60, clock: () => now, finalizationTimeout: Duration.zero);
    session.setTag('screen', 'feed');
    now = now.add(const Duration(seconds: 1));
    session.setTag('screen', 'video');
    session.setExpectedFps(24);
    session.addSamplesForTesting([
      FrameSample(
          buildUs: 2000,
          rasterUs: 1000,
          totalUs: 3000,
          vsyncUs: 100,
          timestamp: start.add(const Duration(milliseconds: 100))),
      FrameSample(
          buildUs: 1000,
          rasterUs: 1000,
          totalUs: 2000,
          vsyncUs: 1100000,
          timestamp: start.add(const Duration(milliseconds: 1100))),
    ]);
    now = now.add(const Duration(seconds: 1));
    final report = await session.end();
    expect(report.worstFrames.first.tags['screen'], 'feed');
    expect(report.worstFrames.first.targetHz, 60);
    expect(report.worstFrames.last.targetHz, 24);
    expect(report.intervalCount, 0);
  });
}
