import 'dart:async';

import '../control/rate_controller.dart';
import '../generated/refresh_rate_api.g.dart';
import '../refresh_rate_api_adapter.dart';
import 'raf_hz_detector.dart';

/// Web implementation of [RefreshRateApiAdapter].
///
/// Uses `requestAnimationFrame` intervals to measure browser callback cadence.
/// This does not establish the physical display's refresh rate.
/// Legacy control methods are graceful no-ops because
/// browsers own their vsync scheduling and expose no API to change it.
class WebRefreshRateApiAdapter
    implements
        RefreshRateApiAdapter,
        RefreshRateDiagnosticsAdapter,
        RefreshRateRequestAdapter {
  @override
  Future<RefreshRateCapabilities> capabilities() async =>
      const RefreshRateCapabilities(callbackObservation: true);

  @override
  Future<RateRequestResult> submit(RatePreference preference) async =>
      RateRequestResult(
        status: preference.kind == PreferenceKind.system
            ? RequestStatus.submitted
            : RequestStatus.unsupported,
        preference: preference,
        backend: 'browser',
        scope: 'document',
        message: 'The browser owns refresh scheduling.',
      );

  @override
  Future<RateRequestResult> resetTouchBoost() async => const RateRequestResult(
      status: RequestStatus.unsupported,
      preference: RatePreference.system(),
      backend: 'browser',
      scope: 'document',
      message: 'Browser touch boost is not configurable.');

  @override
  Future<Map<Object?, Object?>> diagnostics() async => {
        'source': 'requestAnimationFrame',
        'callbackHz': _lastMeasuredRate,
        'sampleCount': RafHzDetector.sampleCount,
        'windowUs': RafHzDetector.measurementWindow?.inMicroseconds,
        'dispersionMs': RafHzDetector.dispersionMs,
      };
  @override
  Future<Map<Object?, Object?>> observeNativeCadence(Duration duration) async {
    _lastMeasuredRate = await RafHzDetector.measure(timeout: duration);
    return diagnostics();
  }

  double? _lastMeasuredRate;

  @override
  Future<DisplayInfoMessage> getDisplayInfo() async {
    _lastMeasuredRate = await RafHzDetector.measure();
    return DisplayInfoMessage(
      currentRate: _lastMeasuredRate,
      // Browsers don't expose max/min/supported rates.
      maxRate: null,
      minRate: null,
      supportedRates: null,
      isVariableRefreshRate: null,
      engineTargetRate: null,
      // Apple / Android specific — not applicable on web.
      iosProMotionEnabled: null,
      androidApiLevel: null,
      // No battery/thermal APIs on web.
      isLowPowerMode: null,
      thermalStateIndex: null,
      hasAdaptiveRefreshRate: null,
      displayServer: 'web',
      monitorCount: null,
    );
  }

  /// No-op — browsers manage their own vsync scheduling.
  @override
  FutureOr<void> enable() {}

  /// No-op — browsers manage their own vsync scheduling.
  @override
  FutureOr<void> disable() {}

  /// No-op — cannot request max rate on web.
  @override
  FutureOr<void> preferMax() {}

  /// No-op — cannot change rate preference on web.
  @override
  FutureOr<void> preferDefault() {}

  /// No-op — cannot match content frame rate on web.
  @override
  FutureOr<void> matchContent(double fps) {}

  /// No-op — cannot boost refresh rate on web.
  @override
  FutureOr<void> boost(int durationMs) {}

  /// No-op — rate categories are Android-specific.
  @override
  FutureOr<void> setCategory(int categoryIndex) {}

  /// No-op — touch boost is Android-specific.
  @override
  FutureOr<void> setTouchBoost(bool enabled) {}

  /// Web supports querying the refresh rate but not controlling it.
  @override
  FutureOr<bool> isSupported() => false;
}
