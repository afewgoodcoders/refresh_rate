import 'dart:async';
import 'package:flutter/widgets.dart';
import '../models/display_info.dart';
import '../models/enums.dart';
import '../models/session_report.dart';
import 'fps_tracker.dart';
import 'frame_collector.dart';
import 'session_scorer.dart';
import 'session_clock.dart';

class _Segment {
  _Segment(this.start, this.state, this.targetHz, this.tags, this.info);
  final DateTime start;
  DateTime? end;
  final SessionState state;
  final double? targetHz;
  final Map<String, String> tags;
  final DisplayInfo info;
  Map<String, Object?> toMap() => {
        'start': start.toIso8601String(),
        'end': end?.toIso8601String(),
        'state': state.name,
        'targetHz': targetHz,
        'tags': tags,
        'nativeReportedDisplayHz': info.nativeReportedDisplayHz,
        'displayModeMaxHz': info.displayModeMaxHz,
        'displayServer': info.displayServer,
        'monitorCount': info.monitorCount,
        'displayObservedAt': info.observedAt?.toIso8601String(),
        'lowPowerMode': info.isLowPowerMode,
        'thermalState': info.thermalState.name
      };
}

/// A timing session with event-time filtering and bounded finalization.
/// Set expectedFps for an explicitly continuous workload. Call pause for idle
/// phases; absent workload intent is never interpreted as a missed deadline.
class RefreshRateSession {
  RefreshRateSession._(this.name, this._info, this._expectedFps, this._now,
      this.finalizationTimeout, this.warmupDuration)
      : _startedAt = _now() {
    _segments.add(_Segment(_startedAt, _state, _expectedFps, const {}, _info));
  }

  /// Human-readable scenario name embedded in the report.
  final String name;
  DisplayInfo _info;
  double? _expectedFps;
  final DateTime Function() _now;
  final DateTime _startedAt;
  SessionClock? _clockSource;

  /// Excluded warmup interval after foreground resume.
  final Duration finalizationTimeout, warmupDuration;
  final _tracker = FpsTracker();
  final _segments = <_Segment>[];
  final _markers = <Map<String, Object?>>[];
  final _exclusions = <ExclusionReason, int>{};
  SessionState _state = SessionState.running;
  void Function()? _unsubscribe;
  StreamSubscription<DisplayInfo>? _infoSubscription;
  AppLifecycleListener? _lifecycle;
  Timer? _warmup;
  Future<SessionReport>? _ending;
  DateTime? _cutoff;
  _Segment? _lastAcceptedSegment;
  Duration _evictedValidDuration = Duration.zero;
  bool _boundaryWitness = false, _coverageLost = false, _userPaused = false;
  bool _foreground = true;
  Map<String, String> _tags = const {};

