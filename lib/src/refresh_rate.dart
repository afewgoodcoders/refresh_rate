import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'diagnostics/configuration_doctor.dart';
import 'diagnostics/diagnostic_bundle.dart';
import 'telemetry/export_policy.dart';
import 'models/session_report.dart';
import 'dart:ui' as ui;
import 'models/rate_diagnostics.dart';
import 'control/rate_controller.dart';
import 'control/auto_controller.dart';
import 'package:flutter/widgets.dart';

import 'generated/refresh_rate_api.g.dart';
import 'models/display_info.dart';
import 'models/enums.dart';
import 'refresh_rate_api_adapter.dart';
import 'verification/overlay_controller.dart';
import 'verification/refresh_rate_session.dart';

/// Primary entry-point for controlling and monitoring the display refresh rate.
///
/// All members are static; this class cannot be instantiated.
///
/// ### Quick-start
/// ```dart
/// // Request a high refresh rate and inspect the submission result.
/// await RefreshRate.refresh();
/// final result = await RefreshRate.preferMax();
///
/// // Show an FPS overlay for debugging.
/// RefreshRate.showFPS();
/// ```
class RefreshRate {
  RefreshRate._();

  static RefreshRateApiAdapter _api = PigeonRefreshRateApiAdapter();
  static DisplayInfo _cachedInfo = DisplayInfo.fallback;
  static StreamController<DisplayInfo>? _changedController;
  static RateController? _controller;
  static RefreshRateLease? _manual;
  static int _readGeneration = 0;

  /// Shared preference arbiter used by this integration.
  static RateController get controller =>
      _controller ??= RateController(_submit);

  /// Broadcast decision history, separate from native display observations.
  static Stream<RefreshRateDecision> get onDecision => controller.decisions;

  /// Bounded recent package request decisions.
  static List<RefreshRateDecision> get decisionHistory => controller.history;

  /// Application preference before OS policy or capability constraints.
  static RatePreference get requestedPreference =>
      controller.effectivePreference;

  /// Supported operations, separate from observed outcomes.
  static Future<RefreshRateCapabilities> capabilities() async =>
      _api is RefreshRateRequestAdapter
          ? (_api as RefreshRateRequestAdapter).capabilities()
          : const RefreshRateCapabilities();

  /// Acquires a request that can release only its own preference.
  static RefreshRateLease request(RatePreference preference,
      {String owner = 'application', int priority = 100, Duration? duration}) {
    _ensureEvents();
    return controller.acquire(preference,
        owner: owner, priority: priority, duration: duration);
  }

  static Future<RateRequestResult> _submit(RatePreference preference) async {
    if (_api is RefreshRateRequestAdapter) {
      return (_api as RefreshRateRequestAdapter).submit(preference);
    }
    if (!await _api.isSupported()) {
      return RateRequestResult(
          status: RequestStatus.unsupported, preference: preference);
    }
    switch (preference.kind) {
      case PreferenceKind.system:
        await _api.preferDefault();
      case PreferenceKind.high:
        await _api.preferMax();
      case PreferenceKind.category:
        await _api.setCategory(preference.category!);
      case PreferenceKind.content:
        return RateRequestResult(
            status: RequestStatus.unsupported,
            preference: preference,
            message:
                'Legacy adapter cannot establish content compatibility/switch strategy.');
      case PreferenceKind.atLeast:
        return RateRequestResult(
            status: RequestStatus.unsupported, preference: preference);
    }
    return RateRequestResult(
        status: RequestStatus.submitted,
        preference: preference,
        backend: 'legacyPreference',
        scope: 'adapter');
  }

  static Future<RateRequestResult> _setManual(RatePreference preference) {
    final old = _manual;
    _manual = request(preference, owner: 'imperative');
    old?.release();
    // Releasing the former owner can coalesce the first submission.
    return controller.reconcile(reason: 'imperativePreference');
  }

