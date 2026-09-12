import 'dart:async';
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

/// Opt-in policies driven by explicit workload activity, not FPS feedback.
/// Use beginActivity/endActivity or RefreshRateInteraction around interactive UI.
class RefreshRateAutoController {
  /// Creates a [RefreshRateAutoController] with the supplied configuration.
  RefreshRateAutoController(
    this.controller,
    Stream<DisplayInfo> changes, {
    this.policy = RefreshRatePolicy.balanced,
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
    final shouldRequest = _foreground &&
        active &&
        !constrained &&
        policy != RefreshRatePolicy.system;
    final desired = policy == RefreshRatePolicy.battery
        ? const RatePreference.category(2)
        : const RatePreference.high();
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
  }
}
