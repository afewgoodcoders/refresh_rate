import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:refresh_rate/refresh_rate.dart';
import 'package:refresh_rate/src/verification/frame_collector.dart';
import 'package:refresh_rate_example/src/benchmark_workload.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> waitFor(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (!condition() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(condition(), true);
  }

  testWidgets('example captures identical baseline and high workloads',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BenchmarkWorkload()));
    await RefreshRate.preferMax();
    RefreshRate.showOverlay(expectedFps: 60);
    await tester.tap(find.text('Run comparison'));
    await waitFor(
        () => find.textContaining('System default:').evaluate().isNotEmpty);
    expect(find.textContaining('Requested high:'), findsOneWidget);
    expect(find.textContaining('16.67 ms budget'), findsNWidgets(2));
    expect(RefreshRate.isOverlayVisible, false);
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.high);
    expect(FrameCollector.instance.subscriberCount, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await RefreshRate.preferDefault();
  });

  testWidgets(
      'closing the example during capture releases its owner and collector',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BenchmarkWorkload()));
    await tester.tap(find.text('Run comparison'));
    await waitFor(() => FrameCollector.instance.subscriberCount > 0);
    await tester.pumpWidget(const SizedBox());
    await waitFor(() => FrameCollector.instance.subscriberCount == 0);
    expect(RefreshRate.requestedPreference.kind, PreferenceKind.system);
    await Future<void>.delayed(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });
}
