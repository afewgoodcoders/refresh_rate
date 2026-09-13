import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:refresh_rate/refresh_rate.dart';

// The debug Android fixture destroys an Activity and starts another with its
// cached engine. No plugin methods or lifecycle callbacks are mocked here.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  const host = MethodChannel('refresh_rate_example/retained_engine');

  Future<Map<Object?, Object?>> snapshot() async =>
      (await host.invokeMapMethod<Object?, Object?>('snapshot'))!;

  Future<Map<Object?, Object?>> replaceActivity(int destroyed) async {
    final previousActivity = (await snapshot())['activity'];
    await host.invokeMethod<void>('replaceActivity');
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    Map<Object?, Object?> state = {};
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      state = await snapshot();
      final native = (await RefreshRate.diagnostics()).nativeMetadata;
      if (state['destroyed'] == destroyed &&
          state['activity'] != previousActivity &&
          native['surfaceAvailable'] == true &&
          binding.lifecycleState == AppLifecycleState.resumed) {
        return state;
      }
    }
    fail('Retained engine did not attach to a replacement Activity: $state');
  }

  testWidgets(
      'retained engine reapplies its owner after ordinary Activity detachment',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: CircularProgressIndicator())));
    await RefreshRate.refresh();
    expect((await RefreshRate.preferMax()).submitted, true);
    final original = await snapshot();
    final before = (await RefreshRate.diagnostics()).nativeMetadata;
    final next = await replaceActivity(1);
    expect(next['engine'], original['engine']);
    expect(next['activity'], isNot(original['activity']));
    expect(next['ordinaryDetach'], true);
    expect(next['detachedWithoutTarget'], true);
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.high);
    // Even before another Dart request, the new native target must receive the vote.
    final reapplied = (await RefreshRate.diagnostics()).nativeMetadata;
    expect(reapplied['targetGeneration'] as num,
        greaterThan(before['targetGeneration'] as num));
    expect(reapplied['submissionCount'] as num,
        greaterThan(before['submissionCount'] as num));
    final last = reapplied['lastNativeRequest'] as Map;
    expect(last['status'], 'submitted');
    expect(last['backend'], 'flutterSurface');
    expect((last['preference'] as Map)['kind'], 'high');
    expect((await RefreshRate.preferMax()).reused, true);
    expect((await RefreshRate.diagnostics()).nativeMetadata['submissionCount'],
        reapplied['submissionCount']);
    debugPrint(
        'RETAINED_ENGINE: before=$before; after=$reapplied; activity=$next');

    await RefreshRate.preferDefault();
    await replaceActivity(2);
    final cleared = (await RefreshRate.diagnostics()).nativeMetadata;
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.system);
    expect(((cleared['lastNativeRequest'] as Map)['preference'] as Map)['kind'],
        'system');
    await tester.pumpWidget(const SizedBox());
  });
}
