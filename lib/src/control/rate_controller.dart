import 'dart:async';
import 'dart:collection';

/// A request, never a guarantee that a display will run at the requested rate.
enum PreferenceKind {
  /// Clear the owning preference.
  system,

  /// Request high refresh where supported.
  high,

  /// Request a platform category.
  category,

  /// Fixed-source content cadence.
  content,

  /// Request at least the specified UI cadence.
  atLeast,
}

/// Whether a content request may cause a visibly interrupted mode switch.
enum FrameRateSwitchStrategy {
  /// Allow only transitions without visual interruption.
  seamlessOnly,

  /// Explicitly allow interrupted display-mode transitions.
  allowNonSeamless,
}

/// Validated semantic refresh-rate request, independent of a native backend.
class RatePreference {
  /// Creates a [RatePreference] with the supplied configuration.
  const RatePreference.system()
      : kind = PreferenceKind.system,
        fps = null,
        category = null,
        strategy = FrameRateSwitchStrategy.seamlessOnly;

  /// Creates a [RatePreference] with the supplied configuration.
  const RatePreference.high()
      : kind = PreferenceKind.high,
        fps = null,
        category = null,
        strategy = FrameRateSwitchStrategy.seamlessOnly;

  /// Native category index: none, low, normal or high (0–3).
  const RatePreference.category(this.category)
      : kind = PreferenceKind.category,
        fps = null,
        strategy = FrameRateSwitchStrategy.seamlessOnly;

  /// Creates a [RatePreference] with the supplied configuration.
  RatePreference.content(double rate,
      {this.strategy = FrameRateSwitchStrategy.seamlessOnly})
      : kind = PreferenceKind.content,
        fps = rate,
        category = null {
    _validateRate(rate);
  }

  /// Whether minimum UI cadence semantics can be preserved.
  RatePreference.atLeast(double rate)
      : kind = PreferenceKind.atLeast,
        fps = rate,
        category = null,
        strategy = FrameRateSwitchStrategy.seamlessOnly {
    _validateRate(rate);
  }

  /// Semantic category of the requested preference.
  final PreferenceKind kind;

  /// Exact requested cadence in frames per second, when applicable.
  final double? fps;

  /// Native category index: none, low, normal or high (0–3).
  final int? category;

  /// Whether a display transition may interrupt visible content.
  final FrameRateSwitchStrategy strategy;
  static void _validateRate(double rate) {
    if (!rate.isFinite || rate <= 0 || rate > 1000) {
      throw ArgumentError.value(rate, 'fps', 'Expected 0 < fps <= 1000');
    }
  }

  /// Rejects invalid category values before native submission.
  void validate() {
    if (kind == PreferenceKind.category &&
        (category == null || category! < 0 || category! > 3)) {
      throw ArgumentError('Invalid category');
    }
  }

  /// Serializes this value to a JSON-compatible map.
  Map<String, Object?> toMap() => {
        'kind': kind.name,
        'fps': fps,
        'category': category,
        'strategy': strategy.name
      };
  @override
  bool operator ==(Object other) =>
      other is RatePreference &&
      kind == other.kind &&
      fps == other.fps &&
      category == other.category &&
      strategy == other.strategy;
  @override
  int get hashCode => Object.hash(kind, fps, category, strategy);
}

/// Outcome of submission, independent of hardware fulfilment.
enum RequestStatus {
  /// The named backend accepted the request.
  submitted,

  /// No supported backend implements these semantics.
  unsupported,

  /// The required window or rendering surface is absent.
  unavailable,

  /// A backend error prevented submission.
  failed,

  /// A newer decision replaced this reconciliation.
  superseded,
}

/// Receipt for a Dart-initiated submission, with its backend and scope.
/// Native lifecycle reapplication does not update an earlier receipt. Read fresh
/// native diagnostics to inspect the latest backend and target evidence.
class RateRequestResult {
  /// Creates a [RateRequestResult] with the supplied configuration.
  const RateRequestResult(
      {required this.status,
      required this.preference,
      this.backend = 'unavailable',
      this.scope = 'unknown',
      this.reused = false,
      this.message});

  /// Submission outcome; it does not establish hardware fulfilment.
  final RequestStatus status;

  /// The preference associated with this owner or submission.
  final RatePreference preference;

  /// Native mechanism used by the original submission, or unavailable.
  /// A reused result retains that mechanism even if native lifecycle callbacks
  /// have since reapplied the preference through another backend.
  final String backend;

  /// Window, surface, engine or observer scope of this value.
  final String scope;

  /// An unchanged successful preference was reused without a new Dart-initiated
  /// native write. Backend and scope describe the original submission.
  final bool reused;

