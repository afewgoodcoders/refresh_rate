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

    Future<Map<Object?, Object?>> waitForNativeHigh(
        {Map<Object?, Object?>? after}) async {
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      Map<Object?, Object?> native = {};
      Map<Object?, Object?>? ready;
      while (DateTime.now().isBefore(deadline)) {
        native = (await RefreshRate.diagnostics()).nativeMetadata;
        final last = native['lastNativeRequest'] as Map?;
        final generation = native['targetGeneration'] as num?;
        final submissions = native['submissionCount'] as num?;
        final targetReapplied = after == null ||
            (generation == after['targetGeneration'] ||
                (submissions != null &&
                    submissions > (after['submissionCount'] as num)));
        if (binding.lifecycleState == AppLifecycleState.resumed &&
            session.state == SessionState.running &&
            RefreshRate.requestedPreference.kind == PreferenceKind.high &&
            native['activityAttached'] == true &&
            native['surfaceAvailable'] == true &&
            generation != null &&
            submissions != null &&
            last?['status'] == 'submitted' &&
            last?['backend'] == 'flutterSurface' &&
            (last?['preference'] as Map?)?['kind'] == 'high' &&
            targetReapplied) {
          // Rotation may briefly deactivate the scope after Flutter's size
          // changes. Require resumed ownership and an unchanged native target
          // and submission across consecutive reads before asserting recovery.
          if (ready?['targetGeneration'] == generation &&
              ready?['submissionCount'] == submissions) {
            return native;
          }
          ready = native;
        } else {
          ready = null;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      fail('Native high preference was not restored: '
          'before=$after; latest=$native; lifecycle=${binding.lifecycleState}; '
          'preference=${RefreshRate.requestedPreference.kind}; '
          'session=${session.state}');
    }

    await waitFor(
        () => RefreshRate.requestedPreference.kind == PreferenceKind.high);
    final beforeBackground = await waitForNativeHigh();
    debugPrint('REFRESH_RATE_HOST_BACKGROUND');
    await waitFor(() => states.contains(AppLifecycleState.paused));
    expect(session.state, SessionState.interrupted);
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.system);
    await waitFor(() => states.last == AppLifecycleState.resumed);
    await waitFor(() => session.state == SessionState.running);
    await waitFor(
        () => RefreshRate.requestedPreference.kind == PreferenceKind.high);
    final beforeRotation = await waitForNativeHigh(after: beforeBackground);
    final size = tester.view.physicalSize;
    debugPrint('REFRESH_RATE_HOST_ROTATE');
    await waitFor(() => tester.view.physicalSize != size);
    // Flutter metrics may arrive before native surface callbacks. Observe the
    // native vote without submitting another request that could mask lost state.
    final native = await waitForNativeHigh(after: beforeRotation);
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
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.high);
    // A reused result describes the original Dart submission, whose backend may
    // predate native reapplication. Current backend evidence comes from above.
    final request =
        await RefreshRate.controller.reconcile(reason: 'rotationTest');
    expect(request.status, RequestStatus.submitted);
    expect(request.preference.kind, PreferenceKind.high);
    expect(request.reused, true);
    expect((await RefreshRate.diagnostics()).nativeMetadata['submissionCount'],
        native['submissionCount']);
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
