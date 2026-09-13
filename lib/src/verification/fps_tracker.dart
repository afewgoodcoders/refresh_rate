import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';
import 'stutter_tracker.dart';
import 'frame_clock.dart' if (dart.library.js_interop) 'frame_clock_web.dart';

/// One Flutter engine timing record; this is not a presentation event.
class FrameSample {
  /// Flutter UI phase duration in microseconds.
  final int buildUs;

  /// Flutter raster phase duration in microseconds.
  final int rasterUs;

  /// Pipeline latency from vsync start to raster finish, in microseconds.
  final int totalUs;

  /// Raw engine vsync timestamp in its own clock domain.
  final int vsyncUs;

  /// Estimated vsync wall time using [timestampSource].
  final DateTime timestamp;

  /// Whether the wall-time bridge is available for event-time filtering.
  final bool hasEventTime;

  /// Clock bridge used for event time, or unavailable for receipt-time fallback.
  final String timestampSource;

  /// Explicit workload cadence; legacy zero means unknown.
  final double? targetHz;

  /// Immutable workload tags applicable at the frame event time.
  final Map<String, String> tags;

  /// Optional engine raster-cache context, not process memory or GPU allocation.
  final Map<String, int>? renderingContext;

  /// Creates a [FrameSample] with the supplied configuration.
  FrameSample(
      {required this.buildUs,
      required this.rasterUs,
      required this.totalUs,
      required this.vsyncUs,
      required this.timestamp,
      this.hasEventTime = true,
      this.timestampSource = 'provided',
      Map<String, int>? renderingContext,
      this.targetHz,
      Map<String, String> tags = const {}})
      : tags = Map.unmodifiable(tags),
        renderingContext = renderingContext == null
            ? null
            : Map.unmodifiable(renderingContext);

  /// Converts raw phases using the raster-finish wall-time bridge.
  factory FrameSample.fromTiming(FrameTiming t,
      {bool includeRenderingContext = false}) {
    final vsync = t.timestampInMicroseconds(FramePhase.vsyncStart);
    final finish = t.timestampInMicroseconds(FramePhase.rasterFinish);
    final wall = t.timestampInMicroseconds(FramePhase.rasterFinishWallTime);
    final event = frameEventTime(vsync, finish, wall);
    return FrameSample(
        buildUs: t.buildDuration.inMicroseconds,
        rasterUs: t.rasterDuration.inMicroseconds,
        totalUs: t.totalSpan.inMicroseconds,
        vsyncUs: vsync,
        renderingContext: includeRenderingContext
            ? {
                'layerCacheCount': t.layerCacheCount,
                'layerCacheBytes': t.layerCacheBytes,
                'pictureCacheCount': t.pictureCacheCount,
                'pictureCacheBytes': t.pictureCacheBytes,
              }
            : null,
        hasEventTime: event != null,
        timestampSource: event?.source ?? 'unavailable',
        timestamp: event?.timestamp ?? DateTime.now().toUtc());
  }

  /// Serializes this value to a JSON-compatible map.
  Map<String, Object?> toMap() => {
        'vsyncUs': vsyncUs,
        'timestamp': timestamp.toIso8601String(),
        'timestampSource': timestampSource,
        'hasEventTime': hasEventTime,
        'buildMs': buildUs / 1000,
        'rasterMs': rasterUs / 1000,
        'pipelineLatencyMs': totalUs / 1000,
        'targetHz': targetHz,
        'renderingContext': renderingContext,
        'tags': tags
      };
}

/// Bounded logarithmic histogram. Bucket width <= 1% for positive durations.
/// Counts/sums are exact; quantiles and partial tail means are approximate.
class TimingHistogram {
  final _counts = SplayTreeMap<int, int>();
  final _sums = <int, int>{};

  /// Number of durations in this histogram.
  int count = 0;

  /// Exact sum of represented durations in microseconds.
  int sum = 0;
  static final _logBase = math.log(1.01);

  /// Adds a nonnegative microsecond duration to the bounded histogram.
  void add(int us) {
    if (us < 0 || us > 9007199254740991) return;
    final key = us == 0 ? -1 : (math.log(us) / _logBase).floor();
    _counts[key] = (_counts[key] ?? 0) + 1;
    _sums[key] = (_sums[key] ?? 0) + us;
    count++;
    sum += us;
  }

  /// Exact arithmetic mean duration in milliseconds.
  double get meanMs => count == 0 ? 0 : sum / count / 1000;