  /// Optional explanation of unsupported state or failure.
  final String? message;

  /// Native submission is not evidence of fulfilment.
  bool get submitted => status == RequestStatus.submitted;

  /// False until a separately qualified observation establishes fulfilment.
  bool get fulfilmentObserved => false;
}

/// Explicit per-operation capabilities; absent evidence remains false.
class RefreshRateCapabilities {
  /// Creates a [RefreshRateCapabilities] with the supplied configuration.
  const RefreshRateCapabilities(
      {this.query = true,
      this.surfaceVoting = false,
      this.windowPreferences = false,
      this.categoryHints = false,
      this.engineControl = false,
      this.presentationObservation = false,
      this.atLeast = false,
      this.contentMatching = false,
      this.touchBoost = false,
      this.callbackObservation = false});

  /// Whether the platform exposes display information.
  final bool query;

  /// Whether a supported rendering-surface vote backend exists.
  final bool surfaceVoting;

  /// Whether window refresh preferences can be submitted.
  final bool windowPreferences;

  /// Whether descriptive native frame-rate categories are supported.
  final bool categoryHints;

  /// Whether this backend can control the specific Flutter engine.
  final bool engineControl;

  /// Whether physical presentation records have a qualified source.
  final bool presentationObservation;

  /// Whether minimum UI cadence semantics can be preserved.
  final bool atLeast;

  /// Whether fixed-source content semantics can be submitted.
  final bool contentMatching;

  /// Native touch boost with a public baseline getter.
  final bool touchBoost;

  /// A bounded native/browser callback observer is available.
  final bool callbackObservation;

  /// Serializes explicit per-operation support.
  Map<String, Object?> toMap() => {
        'query': query,
        'surfaceVoting': surfaceVoting,
        'windowPreferences': windowPreferences,
        'categoryHints': categoryHints,
        'engineControl': engineControl,
        'presentationObservation': presentationObservation,
        'atLeast': atLeast,
        'contentMatching': contentMatching,
        'touchBoost': touchBoost,
        'callbackObservation': callbackObservation,
      };

  /// Decodes explicit capabilities; absent flags remain unsupported.
  factory RefreshRateCapabilities.fromMap(Map<Object?, Object?> map) =>
      RefreshRateCapabilities(
          query: map['query'] == true,
          surfaceVoting: map['surfaceVoting'] == true,
          windowPreferences: map['windowPreferences'] == true,
          categoryHints: map['categoryHints'] == true,
          engineControl: map['engineControl'] == true,
          presentationObservation: map['presentationObservation'] == true,
          atLeast: map['atLeast'] == true,
          contentMatching: map['contentMatching'] == true,
          touchBoost: map['touchBoost'] == true,
          callbackObservation: map['callbackObservation'] == true);
}

/// Timestamped request decision and actual submission result.
class RefreshRateDecision {
  /// Creates a [RefreshRateDecision] with the supplied configuration.
  const RefreshRateDecision(
      this.timestamp, this.owner, this.reason, this.result);

  /// Time associated with this record in UTC.
  final DateTime timestamp;

  /// Identity of the caller that owns this preference.
  final String owner;

  /// Package decision reason, not an inferred reason for OS behavior.
  final String reason;

  /// Observed outcome of the backend submission.
  final RateRequestResult result;

  /// Structured history preserves source/scope without claiming fulfilment.
  Map<String, Object?> toMap() => {
        'timestamp': timestamp.toIso8601String(),
        'owner': owner,
        'reason': reason,
        'status': result.status.name,
        'backend': result.backend,
        'reused': result.reused,
        'scope': result.scope,
        'message': result.message,
        'preference': result.preference.toMap(),
        'fulfilmentObserved': result.fulfilmentObserved,
      };
}

/// An idempotently releasable preference. Expiry can release only this request.
class RefreshRateLease {
  RefreshRateLease._(
      this.id, this.owner, this.preference, this.priority, this._controller);

  /// Unique request identity within its controller.
  final int id;

  /// Higher priorities win; newer requests break ties.
  final int priority;

  /// Identity of the caller that owns this preference.
  final String owner;

  /// The preference associated with this owner or submission.
  final RatePreference preference;
  final RateController _controller;

  /// Outcome of this request’s initial reconciliation; it may be superseded.
  late final Future<RateRequestResult> ready;
  Timer? _timer;
  Future<RateRequestResult>? _release;

  /// Whether this owner has already released its request.
  bool get isReleased => _release != null;

  /// Releases this request only and returns the reconciliation result.
  Future<RateRequestResult> release() {
    _timer?.cancel();
    return _release ??= _controller._release(this);
  }
}

/// Serializes backend submissions and arbitrates by priority, then recency.
class RateController {
  /// Creates a [RateController] with the supplied configuration.
  RateController(this.submit);

