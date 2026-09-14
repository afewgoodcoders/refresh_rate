import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:refresh_rate/refresh_rate.dart';
import 'package:refresh_rate/src/verification/fps_tracker.dart';
import 'package:refresh_rate/src/verification/overlay_widgets.dart';

import 'package:refresh_rate_example/main.dart';

/// Waits for [finder] to match at least one widget, polling every 100 ms.
Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!finder.evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Screenshot content did not appear: $finder');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 200));
}

/// Converts the Flutter surface to an image, pumps one frame, and
/// takes a named screenshot via the integration test binding.
Future<void> _captureScreenshot(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
) async {
  await binding.convertFlutterSurfaceToImage();
  await tester.pump(const Duration(milliseconds: 200));
  await binding.takeScreenshot(name);
}

// Use deterministic frame samples for reproducible illustrative screenshots,
// rendered by the production widgets. Hz still comes from the native device.
FpsTracker _screenshotFrames() {
  final tracker = FpsTracker();
  for (var i = 0; i < 120; i++) {
    tracker.addSample(FrameSample(
        buildUs: 2500 + (i % 7) * 50,
        rasterUs: 900 + (i % 5) * 40,
        totalUs: 3700 + (i % 19 == 0 ? 2200 : 0),
        vsyncUs: i * 8333,
        timestamp: DateTime.utc(2026).add(Duration(microseconds: i * 8333)),
        targetHz: 120));
  }
  return tracker;
}

/// Wraps the example app with a production overlay on top.
Widget _appWithOverlay(Widget overlay) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: const RefreshRateExampleApp(),
    builder: (_, child) => Stack(children: [child!, overlay]));

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    RefreshRate.hideOverlay();
    await RefreshRate.preferDefault();
  });
  testWidgets('screenshot: fps', (tester) async {
    await tester.pumpWidget(_appWithOverlay(
        FpsOverlayWidget(tracker: _screenshotFrames(), expectedFps: 120)));
    await tester.pump(const Duration(seconds: 1));

    await _waitFor(tester, find.text('Diagnostic Console'));

    // Refresh native metadata without claiming that the request is fulfilled.
    await RefreshRate.enable();
    await RefreshRate.refresh();
    expect(find.text('120 FPS'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));

    await _captureScreenshot(binding, tester, 'fps');
  });

  testWidgets('screenshot: hz', (tester) async {
    await tester.pumpWidget(
        _appWithOverlay(HzOverlayWidget(tracker: _screenshotFrames())));
    await tester.pump(const Duration(seconds: 1));

    await _waitFor(tester, find.text('Diagnostic Console'));

    await RefreshRate.enable();
    await RefreshRate.refresh();
    await tester.pump(const Duration(seconds: 2));

    // Rebuild the badge with the refreshed native metadata.
    await tester.pumpWidget(
        _appWithOverlay(HzOverlayWidget(tracker: _screenshotFrames())));
    await _captureScreenshot(binding, tester, 'hz');
  });

  testWidgets('screenshot: hud', (tester) async {
    await RefreshRate.refresh();
    await tester.pumpWidget(_appWithOverlay(
        FullOverlayWidget(tracker: _screenshotFrames(), expectedFps: 120)));
    await _waitFor(tester, find.text('Diagnostic Console'));
    expect(find.text('PHASE OVERRUNS'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(FullOverlayWidget), matching: find.text('8.33 ms')),
        findsOneWidget);
    await _captureScreenshot(binding, tester, 'hud');
  });
}
