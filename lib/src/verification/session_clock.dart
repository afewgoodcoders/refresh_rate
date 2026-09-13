/// Monotonic session time anchored to UTC once. Wall-clock adjustments cannot
/// change measured durations; detected adjustments invalidate event coverage.
class SessionClock {
  /// Injectable clocks support deterministic clock-jump verification.
  SessionClock({DateTime Function()? wallClock, Duration Function()? elapsed})
      : _wall = wallClock ?? (() => DateTime.now().toUtc()),
        _elapsed = elapsed ?? (Stopwatch()..start()).elapsedDuration {
    _anchor = _wall();
    _initialElapsed = _elapsed();
  }
  final DateTime Function() _wall;
  final Duration Function() _elapsed;
  late final DateTime _anchor;
  late final Duration _initialElapsed;

  /// True once a wall-clock change exceeds the event-time bridge tolerance.
  bool discontinuity = false;

  /// Stable UTC-shaped timeline driven by elapsed time, not wall-clock changes.
  DateTime now() {
    final result = _anchor.add(_elapsed() - _initialElapsed);
    if (_wall().difference(result).inMilliseconds.abs() > 5) {
      discontinuity = true;
    }
    return result;
  }
}

extension on Stopwatch {
  Duration elapsedDuration() => elapsed;
}
