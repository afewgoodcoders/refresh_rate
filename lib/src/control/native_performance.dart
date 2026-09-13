import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'rate_controller.dart';

/// A qualified Android thermal-headroom observation. Zero is valid; null means
/// unavailable. Values near 1 indicate forecast severe thermal pressure.
class ThermalHeadroomObservation {
  /// Decodes backend evidence without substituting a temperature or threshold.
  ThermalHeadroomObservation.fromMap(Map<Object?, Object?> data)
      : value = data['value'] is num && (data['value'] as num).isFinite
            ? (data['value'] as num).toDouble()
            : null,
        forecastSeconds = (data['forecastSeconds'] as num?)?.toInt() ?? 0,
        observedAt = data['observedAtMs'] is num
            ? DateTime.fromMillisecondsSinceEpoch(
                (data['observedAtMs'] as num).toInt(),
                isUtc: true)
            : null,
        cached = data['cached'] == true,
        unavailableReason = data['unavailableReason'] as String?;

  /// Forecast thermal-envelope usage, not degrees or CPU utilization.
  final double? value;

  /// Requested forecast horizon; backend may need warmup before forecasting.
  final int forecastSeconds;

  /// Actual collection time, unchanged for a cached observation.
  final DateTime? observedAt;

  /// Whether native polling returned an existing reading.
  final bool cached;

  /// Explicit missing-source or rate-limit explanation.
  final String? unavailableReason;

  /// Structured source-qualified evidence.
  Map<String, Object?> toMap() => {
        'source': 'androidThermalHeadroom',
        'value': value,
        'forecastSeconds': forecastSeconds,
        'observedAt': observedAt?.toIso8601String(),
        'cached': cached,
        'unavailableReason': unavailableReason
      };
}

/// Outcome for a native workload preference independent of refresh-rate votes.
class PerformanceRequestResult {
  /// Submission does not establish a performance or energy improvement.
  PerformanceRequestResult.fromMap(Map<Object?, Object?> data)
      : status = RequestStatus.values.firstWhere(
            (s) => s.name == data['status'],
            orElse: () => RequestStatus.unavailable),
        message = data['message'] as String?,
        backend = data['backend'] as String? ?? 'unavailable';

  /// Native operation outcome.
  final RequestStatus status;

  /// Backend explanation, including unsupported semantics.
  final String? message;

  /// Mechanism actually invoked.
  final String backend;
}

/// Owns one sustained-performance request. Android exposes no public getter for
/// prior sustained state: callers must supply their application's known state.
class SustainedPerformanceLease {
  SustainedPerformanceLease._(
      this._id, bool previousEnabled, Duration? duration) {
    ready = NativePerformance._call(
            'acquireSustained', {'id': _id, 'previousEnabled': previousEnabled})
        .then(PerformanceRequestResult.fromMap);
    if (duration != null) _timer = Timer(duration, release);
  }
  final String _id;
  Timer? _timer;
  Future<PerformanceRequestResult>? _release;

  /// Awaitable submission outcome; unsupported is explicit on other platforms.
  late final Future<PerformanceRequestResult> ready;

  /// Releases only this owner. The final owner restores the declared baseline.
  Future<PerformanceRequestResult> release() {
    _timer?.cancel();
    return _release ??= (() async {
      await ready;
      return PerformanceRequestResult.fromMap(
          await NativePerformance._call('releaseSustained', {'id': _id}));
    })();
  }
}

/// Internal channel facade; public entry points are on RefreshRate.
abstract class NativePerformance {
  static const _channel = MethodChannel('refresh_rate/control');
  static int _nextId = 0;
  static Future<Map<Object?, Object?>> _call(
      String method, Map<String, Object?> args) async {
    try {
      return await _channel
              .invokeMapMethod<Object?, Object?>(method, args)
              .timeout(const Duration(seconds: 5)) ??
          {};
    } on MissingPluginException {
      return {
        'status': 'unsupported',
        'unavailableReason': 'No supported native performance backend'
      };
    } on TimeoutException {
      return {
        'status': 'failed',
        'message': 'Timed out; native completion is unconfirmed',
        'unavailableReason': 'Native request timed out'
      };
    } on PlatformException catch (error) {
      return {
        'status': 'failed',
        'message': error.message,
        'unavailableReason': error.message ?? error.code
      };
    }
  }

  /// Native polling is also bounded across concurrent consumers.
  static Future<ThermalHeadroomObservation> thermalHeadroom(
      {int forecastSeconds = 10}) async {
    if (forecastSeconds < 0 || forecastSeconds > 60) {
      throw ArgumentError.value(forecastSeconds, 'forecastSeconds');
    }
    final data =
        await _call('thermalHeadroom', {'forecastSeconds': forecastSeconds});
    return ThermalHeadroomObservation.fromMap({
      ...data,
      'forecastSeconds': data['forecastSeconds'] ?? forecastSeconds
    });
  }

  /// Requests sustained consistency; never described as maximum performance.
  static SustainedPerformanceLease sustained(
      {required bool previousEnabled, Duration? duration}) {
    if (duration != null &&
        (duration <= Duration.zero || duration > const Duration(days: 1))) {
      throw ArgumentError.value(duration, 'duration');
    }
    return SustainedPerformanceLease._(
        'sustained-${++_nextId}', previousEnabled, duration);
  }

  /// Restores only the native touch boost state owned by this plugin.
  static Future<PerformanceRequestResult> resetTouchBoost() async =>
      PerformanceRequestResult.fromMap(await _call('resetTouchBoost', {}));
}

/// Opt-in foreground-only thermal polling, at most once every ten seconds.
class ThermalHeadroomMonitor {
  /// Starts a bounded observer; dispose when the application no longer needs it.
  ThermalHeadroomMonitor(
      {this.forecastSeconds = 10,
      this.interval = const Duration(seconds: 10)}) {
    if (forecastSeconds < 0 ||
        forecastSeconds > 60 ||
        interval < const Duration(seconds: 10)) {
      throw ArgumentError('Invalid thermal observation interval/horizon');
    }
    _lifecycle = AppLifecycleListener(onStateChange: (state) {
      _foreground = state == AppLifecycleState.resumed;
      _timer?.cancel();
      if (_foreground) _poll();
    });
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    scheduleMicrotask(_poll);
  }

  /// Forecast horizon in seconds.
  final int forecastSeconds;

  /// Minimum interval between polls.
  final Duration interval;
  final _events = StreamController<ThermalHeadroomObservation>.broadcast();
  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  bool _disposed = false, _foreground = true, _inFlight = false;

  /// Latest qualified observation, including unavailable/cached evidence.
  ThermalHeadroomObservation? latest;

  /// Events stop in the background and after disposal.
  Stream<ThermalHeadroomObservation> get observations => _events.stream;
  Future<void> _poll() async {
    if (_disposed || !_foreground || _inFlight) return;
    _inFlight = true;
    final value = await NativePerformance.thermalHeadroom(
        forecastSeconds: forecastSeconds);
    _inFlight = false;
    if (_disposed || !_foreground) return;
    latest = value;
    _events.add(value);
    _timer?.cancel();
    _timer = Timer(interval, _poll);
  }

  /// Cancels future work. A completed in-flight reply is discarded.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _lifecycle?.dispose();
    unawaited(_events.close());
  }
}