  /// Backend submission function; errors become failed request results.
  final Future<RateRequestResult> Function(RatePreference) submit;
  final _leases = <int, RefreshRateLease>{};
  final _events = StreamController<RefreshRateDecision>.broadcast();
  final _history = Queue<RefreshRateDecision>();
  RateRequestResult? _lastSubmitted;
  Future<void> _tail = Future.value();
  int _nextId = 0, _generation = 0;
  bool _disposed = false;

  /// Broadcast stream of package decisions and submission outcomes.
  Stream<RefreshRateDecision> get decisions => _events.stream;

  /// The latest 200 decisions in chronological order.
  List<RefreshRateDecision> get history => List.unmodifiable(_history);

  /// Highest-priority active request, or null for system scheduling.
  RefreshRateLease? get effectiveLease {
    RefreshRateLease? winner;
    for (final lease in _leases.values) {
      if (winner == null ||
          lease.priority > winner.priority ||
          (lease.priority == winner.priority && lease.id > winner.id)) {
        winner = lease;
      }
    }
    return winner;
  }

  /// Arbitrated preference before native fulfilment is considered.
  RatePreference get effectivePreference =>
      effectiveLease?.preference ?? const RatePreference.system();

  /// Acquires an independently owned request with optional bounded expiry.
  RefreshRateLease acquire(RatePreference preference,
      {String owner = 'application', int priority = 100, Duration? duration}) {
    if (_disposed) throw StateError('Controller disposed');
    preference.validate();
    if (duration != null &&
        (duration <= Duration.zero || duration > const Duration(days: 1))) {
      throw ArgumentError('Duration must be positive and at most one day');
    }
    final lease =
        RefreshRateLease._(++_nextId, owner, preference, priority, this);
    _leases[lease.id] = lease;
    lease.ready = _reconcile(owner, 'acquired');
    if (duration != null) lease._timer = Timer(duration, lease.release);
    return lease;
  }

  Future<RateRequestResult> _release(RefreshRateLease lease) {
    _leases.remove(lease.id);
    if (_disposed) {
      return Future.value(RateRequestResult(
          status: RequestStatus.superseded, preference: lease.preference));
    }
    return _reconcile(lease.owner, 'released');
  }

  /// Reconciles ownership without repeating an unchanged successful write.
  /// Force only when the native target changed and needs a new submission.
  Future<RateRequestResult> reconcile(
          {String reason = 'reconcile', bool force = false}) =>
      _reconcile(effectiveLease?.owner ?? 'system', reason, force: force);
  Future<RateRequestResult> _reconcile(String owner, String reason,
      {bool force = false}) {
    final generation = ++_generation;
    final preference = effectivePreference;
    final completer = Completer<RateRequestResult>();
    _tail = _tail.then((_) async {
      RateRequestResult result;
      if (generation != _generation || _disposed) {
        result = RateRequestResult(
            status: RequestStatus.superseded, preference: preference);
      } else {
        try {
          final previous = force ? null : _lastSubmitted;
          if (previous != null && previous.preference == preference) {
            result = RateRequestResult(
                status: RequestStatus.submitted,
                preference: preference,
                backend: previous.backend,
                scope: previous.scope,
                reused: true,
                message: 'Unchanged successful preference; no native write.');
          } else {
            _lastSubmitted = null;
            result = await submit(preference);
            if (result.submitted) _lastSubmitted = result;
          }
        } catch (error) {
          result = RateRequestResult(
              status: RequestStatus.failed,
              preference: preference,
              message: error.toString());
        }
        if (generation != _generation || _disposed) {
          result = RateRequestResult(
              status: RequestStatus.superseded, preference: preference);
        }
      }
      if (!_disposed) {
        final event =
            RefreshRateDecision(DateTime.now().toUtc(), owner, reason, result);
        _history.add(event);
        if (_history.length > 200) _history.removeFirst();
        _events.add(event);
      }
      completer.complete(result);
    });
    return completer.future;
  }

  /// Stops arbitration, drains in-flight submissions, then clears the backend.
  Future<RateRequestResult> close() => _closing ??= _close();
  Future<RateRequestResult>? _closing;
  Future<RateRequestResult> _close() async {
    dispose();
    await _tail;
    try {
      return await submit(const RatePreference.system());
    } catch (error) {
      return RateRequestResult(
          status: RequestStatus.failed,
          preference: const RatePreference.system(),
          message: error.toString());
    }
  }

  /// Cancels local arbitration. Release leases or await close to clear hardware.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    for (final lease in _leases.values) {
      lease._timer?.cancel();
    }
    _leases.clear();
    _events.close();
  }
}