  static final _flutterApi = _RefreshRateFlutterApiImpl();

  /// Enumerates displays known to Flutter without guessing native capabilities.
  static List<FlutterDisplaySnapshot> get displays {
    final now = DateTime.now().toUtc();
    return List.unmodifiable(WidgetsBinding.instance.platformDispatcher.displays
        .map((display) => FlutterDisplaySnapshot(
            id: display.id,
            widthPixels: display.size.width,
            heightPixels: display.size.height,
            devicePixelRatio: display.devicePixelRatio,
            reportedRefreshRate:
                display.refreshRate.isFinite && display.refreshRate > 0
                    ? display.refreshRate
                    : null,
            observedAt: now)));
  }

  /// Read source-qualified information for an optional explicit Flutter view.
  /// Flutter's reported display rate is not an observed engine FPS cap.
  static Future<RateDiagnostics> diagnostics({ui.FlutterView? view}) async {
    final info = await refresh();
    final native = _api is RefreshRateDiagnosticsAdapter
        ? await (_api as RefreshRateDiagnosticsAdapter).diagnostics()
        : <Object?, Object?>{};
    final now = DateTime.now().toUtc();
    RateObservation observation(double? value, String source, String scope,
            {int? count, Duration? window}) =>
        RateObservation(
            value: value != null && value.isFinite && value > 0 ? value : null,
            source: source,
            scope: scope,
            observedAt: now,
            sampleCount: count,
            window: window,
            unavailableReason:
                value == null ? 'No qualified source available' : null);
    return RateDiagnostics(
        requestedPreference: requestedPreference,
        nativeReportedDisplayHz: observation(
            info.nativeReportedDisplayHz,
            native['source'] as String? ?? 'nativeDisplayApi',
            native['displayId'] as String? ?? 'activeWindow'),
        engineReportedDisplayHz: observation(view?.display.refreshRate,
            'flutterDisplay', view?.viewId.toString() ?? 'unspecifiedView'),
        nativeCallbackCadenceHz: observation(
            (native['callbackHz'] as num?)?.toDouble() ??
                info.nativeCallbackCadenceHz,
            info.displayServer == 'web'
                ? 'requestAnimationFrame'
                : 'pluginDisplayLink',
            'observer',
            count: (native['sampleCount'] as num?)?.toInt(),
            window: native['windowUs'] is num
                ? Duration(microseconds: (native['windowUs'] as num).toInt())
                : null),
        displayModeMaxHz: observation(
            info.displayModeMaxHz, 'nativeDisplayCapability', 'activeWindow'),
        capabilities: await capabilities(),
        displayId: native['displayId'] as String?,
        nativeMetadata: Map.unmodifiable(native),
        suggestedNormalHz: (native['suggestedNormalHz'] as num?)?.toDouble(),
        suggestedHighHz: (native['suggestedHighHz'] as num?)?.toDouble());
  }

  /// Explicitly enables an observer for a bounded interval; it affects workload.
  static Future<RateObservation> observeNativeCadence(
      {Duration duration = const Duration(seconds: 1)}) async {
    if (duration < const Duration(milliseconds: 100) ||
        duration > const Duration(seconds: 5)) {
      throw ArgumentError('Observation duration must be 100ms–5s');
    }
    final data = _api is RefreshRateDiagnosticsAdapter
        ? await (_api as RefreshRateDiagnosticsAdapter)
            .observeNativeCadence(duration)
        : <Object?, Object?>{};
    return RateObservation(
        value: (data['callbackHz'] as num?)?.toDouble(),
        source: data['source'] as String? ?? 'unavailable',
        scope: 'pluginObserver',
        observedAt: DateTime.now().toUtc(),
        sampleCount: (data['sampleCount'] as num?)?.toInt(),
        window: data['windowUs'] is num
            ? Duration(microseconds: (data['windowUs'] as num).toInt())
            : duration,
        unavailableReason: data['callbackHz'] == null
            ? 'Observer unsupported or no active callbacks'
            : null);
  }

