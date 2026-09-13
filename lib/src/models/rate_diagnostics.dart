import '../control/rate_controller.dart';

/// A nullable observation with its actual source and observation scope.
class RateObservation {
  /// Creates a [RateObservation] with the supplied configuration.
  const RateObservation(
      {required this.value,
      required this.source,
      required this.scope,
      required this.observedAt,
      this.sampleCount,
      this.window,
      this.unavailableReason});

  /// Finite source measurement, or null when unavailable.
  final double? value;

  /// API or collector that produced this observation.
  final String source;

  /// Window, surface, engine or observer scope of this value.
  final String scope;

  /// UTC time when the observation was collected or received.
  final DateTime observedAt;

  /// Number of records represented by the measurement.
  final int? sampleCount;

  /// Time interval represented by the observation.
  final Duration? window;

  /// Why no qualified measurement is available.
  final String? unavailableReason;

  /// Whether the observation contains a usable numeric value.
  bool get available => value != null;

  /// Serializes this value to a JSON-compatible map.
  Map<String, Object?> toMap() => {
        'value': value,
        'source': source,
        'scope': scope,
        'observedAt': observedAt.toIso8601String(),
        'sampleCount': sampleCount,
        'windowUs': window?.inMicroseconds,
        'unavailableReason': unavailableReason
      };
}

/// Keeps display information, engine information and observer cadence distinct.
class RateDiagnostics {
  /// Creates a [RateDiagnostics] with the supplied configuration.
  const RateDiagnostics(
      {required this.requestedPreference,
      required this.nativeReportedDisplayHz,
      required this.engineReportedDisplayHz,
      required this.nativeCallbackCadenceHz,
      required this.displayModeMaxHz,
      required this.capabilities,
      this.displayId,
      this.nativeMetadata = const {},
      this.suggestedNormalHz,
      this.suggestedHighHz});

  /// Application preference before OS policy or capability constraints.
  final RatePreference requestedPreference;

  /// OS-reported display information; null when no qualified value exists.
  final RateObservation nativeReportedDisplayHz;

  /// Flutter display information; not an observed engine frame-rate cap.
  final RateObservation engineReportedDisplayHz;

  /// Observer callback cadence, never Flutter presentation FPS.
  final RateObservation nativeCallbackCadenceHz;

  /// Maximum reported capability for the relevant native display scope.
  final RateObservation displayModeMaxHz;

  /// Supported operations, separate from observed outcomes.
  final RefreshRateCapabilities capabilities;

  /// Native display identity when exposed by the backend.
  final String? displayId;

  /// Backend-specific attachment and owned-request evidence.
  final Map<Object?, Object?> nativeMetadata;

  /// Android API 36 display-defined normal cadence, when available.
  final double? suggestedNormalHz;

  /// Android API 36 display-defined high cadence, when available.
  final double? suggestedHighHz;

  /// Unavailable: Flutter timing records alone do not establish presentation FPS.
  double? get presentedFps => null;

  /// Complete source-qualified snapshot, including operation capabilities.
  Map<String, Object?> toMap() => {
        'requestedPreference': requestedPreference.toMap(),
        'nativeReportedDisplayHz': nativeReportedDisplayHz.toMap(),
        'engineReportedDisplayHz': engineReportedDisplayHz.toMap(),
        'nativeCallbackCadenceHz': nativeCallbackCadenceHz.toMap(),
        'displayModeMaxHz': displayModeMaxHz.toMap(),
        'capabilities': capabilities.toMap(),
        'displayId': displayId,
        'nativeMetadata': nativeMetadata,
        'suggestedNormalHz': suggestedNormalHz,
        'suggestedHighHz': suggestedHighHz,
        'presentedFps': null,
      };
}

/// Display enumeration reported by Flutter, separate from hardware VRR evidence.
class FlutterDisplaySnapshot {
  /// Creates a display-scoped engine information snapshot.
  const FlutterDisplaySnapshot(
      {required this.id,
      required this.widthPixels,
      required this.heightPixels,
      required this.reportedRefreshRate,
      required this.devicePixelRatio,
      required this.observedAt});

  /// Flutter display identity, which is not necessarily a native monitor ID.
  final int id;

  /// Physical display dimensions reported by the engine.
  final double widthPixels, heightPixels;

  /// Engine-reported refresh information; not instantaneous presented FPS.
  final double? reportedRefreshRate;

  /// Display pixel ratio reported by Flutter.
  final double devicePixelRatio;

  /// Time the snapshot was read.
  final DateTime observedAt;
}
