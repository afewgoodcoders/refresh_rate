import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Browser callback cadence; never physical panel capability or presented FPS.
class RafHzDetector {
  static Future<double?>? _pending;
  static void Function()? _cancel;

  /// Number of records represented by the measurement.
  static int sampleCount = 0;

  /// Difference between sampled 95th and 5th interval percentiles.
  static double? dispersionMs;

  /// Duration covered by the most recent successful callback measurement.
  static Duration? measurementWindow;

  /// UTC time when the observation was collected or received.
  static DateTime? observedAt;

  /// Cancels the shared in-flight callback measurement and releases listeners.
  static void cancel() => _cancel?.call();

  /// Measures raw browser callback cadence with visibility and timeout bounds.
  static Future<double?> measure(
      {Duration timeout = const Duration(seconds: 5)}) {
    if (_pending != null) return _pending!;
    if (timeout <= Duration.zero || timeout > const Duration(seconds: 30)) {
      throw ArgumentError('Invalid timeout');
    }
    if (web.document.hidden) return Future.value(null);
    final completer = Completer<double?>();
    _pending = completer.future;
    sampleCount = 0;
    dispersionMs = null;
    measurementWindow = null;
    observedAt = null;
    final stamps = <double>[];
    var requestId = 0;
    Timer? timer;
    late final JSFunction callback, visibility;
    void finish(double? rate) {
      if (completer.isCompleted) return;
      web.window.cancelAnimationFrame(requestId);
      timer?.cancel();
      web.document.removeEventListener('visibilitychange', visibility);
      _pending = null;
      _cancel = null;
      if (rate != null) observedAt = DateTime.now().toUtc();
      completer.complete(rate);
    }

    visibility = ((web.Event _) {
      if (web.document.hidden) finish(null);
    }).toJS;
    callback = ((JSNumber timestamp) {
      if (completer.isCompleted) return;
      final ts = timestamp.toDartDouble;
      if (!ts.isFinite || (stamps.isNotEmpty && ts <= stamps.last)) {
        finish(null);
        return;
      }
      stamps.add(ts);
      if (stamps.length >= 121) {
        final intervals = [
          for (var i = 1; i < stamps.length; i++) stamps[i] - stamps[i - 1]
        ]..sort();
        final median = (intervals[59] + intervals[60]) / 2;
        sampleCount = intervals.length;
        dispersionMs = intervals[113] - intervals[5];
        measurementWindow = Duration(
            microseconds: ((stamps.last - stamps.first) * 1000).round());
        finish(median > 0 ? 1000 / median : null);
      } else {
        requestId = web.window.requestAnimationFrame(callback);
      }
    }).toJS;
    _cancel = () => finish(null);
    web.document.addEventListener('visibilitychange', visibility);
    timer = Timer(timeout, () => finish(null));
    requestId = web.window.requestAnimationFrame(callback);
    return completer.future;
  }
}
