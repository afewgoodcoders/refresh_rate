import 'dart:async';
import 'dart:collection';
import 'package:flutter/widgets.dart';
import '../models/display_info.dart';
import '../models/enums.dart';
import 'rate_controller.dart';

/// Policies use explicit activity and system constraints, not low-FPS feedback.
enum RefreshRatePolicy {
  /// Leave all choices to the system.
  system,

  /// High during activity, then clear after the configured idle delay.
  balanced,

  /// High during activity, with twice the configured idle grace period.
  performance,

  /// Request the normal category during activity; clear on idle.
  battery,
}

/// A policy proposal is separate from native submission/fulfilment.
class PolicyDecision {
  /// Creates a timestamped proposed preference.
  const PolicyDecision(
      this.preference, this.reason, this.shadowMode, this.timestamp);

  /// Proposed policy preference before higher-priority request arbitration.
  final RatePreference preference;

  /// Activity, constraint or capability reason.
  final String reason;

  /// True when no native preference was submitted by this policy.
  final bool shadowMode;

  /// UTC time of the proposal.
  final DateTime timestamp;

  /// Serializable policy evidence.
  Map<String, Object?> toMap() => {
        'preference': preference.toMap(),
        'reason': reason,
        'shadowMode': shadowMode,
        'timestamp': timestamp.toIso8601String()
      };
}

/// Opt-in policies driven by explicit workload activity, not FPS feedback.
/// Use beginActivity/endActivity or RefreshRateInteraction around interactive UI.
class RefreshRateAutoController {
  /// Creates a [RefreshRateAutoController] with the supplied configuration.
  RefreshRateAutoController(
    this.controller,
    Stream<DisplayInfo> changes, {
    this.policy = RefreshRatePolicy.balanced,
    this.shadowMode = false,
    this.capabilities =
        const RefreshRateCapabilities(surfaceVoting: true, categoryHints: true),
    this.idleDelay = const Duration(milliseconds: 800),
    required DisplayInfo initialInfo,
  }) : _info = initialInfo {
    if (idleDelay < const Duration(milliseconds: 100) ||
        idleDelay > const Duration(seconds: 30)) {
      throw ArgumentError('Idle delay must be 100ms–30s');
    }
    _subscription = changes.listen((info) {
      _info = info;
      _update();
    });
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _lifecycle = AppLifecycleListener(onStateChange: (s) {
      _foreground = s == AppLifecycleState.resumed;
      _update();
    });
  }

  /// Shared preference arbiter used by this integration.
  final RateController controller;

  /// Policy that maps explicit activity to a refresh preference.
  final RefreshRatePolicy policy;

  /// Records proposals without acquiring or releasing backend requests.
  final bool shadowMode;

  /// Qualified operation support; unsupported battery categories fall back to system.
  RefreshRateCapabilities capabilities;
  final _proposals = Queue<PolicyDecision>();
  final _decisions = StreamController<PolicyDecision>.broadcast();
  RatePreference? _lastProposal;
  String? _lastReason;

  /// Bounded latest proposals, including shadow decisions.
  List<PolicyDecision> get history => List.unmodifiable(_proposals);

  /// Proposed decisions; native outcomes are on RateController.decisions.
  Stream<PolicyDecision> get decisions => _decisions.stream;

  /// Refreshes capabilities after attachment or asynchronous initialization.
  void updateCapabilities(RefreshRateCapabilities value) {
    if (_disposed) return;
    capabilities = value;
    _update();
  }

  /// Grace period after the final activity ends.
  final Duration idleDelay;
  DisplayInfo _info;
  final _activities = <Object>{};
  RefreshRateLease? _lease;
  Timer? _idle;
  StreamSubscription<DisplayInfo>? _subscription;
  AppLifecycleListener? _lifecycle;
  bool _foreground = true, _disposed = false;

  /// Begins an activity and returns its independently releasable token.
  Object beginActivity() {
    if (_disposed) throw StateError('Policy disposed');
    final token = Object();
    _activities.add(token);
    _idle?.cancel();
    _update();
    return token;
  }

  /// Ends only the activity identified by this token.
  void endActivity(Object token) {
    if (_disposed || !_activities.remove(token) || _activities.isNotEmpty) {
      return;
    }
    _idle?.cancel();
    _idle = Timer(
        policy == RefreshRatePolicy.performance ? idleDelay * 2 : idleDelay,
        _update);
  }

  void _update() {
    if (_disposed) return;
    final constrained = _info.isLowPowerMode == true ||
        _info.thermalState == ThermalState.serious ||
        _info.thermalState == ThermalState.critical;
    final active = _activities.isNotEmpty || (_idle?.isActive ?? false);
    final supported = policy == RefreshRatePolicy.battery
        ? capabilities.categoryHints
        : (capabilities.surfaceVoting ||
            capabilities.windowPreferences ||
            capabilities.engineControl);
    final shouldRequest = supported &&
        _foreground &&
        active &&
        !constrained &&
        policy != RefreshRatePolicy.system;
    final desired = policy == RefreshRatePolicy.battery
        ? const RatePreference.category(2)
        : const RatePreference.high();
    final proposed = shouldRequest ? desired : const RatePreference.system();
    final reason = !_foreground
        ? 'background'
        : constrained
            ? 'powerOrThermal'
            : !active
                ? 'idle'
                : policy == RefreshRatePolicy.system
                    ? 'systemPolicy'
                    : !supported
                        ? 'unsupportedPolicy'
                        : 'activity';
    if (proposed != _lastProposal || reason != _lastReason) {
      _lastProposal = proposed;
      _lastReason = reason;
      final decision =
          PolicyDecision(proposed, reason, shadowMode, DateTime.now().toUtc());
      if (_proposals.length == 200) _proposals.removeFirst();
      _proposals.add(decision);
      _decisions.add(decision);
    }
    if (shadowMode) return;
    if (!shouldRequest) {
      _lease?.release();
      _lease = null;
    } else if (_lease?.preference != desired) {
      final old = _lease;
      _lease = controller.acquire(desired,
          owner: 'auto:${policy.name}', priority: 10);
      old?.release();
    }
  }

  /// Releases owned listeners, timers and requests; repeated calls are safe.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _idle?.cancel();
    _lifecycle?.dispose();
    await _subscription?.cancel();
    await _lease?.release();
    _activities.clear();
    unawaited(_decisions.close());
  }
}
