import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:refresh_rate/refresh_rate.dart';

// Run through scripts/test_android_lifecycle.py: the host drives actual Android
// Home/resume and rotation while this test observes Flutter/plugin state.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('native background, resume and rotation preserve ownership',
      (tester) async {
    final states = <AppLifecycleState>[];
    final listener = AppLifecycleListener(onStateChange: states.add);
    addTearDown(listener.dispose);
    await tester.pumpWidget(const MaterialApp(
        home: RefreshRateScope(
            preference: RatePreference.high(),
            child: Scaffold(body: CircularProgressIndicator()))));
    final session =
        RefreshRate.startSession('native-lifecycle', expectedFps: 60);
    addTearDown(session.end);
    Future<void> waitFor(bool Function() condition) async {
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      while (!condition() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(condition(), true);
    }

    await waitFor(
        () => RefreshRate.requestedPreference.kind == PreferenceKind.high);
    debugPrint('REFRESH_RATE_HOST_BACKGROUND');
    await waitFor(() => states.contains(AppLifecycleState.paused));
    expect(session.state, SessionState.interrupted);
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.system);
    await waitFor(() => states.last == AppLifecycleState.resumed);
    await waitFor(() => session.state == SessionState.running);
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.high);
    final beforeRotation = (await RefreshRate.diagnostics()).nativeMetadata;
    final size = tester.view.physicalSize;
    debugPrint('REFRESH_RATE_HOST_ROTATE');
    await waitFor(() => tester.view.physicalSize != size);
    final request =
        await RefreshRate.controller.reconcile(reason: 'rotationTest');
    expect(request.status, RequestStatus.submitted);
    expect(request.backend, 'flutterSurface');
    final native = (await RefreshRate.diagnostics()).nativeMetadata;
    expect(native['activityAttached'], true);
    expect(native['surfaceAvailable'], true);
    final lastNative = native['lastNativeRequest'] as Map;
    expect(lastNative['status'], 'submitted');
    expect(lastNative['backend'], 'flutterSurface');
    expect((lastNative['preference'] as Map)['kind'], 'high');
    if (native['targetGeneration'] != beforeRotation['targetGeneration']) {
      expect(native['submissionCount'] as num,
          greaterThan(beforeRotation['submissionCount'] as num));
    }
    debugPrint('LIFECYCLE_NATIVE: $native');
    final report = await session.end();
    expect(report.exclusionReasons[ExclusionReason.appBackgrounded],
        greaterThan(0));
    expect(report.excludedDuration,
        greaterThan(const Duration(milliseconds: 500)));
    expect(report.frameCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    await RefreshRate.preferDefault();
  });
}
