import 'dart:async';
import 'package:flutter/services.dart';
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
}

/// Production Pigeon queries and source-qualified method-channel controls.
class PigeonRefreshRateApiAdapter
    implements
        RefreshRateApiAdapter,
        RefreshRateRequestAdapter,
        RefreshRateDiagnosticsAdapter {
  static const _control = MethodChannel('refresh_rate/control');
  Future<Map<Object?, Object?>>? _observation;
  @override
  Future<Map<Object?, Object?>> diagnostics() async {
    try {
      return await _control.invokeMapMethod<Object?, Object?>('diagnostics') ??
          {};
    } on MissingPluginException {
      return {};
    }
  }

  @override
  Future<Map<Object?, Object?>> observeNativeCadence(Duration duration) =>
      _observation ??= _observe(duration);
  Future<Map<Object?, Object?>> _observe(Duration duration) async {
    try {
      await _control.invokeMethod<void>('startObservation');
      await Future<void>.delayed(duration);
      return await diagnostics();
    } on MissingPluginException {
      return {};
    } finally {
      try {
        await _control.invokeMethod<void>('stopObservation');
      } on MissingPluginException {/* Unsupported observer. */}
      _observation = null;
    }
  }

  @override
  Future<RefreshRateCapabilities> capabilities() async {
    try {
      final map =
          await _control.invokeMapMethod<Object?, Object?>('capabilities');
      return RefreshRateCapabilities.fromMap(map ?? {});
    } on MissingPluginException {
      return const RefreshRateCapabilities();
    }
  }

  @override
  Future<RateRequestResult> submit(RatePreference preference) async {
    try {
      final map = await _control.invokeMapMethod<Object?, Object?>(
          'request', preference.toMap());
      return RateRequestResult(
          preference: preference,
          status: RequestStatus.values.firstWhere(
              (s) => s.name == map?['status'],
              orElse: () => RequestStatus.unavailable),
          backend: map?['backend'] as String? ?? 'unavailable',
          scope: map?['scope'] as String? ?? 'unknown',
          message: map?['message'] as String?);
    } on MissingPluginException {
      return RateRequestResult(
          preference: preference,
          status: RequestStatus.unsupported,
          message: 'This platform has no qualified control backend.');
    }
  }

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
