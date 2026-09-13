import 'dart:async';
import 'control/rate_controller.dart';

import 'generated/refresh_rate_api.g.dart';

/// Abstract interface for the host API, used as the test seam.
///
/// The real implementation ([PigeonRefreshRateApiAdapter]) delegates to the
/// pigeon-generated [RefreshRateHostApi]. Tests implement this interface
/// directly with synchronous fakes — no await required.
abstract class RefreshRateApiAdapter {
  /// Fetches the latest display configuration.
  FutureOr<DisplayInfoMessage> getDisplayInfo();

  /// Enables High Refresh Rate overrides.
  FutureOr<void> enable();

  /// Disables High Refresh Rate overrides.
  FutureOr<void> disable();

  /// Requests the highest possible display refresh rate.
  FutureOr<void> preferMax();

  /// Resets to the system default refresh rate.
  FutureOr<void> preferDefault();

  /// Attempts to set the display refresh rate to match [fps].
  FutureOr<void> matchContent(double fps);

  /// Temporarily boosts the refresh rate for [durationMs].
  FutureOr<void> boost(int durationMs);

  /// Sets the refresh rate based on a given category.
  FutureOr<void> setCategory(int categoryIndex);

  /// Enables or disables automatic refresh rate boost on touch interactions.
  FutureOr<void> setTouchBoost(bool enabled);

  /// Checks whether the refresh rate overrides are supported by the platform.
  FutureOr<bool> isSupported();
}

/// Production implementation that delegates to the pigeon-generated channel.
abstract interface class RefreshRateDiagnosticsAdapter {
  /// Reads native metadata without treating callback cadence as display capability.
  Future<Map<Object?, Object?>> diagnostics();

  /// Enables a callback observer for a bounded interval, then stops it.
  Future<Map<Object?, Object?>> observeNativeCadence(Duration duration);
}

/// Optional adapter contract for qualified control submissions.
abstract interface class RefreshRateRequestAdapter {
  /// Backend submission function; errors become failed request results.
  Future<RateRequestResult> submit(RatePreference preference);

  /// Supported operations, separate from observed outcomes.
  Future<RefreshRateCapabilities> capabilities();

  /// Restores the owned native touch preference.
  Future<RateRequestResult> resetTouchBoost();
}

/// Every native operation is transported through generated Pigeon bindings.
class PigeonRefreshRateApiAdapter
    implements
        RefreshRateApiAdapter,
        RefreshRateRequestAdapter,
        RefreshRateDiagnosticsAdapter {
  Future<Map<Object?, Object?>>? _observation;

  static PreferenceMessage _message(RatePreference preference) =>
      PreferenceMessage(
        kind: NativePreferenceKind.values.byName(preference.kind.name),
        fps: preference.fps,
        category: preference.category,
        strategy: NativeSwitchStrategy.values.byName(preference.strategy.name),
      );

  static RateRequestResult _result(
          RequestResultMessage message, RatePreference preference) =>
      RateRequestResult(
        preference: preference,
        status: message.status == null
            ? RequestStatus.unavailable
            : RequestStatus.values.byName(message.status!.name),
        backend: message.backend ?? 'unavailable',
        scope: message.scope ?? 'unknown',
        message: message.message,
      );

  @override
  Future<Map<Object?, Object?>> diagnostics() async {
    final data = await _pigeon.getDiagnostics();
    final last = data.lastNativeRequest;
    return {
      'source': data.source,
      'displayId': data.displayId,
      'scope': data.scope,
      'currentHz': data.currentHz,
      'maximumHz': data.maximumHz,
      'suggestedNormalHz': data.suggestedNormalHz,
      'suggestedHighHz': data.suggestedHighHz,
      'callbackHz': data.callbackHz,
      'expectedCallbackHz': data.expectedCallbackHz,
      'sampleCount': data.sampleCount,
      'windowUs': data.windowUs,
      'activityAttached': data.activityAttached,
      'surfaceAvailable': data.surfaceAvailable,
      'touchBoostEnabled': data.touchBoostEnabled,
      'targetGeneration': data.targetGeneration,
      'submissionCount': data.submissionCount,
      'lastNativeRequest': last == null
          ? null
          : {
              'status': last.status?.name,
              'backend': last.backend,
              'scope': last.scope,
              'message': last.message,
              'observedAtMs': last.observedAtMs,
              'preference': last.preference == null
                  ? null
                  : {
                      'kind': last.preference!.kind?.name,
                      'fps': last.preference!.fps,
                      'category': last.preference!.category,
                      'strategy': last.preference!.strategy?.name,
                    },
            },
    };
  }

  @override
  Future<Map<Object?, Object?>> observeNativeCadence(Duration duration) =>
      _observation ??= _observe(duration);
  Future<Map<Object?, Object?>> _observe(Duration duration) async {
    var started = false;
    try {
      started = await _pigeon.startObservation();
      if (!started) return {};
      await Future<void>.delayed(duration);
      return await diagnostics();
    } finally {
      try {
        if (started) await _pigeon.stopObservation();
      } finally {
        _observation = null;
      }
    }
  }

  @override
  Future<RefreshRateCapabilities> capabilities() async {
    final data = await _pigeon.getCapabilities();
    return RefreshRateCapabilities(
        query: data.query == true,
        surfaceVoting: data.surfaceVoting == true,
        windowPreferences: data.windowPreferences == true,
        categoryHints: data.categoryHints == true,
        engineControl: data.engineControl == true,
        presentationObservation: data.presentationObservation == true,
        atLeast: data.atLeast == true,
        contentMatching: data.contentMatching == true,
        touchBoost: data.touchBoost == true,
        callbackObservation: data.callbackObservation == true);
  }

  @override
  Future<RateRequestResult> submit(RatePreference preference) async =>
      _result(await _pigeon.submitPreference(_message(preference)), preference);

  @override
  Future<RateRequestResult> resetTouchBoost() async =>
      _result(await _pigeon.resetTouchBoost(), const RatePreference.system());

  final RefreshRateHostApi _pigeon;

  /// Creates a new [PigeonRefreshRateApiAdapter].
  PigeonRefreshRateApiAdapter() : _pigeon = RefreshRateHostApi();

  @override
  Future<DisplayInfoMessage> getDisplayInfo() => _pigeon.getDisplayInfo();

  @override
  Future<void> enable() => _pigeon.enable();

  @override
  Future<void> disable() => _pigeon.disable();

  @override
  Future<void> preferMax() => _pigeon.preferMax();

  @override
  Future<void> preferDefault() => _pigeon.preferDefault();

  @override
  Future<void> matchContent(double fps) => _pigeon.matchContent(fps);

  @override
  Future<void> boost(int durationMs) => _pigeon.boost(durationMs);

  @override
  Future<void> setCategory(int categoryIndex) =>
      _pigeon.setCategory(categoryIndex);

  @override
  Future<void> setTouchBoost(bool enabled) => _pigeon.setTouchBoost(enabled);

  @override
  Future<bool> isSupported() => _pigeon.isSupported();
}