  /// Checks setup and backend limits using current qualified observations.
  static Future<ConfigurationReport> doctor({ui.FlutterView? view}) async {
    try {
      final data =
          await diagnostics(view: view).timeout(const Duration(seconds: 10));
      return ConfigurationReport.inspect(
          info: info,
          diagnostics: data,
          platform: kIsWeb ? 'web' : defaultTargetPlatform.name);
    } on MissingPluginException catch (error) {
      return _configurationFailure(error.message ?? 'Plugin is not registered');
    } on PlatformException catch (error) {
      return _configurationFailure(error.message ?? error.code);
    } on TimeoutException {
      return _configurationFailure('Native display query timed out');
    }
  }

  static ConfigurationReport _configurationFailure(String reason) {
    final missing = RateObservation(
        value: null,
        source: 'unavailable',
        scope: 'unknown',
        observedAt: DateTime.now().toUtc(),
        unavailableReason: reason);
    return ConfigurationReport(
        platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
        diagnostics: RateDiagnostics(
            requestedPreference: requestedPreference,
            nativeReportedDisplayHz: missing,
            engineReportedDisplayHz: missing,
            nativeCallbackCadenceHz: missing,
            displayModeMaxHz: missing,
            capabilities: const RefreshRateCapabilities(query: false)),
        findings: [
          ConfigurationFinding('queryFailed', reason,
              'Confirm plugin registration in this engine and query after binding/view attachment. Rebuild the app after native plugin changes.')
        ]);
  }

  /// Creates an explicitly shared, bounded diagnostic snapshot. Does not upload.
  static Future<DiagnosticBundle> diagnosticBundle(
      {ui.FlutterView? view,
      SessionReport? session,
      Map<String, String> environment = const {},
      String? reproduction,
      TelemetryExportPolicy? policy}) async {
    final decisions = decisionHistory;
    final configuration = await doctor(view: view);
    return DiagnosticBundle(
        configuration: configuration,
        session: session,
        decisions: decisions,
        environment: environment,
        reproduction: reproduction,
        policy: policy);
  }

  // ── Platform registration ──────────────────────────────────────

  /// Replaces the default platform API adapter.
  ///
  /// Called by platform-specific entrypoints (e.g. the web plugin) during
  /// framework initialisation.  Not intended for end-user consumption.
  static void registerAdapter(RefreshRateApiAdapter adapter) {
    _api = adapter;
    _readGeneration++;
  }

  // ── Test seam ──────────────────────────────────────────────────

  /// Replaces the platform API implementation with a test fake.
  ///
  /// Call [clearApiForTesting] in `tearDown` to restore the real adapter.
  @visibleForTesting
  static void setApiForTesting(RefreshRateApiAdapter api) {
    clearApiForTesting();
    _api = api;
  }

  /// Restores the real platform API and resets all internal state.
  ///
  /// Must be called in `tearDown` after [setApiForTesting].
  @visibleForTesting
  static void clearApiForTesting() {
    _controller?.dispose();
    _controller = null;
    _manual = null;
    _cachedInfo = DisplayInfo.fallback;
    _readGeneration++;
    _api = PigeonRefreshRateApiAdapter();
    _flutterApi._onChanged = null;
    RefreshRateFlutterApi.setUp(null);
    _changedController?.close();
    _changedController = null;
  }

  // ── Control ────────────────────────────────────────────────────

  /// Requests high refresh through the qualified backend, as [preferMax].
  /// Unsupported engine-control paths return an explicit unsupported result.
  static Future<RateRequestResult> enable() => preferMax();

  /// Removes the imperative owner's request; other owners remain active.
  static Future<RateRequestResult> disable() => preferDefault();

  /// Requests high refresh through the qualified platform backend.
  static Future<RateRequestResult> preferMax() =>
      _setManual(const RatePreference.high());

