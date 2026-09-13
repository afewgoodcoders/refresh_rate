import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:refresh_rate/refresh_rate.dart';
import 'package:refresh_rate/src/generated/refresh_rate_api.g.dart';

// Host enables Android Battery Saver before controller creation, then disables it on cue.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
      'cold policy initialization respects native Battery Saver and records recovery',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: CircularProgressIndicator())));
    final foregroundDeadline = DateTime.now().add(const Duration(seconds: 30));
    while (binding.lifecycleState != AppLifecycleState.resumed &&
        DateTime.now().isBefore(foregroundDeadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(binding.lifecycleState, AppLifecycleState.resumed,
        reason: 'Keep the phone unlocked with this test app visible.');
    if (const bool.fromEnvironment('POWER_AFTER_LAUNCH')) {
      debugPrint('REFRESH_RATE_HOST_POWER_ON');
      // Poll the typed host directly so the facade's cached state stays cold.
      final host = RefreshRateHostApi();
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while ((await host.getDisplayInfo()).isLowPowerMode != true &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect((await host.getDisplayInfo()).isLowPowerMode, true);
    }
    final policy = RefreshRate.auto();
    addTearDown(policy.dispose);
    final activity = policy.beginActivity();
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.system);
    await policy.ready;
    expect(RefreshRate.info.isLowPowerMode, true);
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.system);
    expect(policy.history.last.reason, 'powerOrThermal');
    final session =
        RefreshRate.startSession('battery-saver-transition', expectedFps: 60);
    addTearDown(session.end);
    await Future<void>.delayed(const Duration(seconds: 1));
    debugPrint('REFRESH_RATE_HOST_POWER_OFF');
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (RefreshRate.info.isLowPowerMode != false &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(RefreshRate.info.isLowPowerMode, false);
    final thermallyConstrained = [ThermalState.serious, ThermalState.critical]
        .contains(RefreshRate.thermalState);
    expect(RefreshRate.requestedPreference.kind,
        thermallyConstrained ? PreferenceKind.system : PreferenceKind.high);
    expect(policy.history.last.reason,
        thermallyConstrained ? 'powerOrThermal' : 'activity');
    debugPrint('POWER_RECOVERY: thermal=${RefreshRate.thermalState.name}, '
        'preference=${RefreshRate.requestedPreference.kind.name}');
    await Future<void>.delayed(const Duration(seconds: 1));
    final report = await session.end();
    expect(report.segments.map((s) => s['lowPowerMode']),
        containsAll([true, false]));
    expect(
        report.validDuration, greaterThanOrEqualTo(const Duration(seconds: 2)));
    expect(report.excludedDuration, Duration.zero);
    expect(report.frameCount, greaterThan(0));
    policy.endActivity(activity);
    await policy.dispose();
    await tester.pumpWidget(const SizedBox());
  });
}
