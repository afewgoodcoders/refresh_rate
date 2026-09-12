import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';
import 'fps_tracker.dart';

/// A single engine callback shared by sessions, overlays and optional sinks.
class FrameCollector {
  FrameCollector._();

  /// Shared service instance for this Flutter isolate.
  static final instance = FrameCollector._();
  final _listeners = <void Function(List<FrameSample>)>{};

  /// Number of active subscribers owning the engine callback.
  int get subscriberCount => _listeners.length;

  /// Adds an independent subscriber and returns its idempotent disposer.
  void Function() subscribe(void Function(List<FrameSample>) listener) {
    if (_listeners.isEmpty) {
      SchedulerBinding.instance.addTimingsCallback(_collect);
    }
    void ownedListener(List<FrameSample> frames) => listener(frames);
    _listeners.add(ownedListener);
    var released = false;
    return () {
      if (released) return;
      released = true;
      _listeners.remove(ownedListener);
      if (_listeners.isEmpty) {
        SchedulerBinding.instance.removeTimingsCallback(_collect);
      }
    };
  }

  void _collect(List<FrameTiming> timings) {
    final frames =
        List<FrameSample>.unmodifiable(timings.map(FrameSample.fromTiming));
    for (final listener in List.of(_listeners)) {
      try {
        listener(frames);
      } catch (error, stack) {
        FlutterError.reportError(FlutterErrorDetails(
            exception: error, stack: stack, library: 'refresh_rate collector'));
      }
    }
  }
}