  /// Starts a session with optional expected workload cadence and clock seam.
  static RefreshRateSession create(
    String name,
    DisplayInfo info, {
    double? expectedFps,
    Stream<DisplayInfo>? changes,
    Duration finalizationTimeout = const Duration(milliseconds: 1100),
    Duration warmupDuration = const Duration(milliseconds: 500),
    DateTime Function()? clock,
  }) {
    _validateFps(expectedFps);
    if (finalizationTimeout.isNegative ||
        finalizationTimeout > const Duration(seconds: 5) ||
        warmupDuration.isNegative) {
      throw ArgumentError('Invalid session duration');
    }
    final stableClock = SessionClock();
    final session = RefreshRateSession._(name, info, expectedFps,
        clock ?? stableClock.now, finalizationTimeout, warmupDuration);
    session._clockSource = clock == null ? stableClock : null;
    session._unsubscribe = FrameCollector.instance.subscribe(session._accept);
    session._infoSubscription = changes?.listen(session.updateDisplayInfo);
    session._lifecycle = AppLifecycleListener(onStateChange: (state) {
      if (state == AppLifecycleState.resumed) {
        session._resumeForeground();
      } else {
        session._leaveForeground();
      }
    });
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) {
      session._leaveForeground();
    }
    return session;
  }

  /// Current collection or finalization lifecycle state.
  SessionState get state => _state;

  /// UTC wall-time boundary at which the session began.
  DateTime get startedAt => _startedAt;

  /// Explicit workload cadence; legacy zero means unknown.
  double get targetHz => _expectedFps ?? 0;
  void _checkOpen() {
    if (_ending != null) throw StateError('Session has ended');
  }

  static void _validateFps(double? fps) {
    if (fps != null && (!fps.isFinite || fps <= 0)) {
      throw ArgumentError.value(fps, 'expectedFps');
    }
  }

  /// Changes expected workload cadence at a timestamped segment boundary.
  void setExpectedFps(double? fps) {
    _checkOpen();
    _validateFps(fps);
    _expectedFps = fps;
    _transition(_state);
  }

  /// Records a device-state transition without discarding thermal degradation.
  void updateDisplayInfo(DisplayInfo info) {
    if (_ending != null) return;
    _info = info;
    _transition(_state);
  }

  /// Changes are attributed to frame event timestamps, including late batches.
  void setTag(String key, String? value) {
    _checkOpen();
    if (key.length > 128 || (value?.length ?? 0) > 256) {
      throw ArgumentError('Tag too long');
    }
    final next = Map<String, String>.of(_tags);
    if (value == null) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    if (next.length > 32) throw StateError('At most 32 active tags');
    _tags = Map.unmodifiable(next);
    _transition(_state);
  }

  /// Adds a bounded timestamped marker with active workload tags.
  void mark(String label) {
    _checkOpen();
    if (label.length > 256) throw ArgumentError('Marker too long');
    if (_markers.length == 1000) {
      _markers.removeAt(0);
      _coverageLost = true;
    }
    _markers.add(Map.unmodifiable({
      'timestamp': _now().toIso8601String(),
      'label': label,
      'tags': _tags
    }));
  }

  /// Excludes subsequent frame events until explicit resume.
  void pause() {
    _checkOpen();
    _userPaused = true;
    _warmup?.cancel();
    _transition(SessionState.interrupted);
  }

  /// Resumes explicit collection when the application is foreground.
  void resume() {
    _checkOpen();
    _userPaused = false;
    if (_foreground) _transition(SessionState.running);
  }

  void _leaveForeground() {
    if (_ending != null || !_foreground) return;
    _foreground = false;
    _warmup?.cancel();
    _exclusions[ExclusionReason.appBackgrounded] =
        (_exclusions[ExclusionReason.appBackgrounded] ?? 0) + 1;
    _transition(SessionState.interrupted);
  }

  void _resumeForeground() {
    if (_ending != null || _foreground) return;
    _foreground = true;
    if (_userPaused) return;
    _transition(SessionState.warmup);
    _exclusions[ExclusionReason.resumeWarmup] =
        (_exclusions[ExclusionReason.resumeWarmup] ?? 0) + 1;
    _warmup = Timer(warmupDuration, () {
      if (_ending == null && _foreground && !_userPaused) {
        _transition(SessionState.running);
      }
    });
  }

  void _transition(SessionState next) {
    final now = _now();
    if (now.isBefore(_segments.last.start)) {
      _coverageLost = true;
      return;
    }
    _segments.last.end = now;
    _state = next;
    _segments.add(_Segment(now, next, _expectedFps, _tags, _info));
    // Bound metadata; dropped boundary history is explicitly incomplete.
    if (_segments.length > 10000) {
      final old = _segments.removeAt(0);
      if (old.state == SessionState.running) {
        _evictedValidDuration += old.end!.difference(old.start);
      }
      _coverageLost = true;
    }
  }

  void _accept(List<FrameSample> frames) {
    for (final sample in frames) {
      if (!sample.hasEventTime) {
        _coverageLost = true;
        _tracker.breakSegment();
        continue;
      }
      if (_cutoff != null && !sample.timestamp.isBefore(_cutoff!)) {
        _boundaryWitness = true;
        continue;
      }
      _Segment? segment;
      // Segment history is sorted; binary search avoids per-frame linear scans.
      var low = 0, high = _segments.length - 1;
      while (low <= high) {
        final mid = (low + high) ~/ 2;
        if (_segments[mid].start.isAfter(sample.timestamp)) {
          high = mid - 1;
        } else {
          segment = _segments[mid];
          low = mid + 1;
        }
      }
      if (segment == null ||
          segment.state != SessionState.running ||
          (segment.end != null && !sample.timestamp.isBefore(segment.end!))) {
        _tracker.breakSegment();
        _lastAcceptedSegment = null;
        continue;
      }
      if (!identical(segment, _lastAcceptedSegment) &&
          (_lastAcceptedSegment?.end != segment.start ||
              _lastAcceptedSegment?.targetHz != segment.targetHz)) {
        _tracker.breakSegment();
      }
      _lastAcceptedSegment = segment;
      _tracker.addSample(FrameSample(
          buildUs: sample.buildUs,
          rasterUs: sample.rasterUs,
          totalUs: sample.totalUs,
          vsyncUs: sample.vsyncUs,
          timestamp: sample.timestamp,
          hasEventTime: sample.hasEventTime,
          timestampSource: sample.timestampSource,
          targetHz: segment.targetHz,
          tags: segment.tags));
    }
  }

  @visibleForTesting

  /// Injects event-timed records through the production session filter.
  void addSamplesForTesting(List<FrameSample> samples) => _accept(samples);

  /// Idempotent: repeated calls return the same finalization future.
  Future<SessionReport> end() => _ending ??= _finalize();
  Future<SessionReport> _finalize() async {
    _cutoff = _now();
    if (_cutoff!.isBefore(_segments.last.start)) {
      _cutoff = _segments.last.start;
      _coverageLost = true;
    }
    _segments.last.end = _cutoff;
    _state = SessionState.finalizing;
    _warmup?.cancel();
    _lifecycle?.dispose();
    await _infoSubscription?.cancel();
    await Future<void>.delayed(finalizationTimeout);
    _unsubscribe?.call();
    _unsubscribe = null;
    _state = SessionState.completed;
    var valid = _evictedValidDuration;
    double expectedFrames = 0;
    for (final segment in _segments) {
      if (segment.state == SessionState.running && segment.end != null) {
        valid += segment.end!.difference(segment.start);
      }
    }
    for (final segment in _segments) {
      if (segment.state == SessionState.running &&
          segment.end != null &&
          segment.targetHz != null) {
        expectedFrames +=
            segment.end!.difference(segment.start).inMicroseconds /
                1000000 *
                segment.targetHz!;
      }
    }
    final elapsed = _cutoff!.difference(_startedAt);
    _tracker.stutters.interrupt();
    final clockChanged = _clockSource?.discontinuity ?? false;
    return SessionScorer.compute(
        sessionName: name,
        tracker: _tracker,
        targetHz: _expectedFps ?? 0,
        expectedWorkloadFrameCount:
            _coverageLost || expectedFrames == 0 ? null : expectedFrames,
        validDuration: valid,
        excludedDuration: elapsed - valid,
        exclusionReasons: Map.unmodifiable(_exclusions),
        deviceState: DeviceStateSnapshot(
            isLowPowerMode: _info.isLowPowerMode,
            thermalState: _info.thermalState,
            hasAdaptiveRefreshRate: _info.hasAdaptiveRefreshRate,
            displayServer: _info.displayServer,
            monitorCount: _info.monitorCount),
        boundaryCoverageComplete: _boundaryWitness &&
            !_coverageLost &&
            !clockChanged &&
            _tracker.invalidSampleCount == 0,
        segments: List.unmodifiable(
            _segments.map((s) => Map<String, Object?>.unmodifiable(s.toMap()))),
        markers: List.unmodifiable(_markers),
        clockDiscontinuity: clockChanged);
  }
}
