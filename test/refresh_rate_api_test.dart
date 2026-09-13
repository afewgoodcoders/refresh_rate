import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:refresh_rate/refresh_rate.dart';
import 'package:refresh_rate/src/generated/refresh_rate_api.g.dart';
import 'package:refresh_rate/src/refresh_rate_api_adapter.dart';

class FakeHostApi implements RefreshRateApiAdapter, RefreshRateRequestAdapter {
  final calls = <RatePreference>[];
  Completer<DisplayInfoMessage>? fetch;
  @override
  FutureOr<DisplayInfoMessage> getDisplayInfo() =>
      fetch?.future ??
      DisplayInfoMessage(currentRate: 120, maxRate: 120, thermalStateIndex: 0);
  @override
  Future<RefreshRateCapabilities> capabilities() async =>
      const RefreshRateCapabilities(surfaceVoting: true);
  @override
  Future<RateRequestResult> submit(RatePreference preference) async {
    calls.add(preference);
    return RateRequestResult(
        status: RequestStatus.submitted,
        preference: preference,
        backend: 'fakeSurface',
        scope: 'test');
  }

  @override
  Future<RateRequestResult> resetTouchBoost() async => const RateRequestResult(
      status: RequestStatus.unsupported, preference: RatePreference.system());

  @override
  void enable() {}
  @override
  void disable() {}
  @override
  void preferMax() {}
  @override
  void preferDefault() {}
  @override
  void matchContent(double fps) {}
  @override
  void boost(int durationMs) {}
  @override
  void setCategory(int c) {}
  @override
  void setTouchBoost(bool e) {}
  @override
  bool isSupported() => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeHostApi fake;
  setUp(() {
    fake = FakeHostApi();
    RefreshRate.setApiForTesting(fake);
  });
  tearDown(RefreshRate.clearApiForTesting);
  test('controls are awaitable and submission does not mean fulfilment',
      () async {
    final result = await RefreshRate.enable();
    expect(result.submitted, true);
    expect(result.fulfilmentObserved, false);
    expect(fake.calls.last.kind, PreferenceKind.high);
  });
  test('fractional content and switch strategy reach the backend', () async {
    await RefreshRate.matchContent(24000 / 1001,
        strategy: FrameRateSwitchStrategy.allowNonSeamless);
    expect(fake.calls.last.fps, 24000 / 1001);
    expect(fake.calls.last.strategy, FrameRateSwitchStrategy.allowNonSeamless);
  });
  test('invalid values do not reach a platform', () {
    for (final fps in [double.nan, double.infinity, -1.0, 0.0]) {
      expect(() => RefreshRate.matchContent(fps), throwsArgumentError);
    }
    expect(() => RefreshRate.boost(const Duration(milliseconds: -1)),
        throwsArgumentError);
    expect(fake.calls, isEmpty);
  });
  test('repeated playback updates return the current backend result', () async {
    final content = RefreshRateContentController();
    addTearDown(content.dispose);
    for (final fps in [24000 / 1001, 30000 / 1001, 30000 / 1001]) {
      final result = await content.update(sourceFps: fps);
      expect(result.status, RequestStatus.submitted);
      expect(result.preference.fps, fps);
    }
  });
  test('late reads cannot overwrite a newer snapshot', () async {
    final first = Completer<DisplayInfoMessage>();
    final second = Completer<DisplayInfoMessage>();
    fake.fetch = first;
    final earlier = RefreshRate.refresh();
    fake.fetch = second;
    final later = RefreshRate.refresh();
    second.complete(DisplayInfoMessage(currentRate: 120));
    await later;
    first.complete(DisplayInfoMessage(currentRate: 60));
    await earlier;
    expect(RefreshRate.info.nativeReportedDisplayHz, 120);
  });
  test('cache resets and unavailable values remain unknown', () async {
    await RefreshRate.refresh();
    expect(RefreshRate.info.currentRate, 120);
    RefreshRate.clearApiForTesting();
    expect(RefreshRate.info.nativeReportedDisplayHz, isNull);
  });
  test('old boost expiry cannot undo an active content preference', () async {
    await RefreshRate.boost(const Duration(milliseconds: 20));
    final content =
        RefreshRate.request(RatePreference.content(24), priority: 250);
    await content.ready;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(fake.calls.last.kind, PreferenceKind.content);
    await content.release();
    expect(fake.calls.last.kind, PreferenceKind.system);
  });
  test('clear imperative request leaves independent scope ownership', () async {
    final scope =
        RefreshRate.request(const RatePreference.high(), priority: 50);
    await scope.ready;
    await RefreshRate.matchContent(24);
    await RefreshRate.preferDefault();
    expect(fake.calls.last.kind, PreferenceKind.high);
    await scope.release();
  });
}
