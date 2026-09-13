import 'dart:collection';

/// Consecutive irregular intervals within one explicitly budgeted workload.
/// This records Flutter cadence, not physical presentation misses.
class StutterEpisode {
  /// Creates a completed or interrupted episode.
  const StutterEpisode(
      {required this.startedAt,
      required this.endedAt,
      required this.badIntervals,
      required this.longestIntervalUs,
      required this.durationUs,
      required this.recovered});

  /// Event-time boundaries, including the interval that establishes recovery.
  final DateTime startedAt, endedAt;

  /// Number of consecutive intervals over 1.5 times the workload budget.
  final int badIntervals;

  /// Longest observed inter-frame interval in microseconds.
  final int longestIntervalUs;

  /// Time from the first bad interval's start to recovery or interruption.
  final int durationUs;

  /// False when a boundary or session end prevented observing recovery.
  final bool recovered;

  /// Structured cadence evidence with explicit units.
  Map<String, Object?> toMap() => {
        'start': startedAt.toIso8601String(),
        'end': endedAt.toIso8601String(),
        'badIntervals': badIntervals,
        'longestIntervalMs': longestIntervalUs / 1000,
        'durationMs': durationUs / 1000,
        'recovered': recovered,
      };
}

/// Bounded episode history with exact whole-session counts.
class StutterTracker {
  /// Limits retained episodes; aggregate counts survive eviction.
  StutterTracker({this.capacity = 100}) {
    if (capacity < 1) throw ArgumentError.value(capacity, 'capacity');
  }

  /// Maximum retained episodes.
  final int capacity;
  final _episodes = Queue<StutterEpisode>();
  DateTime? _start, _last;
  int _bad = 0, _duration = 0, _longest = 0;

  /// Total episodes, including an unfinished current episode.
  int episodeCount = 0;

  /// Number of explicitly budgeted intervals lasting at least 100 ms.
  int longStallCount = 0;

  /// Longest budgeted interval observed across the whole session.
  int longestIntervalUs = 0;

  /// Largest run of consecutive bad intervals.
  int maxConsecutiveBadIntervals = 0;

  /// Completed episode evidence dropped from bounded history.
  int droppedEpisodes = 0;

  StutterEpisode _snapshot(bool recovered) => StutterEpisode(
      startedAt: _start!,
      endedAt: _last!,
      badIntervals: _bad,
      longestIntervalUs: _longest,
      durationUs: _duration,
      recovered: recovered);

  /// Latest completed episodes plus the active episode, if any.
  List<StutterEpisode> get episodes => List.unmodifiable([
        ..._episodes
            .skip(_start != null && _episodes.length == capacity ? 1 : 0),
        if (_start != null) _snapshot(false),
      ]);

  /// Adds one interval. Call [interrupt] at target/lifecycle boundaries.
  void add(
      {required int intervalUs,
      required double targetHz,
      required DateTime start,
      required DateTime end}) {
    if (intervalUs > longestIntervalUs) longestIntervalUs = intervalUs;
    if (intervalUs > 1500000 / targetHz) {
      if (intervalUs >= 100000) longStallCount++;
      if (_start == null) {
        _start = start;
        episodeCount++;
      }
      _last = end;
      _duration += intervalUs;
      _bad++;
      if (intervalUs > _longest) _longest = intervalUs;
      if (_bad > maxConsecutiveBadIntervals) maxConsecutiveBadIntervals = _bad;
    } else if (_start != null) {
      _last = end;
      _duration += intervalUs;
      _finish(true);
    }
  }

  void _finish(bool recovered) {
    if (_start == null) return;
    if (_episodes.length == capacity) {
      _episodes.removeFirst();
      droppedEpisodes++;
    }
    _episodes.add(_snapshot(recovered));
    _start = _last = null;
    _bad = _duration = _longest = 0;
  }

  /// Ends the active episode without claiming recovery.
  void interrupt() => _finish(false);

  /// Resets all retained and aggregate state.
  void clear() {
    _episodes.clear();
    _start = _last = null;
    _bad = _duration = _longest = 0;
    episodeCount = longStallCount = longestIntervalUs = 0;
    maxConsecutiveBadIntervals = droppedEpisodes = 0;
  }

  /// Bounded evidence and full-session aggregates.
  Map<String, Object?> toMap() => {
        'definition':
            'Consecutive Flutter intervals > 1.5 workload budgets; long stall >= 100 ms. Recovery is the first subsequent interval within cadence tolerance.',
        'episodeCount': episodeCount,
        'longStallCount': longStallCount,
        'longestIntervalMs': longestIntervalUs / 1000,
        'maxConsecutiveBadIntervals': maxConsecutiveBadIntervals,
        'droppedEpisodes': droppedEpisodes,
        'episodes': episodes.map((e) => e.toMap()).toList(),
      };
}