  /// Returns an approximate nearest-rank percentile in milliseconds.
  double? percentileMs(double percentile) {
    if (percentile < 0 || percentile > 100 || !percentile.isFinite) {
      throw ArgumentError.value(percentile, 'percentile');
    }
    if (count == 0) return null;
    final rank = math.max(1, (count * percentile / 100).ceil());
    var seen = 0;
    for (final e in _counts.entries) {
      seen += e.value;
      if (seen >= rank) return _sums[e.key]! / e.value / 1000;
    }
    return null;
  }

  /// Returns inverse mean of the slowest interval fraction, or insufficient data.
  double? lowFps(double fraction) {
    if (!fraction.isFinite || fraction <= 0 || fraction > 1) {
      throw ArgumentError.value(fraction, 'fraction', 'Must be in (0, 1]');
    }
    if (count < (1 / fraction).ceil()) return null;
    var remaining = (count * fraction).ceil();
    final n = remaining;
    double tailSum = 0;
    for (final key in _counts.keys.toList().reversed) {
      final take = math.min(remaining, _counts[key]!);
      tailSum += take * _sums[key]! / _counts[key]!;
      remaining -= take;
      if (remaining == 0) break;
    }
    return tailSum > 0 ? 1000000 * n / tailSum : null;
  }

  /// Estimates count above a threshold using bucket means.
  int countAbove(double us) => _counts.entries
      .fold(0, (n, e) => n + (_sums[e.key]! / e.value > us ? e.value : 0));

  /// Clears histogram counts and sums.
  void clear() {
    _counts.clear();
    _sums.clear();
    count = 0;
    sum = 0;
  }
}

/// Whole-session aggregates with bounded recent history and worst records.
class FpsTracker {
  /// Creates a [FpsTracker] with the supplied configuration.
  FpsTracker({this.historyLimit = 600, this.worstFrameLimit = 10}) {
    if (historyLimit < 2 || worstFrameLimit < 0) {
      throw ArgumentError('Invalid limits');
    }
  }

  /// Maximum recent raw samples retained independently of aggregates.
  final int historyLimit;

  /// Maximum worst-latency records retained across the session.
  final int worstFrameLimit;
  final _samples = Queue<FrameSample>();
  final _worst = <FrameSample>[];

  /// Whole-session histogram of UI phase microseconds.
  final build = TimingHistogram();

  /// Whole-session histogram of raster phase microseconds.
  final raster = TimingHistogram();

  /// Whole-session histogram of pipeline latency microseconds.
  final pipeline = TimingHistogram();

  /// Whole-session histogram of valid adjacent-frame intervals.
  final intervals = TimingHistogram();
  final _maxPhase = TimingHistogram();

  /// Consecutive cadence anomalies at the declared workload target.
  final stutters = StutterTracker();
  FrameSample? _previous;
  int? _lastVsync;
  int _count = 0;

  /// Rejected invalid or non-increasing timing records.
  int invalidSampleCount = 0;

  /// Records with an explicitly specified workload frame budget.
  int budgetedFrameCount = 0;

  /// UI phases exceeding the event-time budget.
  int buildOverruns = 0;

  /// Raster phases exceeding the event-time budget.
  int rasterOverruns = 0;

  /// Frames where either UI or raster exceeded the event-time budget.
  int phaseOverruns = 0;

  /// Frames with a phase exceeding twice the event-time budget.
  int severePhaseOverruns = 0;

  /// Pipeline spans over budget, separate from phase overruns.
  int pipelineOverruns = 0;

  /// Intervals greater than 1.5 times the expected cadence interval.
  int cadenceGaps = 0;

  /// Intervals with a known workload cadence.
  int expectedIntervalCount = 0;

  /// Number of records represented by the measurement.
  int get sampleCount => _count;

  /// Immutable copy of bounded recent raw history.
  List<FrameSample> get samples => List.unmodifiable(_samples);

  /// Bounded worst pipeline-latency records retained across the full session.
  List<FrameSample> get worstFrames => List.unmodifiable(_worst);

