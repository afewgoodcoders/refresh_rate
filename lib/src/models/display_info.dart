import '../generated/refresh_rate_api.g.dart';
import 'package:flutter/foundation.dart';
import 'enums.dart';

/// A snapshot of the current display configuration and device health.
///
/// Retrieve a fresh snapshot via [RefreshRate.refresh] or listen to
/// [RefreshRate.onChanged] for real-time updates.
class DisplayInfo {
  /// Legacy native reported Hz (web callback cadence); zero when unavailable.
  final double currentRate;

  /// Maximum reported capability in Hz; zero when unavailable.
  final double maxRate;

  /// Minimum reported mode rate in Hz; zero when unavailable.
  final double minRate;

  /// Reported compatible mode rates, not an exhaustive physical panel range.
  final List<double> supportedRates;

  /// Legacy VRR evidence; false also covers unknown. Prefer the nullable field.
  final bool isVariableRefreshRate;

  /// Nullable capability evidence; legacy isVariableRefreshRate collapses unknown.
  final bool? reportedVariableRefreshRate;

  /// Legacy engine-rate field; zero when the backend has no qualified source.
  final double engineTargetRate;

  /// Whether iOS ProMotion adaptive refresh is enabled for this app.
  ///
  /// `null` on non-iOS platforms.
  final bool? iosProMotionEnabled;

  /// The Android API level of the device.
  ///
  /// `null` on non-Android platforms.
  final int? androidApiLevel;

  /// Whether the device is in Low Power Mode.
  ///
  /// `null` when the platform does not expose this information.
  final bool? isLowPowerMode;

  /// The current thermal state of the device.
  final ThermalState thermalState;

  /// Whether the display supports an adaptive (variable) refresh rate.
  ///
  /// `null` when the platform does not expose this information.
  final bool? hasAdaptiveRefreshRate;

  /// The name of the display server in use (Linux only, e.g. `"wayland"`).
  ///
  /// `null` on non-Linux platforms.
  final String? displayServer;

  /// The number of monitors connected to the device (desktop platforms only).
  ///
  /// `null` on mobile platforms.
  final int? monitorCount;

  /// Time this native snapshot arrived in Dart (not hardware event time).
  final DateTime? observedAt;

  /// OS-reported display information; null when no qualified value exists.
  double? get nativeReportedDisplayHz =>
      displayServer == 'web' ? null : _valid(currentRate);

  /// Observer callback cadence, never Flutter presentation FPS.
  double? get nativeCallbackCadenceHz =>
      displayServer == 'web' ? _valid(currentRate) : null;

  /// Maximum reported capability for the relevant native display scope.
  double? get displayModeMaxHz => _valid(maxRate);

  /// Flutter display information; not an observed engine frame-rate cap.
  double? get engineReportedDisplayHz => _valid(engineTargetRate);

  /// Whether no snapshot exists or the last read is older than five seconds.
  bool get isStale =>
      observedAt == null ||
      DateTime.now().difference(observedAt!) > const Duration(seconds: 5);
  static double? _valid(double? value) =>
      value != null && value.isFinite && value > 0 ? value : null;

  /// Creates a new [DisplayInfo] snapshot.
  const DisplayInfo({
    required this.currentRate,
    required this.maxRate,
    required this.minRate,
    required this.supportedRates,
    required this.isVariableRefreshRate,
    required this.engineTargetRate,
    this.iosProMotionEnabled,
    this.androidApiLevel,
    this.isLowPowerMode,
    required this.thermalState,
    this.hasAdaptiveRefreshRate,
    this.displayServer,
    this.monitorCount,
    this.observedAt,
    this.reportedVariableRefreshRate,
  });

  /// Creates a [DisplayInfo] from a platform [DisplayInfoMessage].
  factory DisplayInfo.fromMessage(DisplayInfoMessage msg) {
    return DisplayInfo(
      currentRate: _valid(msg.currentRate) ?? 0.0,
      maxRate: _valid(msg.maxRate) ?? 0.0,
      minRate: _valid(msg.minRate) ?? 0.0,
      supportedRates: List.unmodifiable(msg.supportedRates
              ?.whereType<double>()
              .where((rate) => _valid(rate) != null)
              .toSet()
              .toList() ??
          const <double>[]),
      isVariableRefreshRate: msg.isVariableRefreshRate ?? false,
      engineTargetRate: _valid(msg.engineTargetRate) ?? 0.0,
      iosProMotionEnabled: msg.iosProMotionEnabled,
      androidApiLevel: msg.androidApiLevel,
      isLowPowerMode: msg.isLowPowerMode,
      thermalState: ThermalState.fromIndex(msg.thermalStateIndex),
      hasAdaptiveRefreshRate: msg.hasAdaptiveRefreshRate,
      displayServer: msg.displayServer,
      monitorCount: msg.monitorCount,
      observedAt: DateTime.now().toUtc(),
      reportedVariableRefreshRate: msg.isVariableRefreshRate,
    );
  }

  /// A safe fallback [DisplayInfo] used before the first [RefreshRate.refresh]
  /// call completes. Legacy numeric fields use zero for unavailable; prefer nullable observation getters.
  static const DisplayInfo fallback = DisplayInfo(
    currentRate: 0.0,
    maxRate: 0.0,
    minRate: 0.0,
    supportedRates: [],
    isVariableRefreshRate: false,
    engineTargetRate: 0.0,
    thermalState: ThermalState.unknown,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DisplayInfo &&
          currentRate == other.currentRate &&
          maxRate == other.maxRate &&
          minRate == other.minRate &&
          isVariableRefreshRate == other.isVariableRefreshRate &&
          engineTargetRate == other.engineTargetRate &&
          thermalState == other.thermalState &&
          isLowPowerMode == other.isLowPowerMode &&
          listEquals(supportedRates, other.supportedRates) &&
          iosProMotionEnabled == other.iosProMotionEnabled &&
          androidApiLevel == other.androidApiLevel &&
          hasAdaptiveRefreshRate == other.hasAdaptiveRefreshRate &&
          displayServer == other.displayServer &&
          monitorCount == other.monitorCount &&
          reportedVariableRefreshRate == other.reportedVariableRefreshRate;

  @override
  int get hashCode => Object.hash(
      currentRate,
      maxRate,
      minRate,
      isVariableRefreshRate,
      engineTargetRate,
      thermalState,
      isLowPowerMode,
      Object.hashAll(supportedRates),
      iosProMotionEnabled,
      androidApiLevel,
      hasAdaptiveRefreshRate,
      displayServer,
      monitorCount,
      reportedVariableRefreshRate);

  @override
  String toString() =>
      'DisplayInfo(currentRate: ${currentRate}Hz, maxRate: ${maxRate}Hz, '
      'thermalState: $thermalState, isLowPowerMode: $isLowPowerMode)';
}
