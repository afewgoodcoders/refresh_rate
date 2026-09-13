import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refresh_rate/refresh_rate.dart';
import 'package:refresh_rate/src/verification/frame_collector.dart';
import 'refresh_rate_api_test.dart' show FakeHostApi;

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
  testWidgets('nested scopes release only their own preference',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: RefreshRateScope(
            preference: const RatePreference.high(),
            child: RefreshRateScope(
                preference: RatePreference.content(24),
                child: const SizedBox()))));
    await tester.pump();
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.content);
    await tester.pumpWidget(MaterialApp(
        home: RefreshRateScope(
            preference: const RatePreference.high(), child: const SizedBox())));
    await tester.pump();
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.high);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.system);
  });
  testWidgets('hidden TickerMode and inactive scopes release preference',
      (tester) async {
    Widget app(bool enabled) => MaterialApp(
        home: TickerMode(
            enabled: enabled,
            child: const RefreshRateScope(
                preference: RatePreference.high(), child: SizedBox())));
    await tester.pumpWidget(app(true));
    await tester.pump();
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.high);
    await tester.pumpWidget(app(false));
    await tester.pump();
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.system);
  });
  testWidgets('Hz badge does not collect timings or sustain frames',
      (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: Text('idle'))));
    RefreshRate.showHz();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(FrameCollector.instance.subscriberCount, 0);
    expect(tester.binding.hasScheduledFrame, false);
    RefreshRate.hideOverlay();
    await tester.pump();
  });
  testWidgets('hide cancels queued overlay insertion', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    RefreshRate.showHz();
    RefreshRate.hideOverlay();
    await tester.pump();
    expect(RefreshRate.isOverlayVisible, false);
    expect(FrameCollector.instance.subscriberCount, 0);
  });
  testWidgets('activity uses idle hysteresis and respects power state',
      (tester) async {
    final changes = StreamController<DisplayInfo>.broadcast();
    final policy = RefreshRateAutoController(
        RefreshRate.controller, changes.stream,
        initialInfo: DisplayInfo.fallback,
        idleDelay: const Duration(milliseconds: 500));
    final token = policy.beginActivity();
    await tester.pump();
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.high);
    policy.endActivity(token);
    await tester.pump(const Duration(milliseconds: 250));
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.high);
    final second = policy.beginActivity();
    await tester.pump();
    changes.add(const DisplayInfo(
        currentRate: 60,
        maxRate: 120,
        minRate: 60,
        supportedRates: [60, 120],
        isVariableRefreshRate: false,
        engineTargetRate: 0,
        thermalState: ThermalState.nominal,
        isLowPowerMode: true));
    await tester.pump();
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.system);
    policy.endActivity(second);
    await tester.runAsync(() async {
      await policy.dispose();
      await changes.close();
    });
  });
  testWidgets(
      'animation adapter supports already-running and repeating controller',
      (tester) async {
    final animation = AnimationController(
        vsync: tester, duration: const Duration(milliseconds: 100));
    animation.repeat(reverse: true);
    final detach = RefreshRate.boostDuring(animation);
    await tester.pump();
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.high);
    await tester.pump(const Duration(milliseconds: 300));
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.high);
    detach();
    detach();
    animation.dispose();
    await tester.pump();
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.system);
  });
}