  /// Releases the imperative owner while preserving independent requests.
  static Future<RateRequestResult> preferDefault() {
    final old = _manual;
    _manual = null;
    return old?.release() ?? controller.reconcile(reason: 'clearImperative');
  }

  /// Submits exact content FPS and transition semantics where supported.
  static Future<RateRequestResult> matchContent(
    double fps, {
    FrameRateSwitchStrategy strategy = FrameRateSwitchStrategy.seamlessOnly,
  }) =>
      _setManual(RatePreference.content(fps, strategy: strategy));

  /// Requests minimum UI cadence where the backend supports it.
  static Future<RateRequestResult> preferAtLeast(double fps) =>
      _setManual(RatePreference.atLeast(fps));

  /// Acquires a timed high-rate lease without resetting unrelated requests.
  static Future<RateRequestResult> boost(Duration duration) =>
      request(const RatePreference.high(),
              owner: 'boost', priority: 200, duration: duration)
          .ready;

  /// Attach until explicitly disposed. Supports running/repeating/reverse animations.
  static VoidCallback boostDuring(AnimationController animation) {
    RefreshRateLease? lease;
    Timer? stopCheck;
    var disposed = false;
    void update() {
      if (disposed) return;
      if (animation.isAnimating) {
        lease ??= request(const RatePreference.high(),
            owner: 'animation', priority: 150);
        // AnimationController.stop() sends no value/status notification.
        // Poll only while this adapter owns a running animation; this timer
        // never schedules Flutter frames and ends as soon as it observes stop.
        stopCheck ??= Timer.periodic(const Duration(milliseconds: 32), (_) {
          if (!animation.isAnimating) {
            stopCheck?.cancel();
            stopCheck = null;
            lease?.release();
            lease = null;
          }
        });
      } else {
        stopCheck?.cancel();
        stopCheck = null;
        lease?.release();
        lease = null;
      }
    }

    void status(AnimationStatus _) => update();
    animation.addStatusListener(status);
    animation.addListener(update);
    update();
    return () {
      if (disposed) return;
      disposed = true;
      stopCheck?.cancel();
      animation.removeStatusListener(status);
      animation.removeListener(update);
      lease?.release();
      lease = null;
    };
  }

  /// Native category index: none, low, normal or high (0–3).
  static Future<RateRequestResult> category(RateCategory c) =>
      _setManual(RatePreference.category(c.index));

  /// Legacy native touch hint; use RefreshRateInteraction for owned interaction boosts.
  static Future<void> setTouchBoost(bool enabled) async =>
      await _api.setTouchBoost(enabled);

  /// Creates an opt-in policy driven by explicit activity adapters.
  static RefreshRateAutoController auto(
      {RefreshRatePolicy policy = RefreshRatePolicy.balanced,
      bool shadowMode = false,
      Duration idleDelay = const Duration(milliseconds: 800)}) {
    final result = RefreshRateAutoController(controller, onChanged,
        policy: policy,
        shadowMode: shadowMode,
        idleDelay: idleDelay,
        capabilities: const RefreshRateCapabilities(),
        initialInfo: info);
    result.initialize(() async {
      await refresh();
      final support = await capabilities();
      return (info, support);
    });
    return result;
  }

  /// Restores the native touch-boost state captured by this plugin.
  static Future<RateRequestResult> resetTouchBoost() async {
    if (_api is RefreshRateRequestAdapter) {
      return (_api as RefreshRateRequestAdapter).resetTouchBoost();
    }
    return const RateRequestResult(
        status: RequestStatus.unsupported, preference: RatePreference.system());
  }

  // ── Verification overlays ──────────────────────────────────────

  /// Shows a minimal live FPS counter overlay in the top-right corner.
  static void showFPS({double? expectedFps}) =>
      OverlayController.instance.showFPS(expectedFps: expectedFps);

  /// Shows a minimal live Hz readout overlay in the top-right corner.
  static void showHz() => OverlayController.instance.showHz();

