import 'dart:async';
import 'package:flutter/widgets.dart';
import '../models/display_info.dart';
import '../models/enums.dart';
import '../verification/frame_collector.dart';
import '../verification/fps_tracker.dart';

/// Application-owned quality level advice; the package never changes visuals.
enum QualityLevel {
  /// Conditions permit the app to consider restoring its usual workload.
  normal,

  /// Consider reducing expensive effects or discretionary work.
  reduced,
}

/// A reasoned suggestion, not proof of the cause of frame drops.
class QualityRecommendation {
  /// Describes observed pressure or sustained recovery.
  const QualityRecommendation(this.level, this.reason, this.observedAt);

  /// Requested application response; caller may ignore it.
  final QualityLevel level;

  /// Evidence used for the suggestion, without causal attribution.
  final String reason;

  /// UTC receipt time of the evidence.
  final DateTime observedAt;
}

/// Advises on sustained phase-budget pressure and native power/thermal state.
/// Timing samples are used only while the caller declares an active workload.
class RefreshRateQualityController {
  /// A reduction needs badFrames consecutive phase overruns; recovery needs
  /// recoveryFrames healthy records. No recovery is inferred from missing data.
  RefreshRateQualityController(
      {required this.onRecommendation,
      required Stream<DisplayInfo> changes,
      required DisplayInfo initialInfo,
      this.badFrames = 8,
      this.recoveryFrames = 120})
      : _info = initialInfo {
    if (badFrames < 1 || recoveryFrames <= badFrames) {
      throw ArgumentError('Invalid quality hysteresis');
    }
    _subscription = changes.listen((info) {
      _info = info;
      _device();
    });
    _lifecycle = AppLifecycleListener(onStateChange: (state) {
      _foreground = state == AppLifecycleState.resumed;
      _bad = _good = 0;
      _syncCollector();
    });
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  /// Application delegate; invoked only when the recommendation changes.
  final ValueChanged<QualityRecommendation> onRecommendation;

  /// Consecutive pressure/recovery sample requirements.
  final int badFrames, recoveryFrames;
  DisplayInfo _info;
  double? _target, _headroom;
  DateTime? _activeSince;
  int? _lastVsync;
  bool _foreground = true, _disposed = false;
  int _bad = 0, _good = 0;
  QualityLevel _level = QualityLevel.normal;
  StreamSubscription<DisplayInfo>? _subscription;
  AppLifecycleListener? _lifecycle;
  void Function()? _unsubscribe;

  /// Most recently proposed application quality level.
  QualityLevel get level => _level;

  /// Declare continuous work and its budget; null stops timing collection.
  void setWorkload(double? expectedFps) {
    if (_disposed) throw StateError('Quality controller disposed');
    if (expectedFps != null && (!expectedFps.isFinite || expectedFps <= 0)) {
      throw ArgumentError.value(expectedFps, 'expectedFps');
    }
    _target = expectedFps;
    _activeSince = DateTime.now().toUtc();
    _lastVsync = null;
    _bad = _good = 0;
    _syncCollector();
    _device();
  }

  /// Supplies a fresh optional Android headroom reading; null clears it.
  /// Values >= 0.9 are precautionary advice, not a universal thermal threshold.
  void updateThermalHeadroom(double? value) {
    if (_disposed) throw StateError('Quality controller disposed');
    if (value != null && (!value.isFinite || value < 0)) {
      throw ArgumentError.value(value, 'value');
    }
    _headroom = value;
    _device();
  }

  bool get _constrained =>
      _info.isLowPowerMode == true ||
      _info.thermalState == ThermalState.serious ||
      _info.thermalState == ThermalState.critical ||
      (_headroom ?? 0) >= .9;
  void _device() {
    if (!_disposed && _foreground && _target != null && _constrained) {
      _good = 0;
      _advise(QualityLevel.reduced, 'Reported power/thermal pressure');
    }
  }

  void _syncCollector() {
    _unsubscribe?.call();
    _unsubscribe = null;
    if (!_disposed && _foreground && _target != null) {
      _activeSince = DateTime.now().toUtc();
      _lastVsync = null;
      _unsubscribe = FrameCollector.instance.subscribe(_frames);
    }
  }

  void _frames(List<FrameSample> frames) {
    if (_disposed || _target == null || !_foreground) return;
    final budget = 1000000 / _target!;
    for (final frame in frames) {
      if (!frame.hasEventTime || frame.timestamp.isBefore(_activeSince!)) {
        continue;
      }
      if (_lastVsync != null &&
          (frame.vsyncUs <= _lastVsync! ||
              frame.vsyncUs - _lastVsync! > 250000)) {
        _bad = _good = 0;
      }
      _lastVsync = frame.vsyncUs;
      if (frame.buildUs < 0 || frame.rasterUs < 0) {
        _bad = _good = 0;
        continue;
      }
      if (_constrained) {
        _device();
        continue;
      }
      if (frame.buildUs > budget || frame.rasterUs > budget) {
        _good = 0;
        if (++_bad >= badFrames) {
          _advise(QualityLevel.reduced,
              'Consecutive Flutter phase-budget overruns');
        }
      } else {
        _bad = 0;
        if (++_good >= recoveryFrames) {
          _advise(
              QualityLevel.normal, 'Sustained in-budget Flutter processing');
        }
      }
    }
  }

  void _advise(QualityLevel next, String reason) {
    if (next == _level) return;
    _level = next;
    try {
      onRecommendation(
          QualityRecommendation(next, reason, DateTime.now().toUtc()));
    } catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'refresh_rate quality delegate'));
    }
  }

  /// Stops collection and listeners; leaves all application choices to the app.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _unsubscribe?.call();
    _lifecycle?.dispose();
    await _subscription?.cancel();
  }
}