  /// Adds a batch of engine records to the accumulator.
  void addTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      addSample(FrameSample.fromTiming(timing));
    }
  }

  /// Prevents the next record from forming an interval across a boundary.
  void breakSegment() {
    _previous = null;
    stutters.interrupt();
  }

  /// Adds one validated record and updates full-session aggregates.
  void addSample(FrameSample s) {
    if (s.buildUs < 0 ||
        s.rasterUs < 0 ||
        s.totalUs < 0 ||
        (_lastVsync != null && s.vsyncUs <= _lastVsync!)) {
      invalidSampleCount++;
      breakSegment();
      return;
    }
    final previous = _previous;
    final target = s.targetHz;
    if (previous != null && previous.targetHz == target) {
      final interval = s.vsyncUs - previous.vsyncUs;
      intervals.add(interval);
      if (target != null && target.isFinite && target > 0) {
        expectedIntervalCount++;
        stutters.add(
            intervalUs: interval,
            targetHz: target,
            start: previous.timestamp,
            end: s.timestamp);
        if (interval > 1000000 / target * 1.5) cadenceGaps++;
      }
    }
    if (previous != null && previous.targetHz != target) stutters.interrupt();
    _previous = s;
    _lastVsync = s.vsyncUs;
    _count++;
    build.add(s.buildUs);
    raster.add(s.rasterUs);
    pipeline.add(s.totalUs);
    _maxPhase.add(math.max(s.buildUs, s.rasterUs));
    if (target != null && target.isFinite && target > 0) {
      budgetedFrameCount++;
      final budget = (1000000 / target).round();
      if (s.buildUs > budget) buildOverruns++;
      if (s.rasterUs > budget) rasterOverruns++;
      if (math.max(s.buildUs, s.rasterUs) > budget) phaseOverruns++;
      if (math.max(s.buildUs, s.rasterUs) > budget * 2) severePhaseOverruns++;
      if (s.totalUs > budget) pipelineOverruns++;
    }
    _samples.add(s);
    if (_samples.length > historyLimit) _samples.removeFirst();
    if (worstFrameLimit > 0) {
      var index = 0;
      while (index < _worst.length && _worst[index].totalUs >= s.totalUs) {
        index++;
      }
      if (index < worstFrameLimit) _worst.insert(index, s);
      if (_worst.length > worstFrameLimit) _worst.removeLast();
    }
  }

  /// Whole-session valid interval count divided by interval exposure.
  double get avgFps =>
      intervals.sum > 0 ? intervals.count * 1000000 / intervals.sum : 0;

  /// Cadence over up to n recent records for the live overlay.
  double recentFps([int n = 60]) {
    if (n < 2) throw ArgumentError.value(n, 'n');
    final s = samples;
    if (s.length < 2) return 0;
    final first = s[math.max(0, s.length - n)];
    final elapsed = s.last.vsyncUs - first.vsyncUs;
    return elapsed > 0 ? (math.min(n, s.length) - 1) * 1000000 / elapsed : 0;
  }

  /// Whole-session arithmetic mean UI phase time in milliseconds.
  double get avgBuildMs => build.meanMs;

  /// Whole-session arithmetic mean raster time in milliseconds.
  double get avgRasterMs => raster.meanMs;

  /// Whole-session mean pipeline latency in milliseconds.
  double get avgTotalMs => pipeline.meanMs;

  /// Slowest 1% interval-tail cadence; legacy zero means insufficient data.
  double get onePercentLowFps => intervals.lowFps(.01) ?? 0;

  /// Slowest 5% interval-tail cadence; legacy zero means insufficient data.
  double get fivePercentLowFps => intervals.lowFps(.05) ?? 0;

  /// Slowest 0.1% interval-tail cadence; null below 1000 intervals.
  double? get pointOnePercentLowFps => intervals.lowFps(.001);

  /// Legacy estimate of phase overruns at a supplied budget, not presentations.
  int jankyFrameCount(double hz) {
    _validateTarget(hz);
    return _maxPhase.countAbove((1000000 / hz).roundToDouble());
  }

  /// Legacy estimate of phase overruns above twice a supplied budget.
  int severeJankCount(double hz) {
    _validateTarget(hz);
    return _maxPhase.countAbove((1000000 / hz).round() * 2.0);
  }

  /// Legacy phase-overrun percentage; not a physical missed-frame count.
  double missedFramePercent(double hz) =>
      sampleCount == 0 ? 0 : jankyFrameCount(hz) / sampleCount * 100;
  static void _validateTarget(double hz) {
    if (!hz.isFinite || hz <= 0) throw ArgumentError.value(hz, 'targetHz');
  }

  /// Clears recent history and all session aggregates.
  void reset() {
    _samples.clear();
    stutters.clear();
    _worst.clear();
    _previous = null;
    _lastVsync = null;
    _count = 0;
    for (final h in [build, raster, pipeline, intervals, _maxPhase]) {
      h.clear();
    }
    invalidSampleCount = budgetedFrameCount = buildOverruns = rasterOverruns =
        phaseOverruns = severePhaseOverruns =
            pipelineOverruns = cadenceGaps = expectedIntervalCount = 0;
  }
}