  /// Shows the full diagnostic overlay (FPS + Hz + thermal state).
  static void showOverlay({double? expectedFps}) =>
      OverlayController.instance.showFull(expectedFps: expectedFps);

  /// Hides whatever verification overlay is currently visible.
  static void hideOverlay() => OverlayController.instance.hide();

  /// Whether the debug overlay is currently shown.
  static bool get isOverlayVisible => OverlayController.instance.isVisible;

  // ── Diagnostics ────────────────────────────────────────────────

  /// The most recently fetched [DisplayInfo] snapshot.
  ///
  /// Initialised to [DisplayInfo.fallback] (unknown rates)
  /// until [refresh] is awaited at least once.
  static DisplayInfo get info => _cachedInfo;

  /// Fetches fresh [DisplayInfo] from the platform and caches the result.
  ///
  /// Resolves with the updated [DisplayInfo] on success.
  static Future<DisplayInfo> refresh() async {
    _ensureEvents();
    final generation = ++_readGeneration;
    final msg = await _api.getDisplayInfo();
    final info = DisplayInfo.fromMessage(msg);
    if (generation == _readGeneration) {
      _cachedInfo = info;
      _changedController?.add(info);
    }
    return info;
  }

  /// Native display snapshots; subscription alone does not schedule Flutter frames.
  static Stream<DisplayInfo> get onChanged {
    _ensureEvents();
    return _changedController!.stream;
  }

  static void _ensureEvents() {
    if (_changedController != null) return;
    _changedController = StreamController<DisplayInfo>.broadcast();
    _flutterApi._onChanged = (info) {
      _readGeneration++;
      _cachedInfo = info;
      _changedController?.add(info);
    };
    RefreshRateFlutterApi.setUp(_flutterApi);
  }

  /// The application's ProMotion plist setting; null when unavailable.
  static bool? get isProMotionConfigured => _cachedInfo.iosProMotionEnabled;

  /// Whether the reported display maximum exceeds 60 Hz; null without evidence.
  /// Independent of whether this plugin can control the Flutter engine.
  static bool? get supportsHighRefreshRate =>
      _cachedInfo.supportsHighRefreshRate;

  /// Legacy setup convenience. Requires both the plist flag and a reported
  /// high-refresh display, but never guarantees engine or presentation cadence.
  @Deprecated(
      'Use isProMotionConfigured and supportsHighRefreshRate separately.')
  static bool get isProMotionReady =>
      isProMotionConfigured == true && supportsHighRefreshRate == true;

  /// Whether the device is currently in Low Power Mode.
  ///
  /// Defaults to `false` when the value cannot be determined.
  static bool get isLowPowerMode => _cachedInfo.isLowPowerMode ?? false;

  /// The current thermal state of the device.
  ///
  /// A state of [ThermalState.serious] or [ThermalState.critical] may cause
  /// the OS to clamp the refresh rate regardless of your requested value.
  static ThermalState get thermalState => _cachedInfo.thermalState;

  // ── Benchmark sessions ─────────────────────────────────────────

  /// Creates and starts a new FPS benchmark session named [name].
  ///
  /// Call [RefreshRateSession.end] when the scenario under test completes to
  /// receive a [SessionReport] with verdict, FPS stats, and bottleneck hints.
  static RefreshRateSession startSession(String name,
          {double? expectedFps,
          Duration finalizationTimeout = const Duration(milliseconds: 1100)}) =>
      RefreshRateSession.create(name, _cachedInfo,
          expectedFps: expectedFps,
          changes: onChanged,
          finalizationTimeout: finalizationTimeout);
}

class _RefreshRateFlutterApiImpl extends RefreshRateFlutterApi {
  void Function(DisplayInfo)? _onChanged;

  @override
  void onDisplayInfoChanged(DisplayInfoMessage info) {
    _onChanged?.call(DisplayInfo.fromMessage(info));
  }
}
