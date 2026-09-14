import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refresh_rate/refresh_rate.dart';
import 'package:refresh_rate/src/generated/refresh_rate_api.g.dart';
import 'refresh_rate_api_test.dart' show FakeHostApi;

class InitialStateApi extends FakeHostApi {
  final initial = Completer<DisplayInfoMessage>();
  @override
  Future<DisplayInfoMessage> getDisplayInfo() => initial.future;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    RefreshRate.setApiForTesting(FakeHostApi());
  });
  tearDown(() {
    RefreshRate.hideOverlay();
    RefreshRate.clearApiForTesting();
  });

  testWidgets(
      'stopping an animation releases the boost without disposing the adapter',
      (tester) async {
    final animation = AnimationController(
        vsync: tester, duration: const Duration(seconds: 1));
    final detach = RefreshRate.boostDuring(animation);
    animation.repeat();
    await tester.pump();
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.high);
    animation.stop();
    await tester.pump(const Duration(milliseconds: 40));
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.system);
    animation.repeat(reverse: true);
    await tester.pump();
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.high);
    animation.stop(canceled: false);
    await tester.pump(const Duration(milliseconds: 40));
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.system);
    detach();
    animation.dispose();
    await tester.pump(const Duration(milliseconds: 100));
    expect(binding.hasScheduledFrame, false);
  });

  testWidgets(
      'policy waits for an initial low-power snapshot before requesting high',
      (tester) async {
    final api = InitialStateApi();
    RefreshRate.setApiForTesting(api);
    final policy = RefreshRate.auto();
    policy.beginActivity();
    await tester.pump();
    expect(api.calls, isEmpty);
    api.initial.complete(DisplayInfoMessage(
        currentRate: 120,
        maxRate: 120,
        isLowPowerMode: true,
        thermalStateIndex: 0));
    await tester.pump();
    await policy.ready;
    expect(api.calls.where((p) => p.kind == PreferenceKind.high), isEmpty);
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.system);
    await tester.runAsync(policy.dispose);
  });

  testWidgets(
      'disposing while policy initialization is pending cannot create a lease',
      (tester) async {
    final api = InitialStateApi();
    RefreshRate.setApiForTesting(api);
    final policy = RefreshRate.auto();
    policy.beginActivity();
    await tester.runAsync(policy.dispose);
    api.initial.complete(DisplayInfoMessage(
        currentRate: 120, maxRate: 120, isLowPowerMode: false));
    await tester.pump();
    await policy.ready;
    expect(api.calls, isEmpty);
  });

  testWidgets(
      'failed initial query keeps automatic scheduling at system policy',
      (tester) async {
    final api = InitialStateApi();
    RefreshRate.setApiForTesting(api);
    final policy = RefreshRate.auto();
    policy.beginActivity();
    api.initial.completeError(StateError('query unavailable'));
    await tester.pump();
    await policy.ready;
    expect(api.calls, isEmpty);
    await tester.runAsync(policy.dispose);
  });

  test(
      'successful duplicates are reused, while failures and forced writes retry',
      () async {
    var writes = 0;
    var fail = false;
    var backend = 'windowPreference';
    final controller = RateController((preference) async {
      writes++;
      return RateRequestResult(
          status: fail ? RequestStatus.failed : RequestStatus.submitted,
          preference: preference,
          backend: backend,
          scope: 'surface');
    });
    final one = controller.acquire(RatePreference.content(24));
    await one.ready;
    backend = 'flutterSurface';
    final two = controller.acquire(RatePreference.content(24));
    final reused = await two.ready;
    expect(reused.reused, true);
    expect(reused.backend, 'windowPreference');
    await one.release();
    expect(writes, 1);
    final refreshed = await controller.reconcile(force: true);
    expect(refreshed.reused, false);
    expect(refreshed.backend, 'flutterSurface');
    expect(writes, 2);
    fail = true;
    await controller.reconcile(force: true);
    await controller.reconcile();
    expect(writes, 4);
    fail = false;
    expect((await controller.reconcile()).submitted, true);
    expect(writes, 5);
    await two.release();
    controller.dispose();
  });

  testWidgets('idle overlay refreshes numeric requests without display events',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    RefreshRate.showOverlay(expectedFps: 120);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('WORKLOAD'), findsOneWidget);
    expect(find.text('120.0 FPS'), findsOneWidget);
    expect(find.text('8.33 ms'), findsOneWidget);
    RefreshRate.matchContent(24000 / 1001);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('REQUEST'), findsOneWidget);
    expect(find.text('content 23.976 FPS'), findsOneWidget);
    RefreshRate.hideOverlay();
    await tester.pump();
    expect(() => RefreshRate.showOverlay(expectedFps: 0), throwsArgumentError);
  });

  test('high-refresh capability stays separate from the ProMotion plist flag',
      () {
    final low = DisplayInfo.fromMessage(
        DisplayInfoMessage(maxRate: 60, iosProMotionEnabled: true));
    expect(low.supportsHighRefreshRate, false);
    final high = DisplayInfo.fromMessage(
        DisplayInfoMessage(maxRate: 120, iosProMotionEnabled: false));
    expect(high.supportsHighRefreshRate, true);
    expect(DisplayInfo.fallback.supportsHighRefreshRate, isNull);
  });
}
