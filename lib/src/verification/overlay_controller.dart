import 'dart:async';
import 'package:flutter/material.dart';
import '../refresh_rate.dart';
import 'fps_tracker.dart';
import 'frame_collector.dart';
import 'overlay_widgets.dart';

enum _OverlayMode { none, fps, hz, full }

/// Event-driven overlay. The observer still affects workload: benchmark it off.
class OverlayController {
  OverlayController._();

  /// Shared service instance for this Flutter isolate.
  static final instance = OverlayController._();
  OverlayEntry? _entry;
  _OverlayMode _mode = _OverlayMode.none;
  final _tracker = FpsTracker();
  void Function()? _unsubscribe;
  StreamSubscription<Object?>? _changes, _decisions;
  double? _expectedFps;
  Timer? _update, _stale;
  int _generation = 0;
  bool _isStale = true;
  String _signature = '';

  /// Whether an overlay entry is currently inserted.
  bool get isVisible => _entry != null;

  /// Shows a throttled Flutter cadence badge.
  void showFPS({double? expectedFps}) =>
      _show(_OverlayMode.fps, expectedFps: expectedFps);

  /// Shows native display information without subscribing to frame timings.
  void showHz() => _show(_OverlayMode.hz);

  /// Shows source-qualified rates and phase timing diagnostics.
  void showFull({double? expectedFps}) =>
      _show(_OverlayMode.full, expectedFps: expectedFps);

  /// Removes the overlay and cancels queued insertions and observers.
  void hide() {
    _generation++;
    _update?.cancel();
    _stale?.cancel();
    _unsubscribe?.call();
    _unsubscribe = null;
    _changes?.cancel();
    _changes = null;
    _decisions?.cancel();
    _decisions = null;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
    _mode = _OverlayMode.none;
    _tracker.reset();
    _signature = '';
    _isStale = true;
  }

  void _show(_OverlayMode mode, {double? expectedFps}) {
    if (expectedFps != null && (!expectedFps.isFinite || expectedFps <= 0)) {
      throw ArgumentError.value(expectedFps, 'expectedFps');
    }
    hide();
    _expectedFps = expectedFps;
    _mode = mode;
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (generation != _generation || _mode == _OverlayMode.none) return;
      final overlay = _findOverlay();
      if (overlay == null) {
        _mode = _OverlayMode.none;
        return;
      }
      _entry = OverlayEntry(
          builder: (_) => switch (_mode) {
                _OverlayMode.fps =>
                  FpsOverlayWidget(tracker: _tracker, stale: _isStale),
                _OverlayMode.hz => HzOverlayWidget(tracker: _tracker),
                _OverlayMode.full => FullOverlayWidget(
                    tracker: _tracker,
                    stale: _isStale,
                    expectedFps: _expectedFps),
                _OverlayMode.none => const SizedBox.shrink(),
              });
      overlay.insert(_entry!);
      _changes = RefreshRate.onChanged.listen((_) => _scheduleUpdate());
      if (mode == _OverlayMode.full) {
        _decisions = RefreshRate.onDecision.listen((_) => _scheduleUpdate());
      }
      RefreshRate.refresh().catchError((Object _) => RefreshRate.info);
      if (mode != _OverlayMode.hz) {
        _unsubscribe = FrameCollector.instance.subscribe((frames) {
          // A lone overlay repaint must not sustain its own update loop.
          if (frames.length < 2) return;
          if (_isStale) _tracker.reset();
          for (final frame in frames) {
            _tracker.addSample(FrameSample(
                buildUs: frame.buildUs,
                rasterUs: frame.rasterUs,
                totalUs: frame.totalUs,
                vsyncUs: frame.vsyncUs,
                timestamp: frame.timestamp,
                hasEventTime: frame.hasEventTime,
                timestampSource: frame.timestampSource,
                targetHz: _expectedFps));
          }
          _isStale = false;
          _scheduleUpdate();
          _stale?.cancel();
          _stale = Timer(const Duration(milliseconds: 1500), () {
            _isStale = true;
            _scheduleUpdate();
          });
        });
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _scheduleUpdate() {
    if (_update?.isActive ?? false) return;
    final generation = _generation;
    _update = Timer(const Duration(milliseconds: 250), () {
      if (generation != _generation) return;
      final signature = '$_isStale:${_tracker.recentFps().round()}:'
          '${_tracker.avgBuildMs.toStringAsFixed(1)}:${_tracker.avgRasterMs.toStringAsFixed(1)}:'
          '${RefreshRate.info}:${RefreshRate.info.isStale}:'
          '${RefreshRate.requestedPreference.toMap()}:$_expectedFps:'
          '${_tracker.phaseOverruns}:${_tracker.budgetedFrameCount}';
      if (signature != _signature) {
        _signature = signature;
        _entry?.markNeedsBuild();
      }
    });
  }

  static OverlayState? _findOverlay() {
    final root = WidgetsBinding.instance.rootElement;
    OverlayState? found;
    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement && element.state is OverlayState) {
        found = element.state as OverlayState;
        return;
      }
      element.visitChildren(visit);
    }

    root?.visitChildren(visit);
    return found;
  }
}
