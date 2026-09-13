import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:refresh_rate/refresh_rate.dart';

/// Paired workload captures. Profile on a physical device for useful overhead
/// evidence; debug/simulator runs validate only capture and cleanup behavior.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('capture paired overlay-off and overlay-on workload costs',
      (tester) async {
    if (const bool.fromEnvironment('REQUIRE_PROFILE')) {
      expect(kProfileMode, true,
          reason: 'Overhead qualification requires a real profile build');
    }
    await tester.pumpWidget(const MaterialApp(home: _Animation()));
    expect(binding.lifecycleState, AppLifecycleState.resumed,
        reason: 'Keep the physical device unlocked for the entire capture.');
    await RefreshRate.refresh();
    final runs = <Map<String, Object?>>[];
    for (var round = 0; round < 3; round++) {
      // Alternate ordering to expose drift rather than assigning it to overlay.
      for (final overlay in round.isEven ? [false, true] : [true, false]) {
        RefreshRate.hideOverlay();
        if (overlay) RefreshRate.showOverlay(expectedFps: 60);
        await Future<void>.delayed(const Duration(milliseconds: 700));
        final session =
            RefreshRate.startSession('overlay-overhead', expectedFps: 60);
        await Future<void>.delayed(const Duration(seconds: 4));
        final report = await session.end();
        expect(report.frameCount, greaterThan(0));
        expect(report.excludedDuration, Duration.zero,
            reason:
                'A background interruption invalidates paired overhead evidence.');
        expect(report.boundaryCoverageComplete, true);
        expect(report.validDuration,
            greaterThanOrEqualTo(const Duration(seconds: 4)));
        runs.add(
            {'round': round, 'overlay': overlay, 'report': report.toMap()});
      }
    }
    RefreshRate.hideOverlay();
    await tester.pumpWidget(const SizedBox());
    expect(RefreshRate.isOverlayVisible, false);
    binding.reportData = {
      'experiment': 'paired-overlay-overhead',
      'debugBuild': kDebugMode,
      'profileBuild': kProfileMode,
      'runs': runs,
      'interpretation':
          'Compare paired build/raster costs, cadence, coverage and thermal segments. No overhead pass threshold or causal claim is inferred automatically.'
    };
    debugPrint(
        'OVERLAY_OVERHEAD: ${runs.length} paired captures; debug=$kDebugMode; profile=$kProfileMode');
  });
}

class _Animation extends StatefulWidget {
  const _Animation();
  @override
  State<_Animation> createState() => _AnimationState();
}

class _AnimationState extends State<_Animation>
    with SingleTickerProviderStateMixin {
  late final animation =
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
          child: RotationTransition(
              turns: animation,
              child: const SizedBox(
                  width: 180,
                  height: 180,
                  child: ColoredBox(color: Colors.blue)))));
}
