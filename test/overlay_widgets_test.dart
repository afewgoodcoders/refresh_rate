import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refresh_rate/refresh_rate.dart';
import 'package:refresh_rate/src/generated/refresh_rate_api.g.dart';
import 'package:refresh_rate/src/verification/fps_tracker.dart';
import 'package:refresh_rate/src/verification/overlay_widgets.dart';
import 'refresh_rate_api_test.dart' show FakeHostApi;

class _DisplayApi extends FakeHostApi {
  _DisplayApi(this.info);
  final DisplayInfoMessage info;
  @override
  DisplayInfoMessage getDisplayInfo() => info;
}

FpsTracker _frames({double? target, int buildUs = 2500}) {
  final tracker = FpsTracker();
  for (var i = 0; i < 120; i++) {
    tracker.addSample(FrameSample(
        buildUs: buildUs,
        rasterUs: 900,
        totalUs: buildUs + 1400,
        vsyncUs: i * 16667,
        timestamp: DateTime.utc(2026).add(Duration(microseconds: i * 16667)),
        targetHz: target));
  }
  return tracker;
}

Widget _app(Widget overlay, {double scale = 1}) => MaterialApp(
    home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: Stack(children: [overlay]))));

Color _color(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!.color!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    RefreshRate.setApiForTesting(FakeHostApi());
  });
  tearDown(() {
    RefreshRate.hideOverlay();
    RefreshRate.clearApiForTesting();
  });

  testWidgets('FPS badge colors follow workload, not the maximum display rate',
      (tester) async {
    await RefreshRate.refresh(); // 120 Hz display, 60 FPS workload.
    final colors = <Color>[];
    for (final target in [60.0, 75.0, 120.0]) {
      await tester.pumpWidget(
          _app(FpsOverlayWidget(tracker: _frames(), expectedFps: target)));
      expect(find.text('60 FPS'), findsOneWidget);
      colors.add(_color(tester, '60 FPS'));
    }
    expect(colors, [
      const Color(0xFF76E88D), // At target: green.
      const Color(0xFFFFC857), // 80% of target: amber.
      const Color(0xFFFF6270), // 50% of target: red.
    ]);
  });

  testWidgets('FPS color can use display timing without inventing a budget',
      (tester) async {
    RefreshRate.setApiForTesting(
        _DisplayApi(DisplayInfoMessage(currentRate: 60, maxRate: 120)));
    await RefreshRate.refresh();
    await tester.pumpWidget(_app(FpsOverlayWidget(tracker: _frames())));
    expect(_color(tester, '60 FPS'), const Color(0xFF76E88D));
    await tester.pumpWidget(_app(FullOverlayWidget(tracker: _frames())));
    expect(_color(tester, '60 FPS'), const Color(0xFF76E88D));
    expect(find.text('unknown'),
        findsNWidgets(4)); // Budget, target, overruns, thermal.
    expect(find.text('16.67 ms'), findsNothing);
  });

  testWidgets('controller passes the workload target into the FPS badge',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    RefreshRate.showFPS(expectedFps: 30);
    await tester.pump();
    await tester.pump();
    final badge =
        tester.widget<FpsOverlayWidget>(find.byType(FpsOverlayWidget));
    expect(badge.expectedFps, 30);
    RefreshRate.hideOverlay();
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('unknown display stays unknown and browser Hz keeps its source',
      (tester) async {
    await tester.pumpWidget(_app(HzOverlayWidget(tracker: _frames())));
    expect(find.text('— Hz'), findsOneWidget);
    RefreshRate.setApiForTesting(_DisplayApi(
        DisplayInfoMessage(currentRate: 59.94, displayServer: 'web')));
    await RefreshRate.refresh();
    await tester.pumpWidget(_app(HzOverlayWidget(tracker: _frames())));
    expect(find.text('59.9 Hz · callback'), findsOneWidget);
    await tester.pumpWidget(_app(FullOverlayWidget(tracker: _frames())));
    expect(find.text('CALLBACK'), findsOneWidget);
    expect(find.text('OS DISPLAY'), findsNothing);
  });

  testWidgets('idle cadence hides old numbers and over-budget phases turn red',
      (tester) async {
    final tracker = _frames(target: 120, buildUs: 10000);
    await tester.pumpWidget(
        _app(FullOverlayWidget(tracker: tracker, expectedFps: 120)));
    expect(_color(tester, '10.0 ms'), const Color(0xFFFF6270));
    expect(find.text('100.0%'), findsOneWidget);
    await tester.pumpWidget(_app(
        FullOverlayWidget(tracker: tracker, expectedFps: 120, stale: true)));
    expect(find.text('IDLE / STALE'), findsOneWidget);
    expect(find.text('10.0 ms'), findsNothing);
    expect(find.text('60 FPS'), findsNothing);
    expect(find.text('100.0%'), findsNothing);
    await tester
        .pumpWidget(_app(FpsOverlayWidget(tracker: tracker, stale: true)));
    expect(find.text('FPS idle'), findsOneWidget);
    expect(_color(tester, 'FPS idle'), const Color(0xFFFFC857));
  });

  testWidgets(
      'HUD fits a narrow phone with larger text and fractional requests',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    RefreshRate.setApiForTesting(_DisplayApi(DisplayInfoMessage(
        currentRate: 120, thermalStateIndex: 2, isLowPowerMode: true)));
    await RefreshRate.refresh();
    await RefreshRate.matchContent(24000 / 1001);
    await tester.pumpWidget(_app(
        FullOverlayWidget(tracker: _frames(target: 120), expectedFps: 120),
        scale: 1.5));
    expect(tester.takeException(), isNull);
    expect(find.text('content 23.976 FPS'), findsOneWidget);
    expect(find.text('Low Power Mode'), findsOneWidget);
    expect(_color(tester, 'serious'), const Color(0xFFFF6270));
    expect(tester.getBottomRight(find.byType(FullOverlayWidget)).dx,
        lessThanOrEqualTo(320));
    expect(tester.getBottomRight(find.byType(FullOverlayWidget)).dy,
        lessThanOrEqualTo(740));
  });
}
