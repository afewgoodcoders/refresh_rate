import 'dart:async';
import 'dart:collection';
import '../verification/frame_collector.dart';
import '../verification/fps_tracker.dart';

/// Opt-in, sampled batches for an application-provided sink. No network is
/// configured by the package. Raw timestamps can be sensitive telemetry.
class FrameTelemetry {
  /// Creates a [FrameTelemetry] with the supplied configuration.
  FrameTelemetry(
      {required this.sink,
      this.sampleEvery = 10,
      this.includeRenderingContext = false,
      this.capacity = 256,
      this.batchSize = 64,
      this.flushInterval = const Duration(seconds: 1),
      this.sinkTimeout = const Duration(seconds: 5)}) {
    if (sampleEvery < 1 ||
        capacity < 1 ||
        batchSize < 1 ||
        batchSize > capacity ||
        flushInterval < const Duration(milliseconds: 100) ||
        sinkTimeout <= Duration.zero) {
      throw ArgumentError('Invalid telemetry configuration');
    }
    _unsubscribe = FrameCollector.instance
        .subscribe(_accept, includeRenderingContext: includeRenderingContext);
  }

  /// Application-provided asynchronous export callback; no network is configured.
  final Future<void> Function(List<FrameSample>) sink;

  /// Exports every nth timing record.
  final int sampleEvery;

  /// Opt-in engine raster cache counters; no allocation sampling or heap scan.
  final bool includeRenderingContext;

  /// Maximum queued samples before dropping the oldest.
  final int capacity;

  /// Maximum samples passed to one sink invocation.
  final int batchSize;

  /// Time limit before a stalled sink disables further exports.
  final Duration flushInterval, sinkTimeout;
  final _queue = Queue<FrameSample>();
  void Function()? _unsubscribe;
  Timer? _timer;
  Future<void>? _inFlight;
  bool _disposed = false, _sinkTimedOut = false;
  int _seen = 0;

  /// Records discarded by backpressure or disposal.
  int droppedSamples = 0;

  /// Sink invocations that failed or timed out.
  int failedBatches = 0;

  /// Samples in failed or timed-out batches; remote delivery is unconfirmed.
  int failedSamples = 0;

  /// Samples whose sink callback completed before its timeout.
  int exportedSamples = 0;

  /// Most recent sink failure, available for application diagnostics.
  Object? lastError;
  void _accept(List<FrameSample> frames) {
    if (_disposed) return;
    for (final frame in frames) {
      if (++_seen % sampleEvery != 0) continue;
      if (_queue.length == capacity) {
        _queue.removeFirst();
        droppedSamples++;
      }
      _queue.add(frame);
    }
    if (_queue.isNotEmpty && _timer == null && !_sinkTimedOut) {
      _timer = Timer(flushInterval, () {
        _timer = null;
        flush();
      });
    }
  }

  /// At most one sink invocation runs at a time. A timed-out sink disables
  /// further exports so an uncooperative callback cannot create concurrency.
  Future<void> flush() {
    if (_inFlight != null) return _inFlight!;
    if (_queue.isEmpty || _sinkTimedOut) return Future.value();
    final batch = <FrameSample>[];
    while (batch.length < batchSize && _queue.isNotEmpty) {
      batch.add(_queue.removeFirst());
    }
    final operation = Future<void>.sync(() => sink(List.unmodifiable(batch)));
    _inFlight = operation.timeout(sinkTimeout).then((_) {
      exportedSamples += batch.length;
    }).catchError((Object error) {
      failedBatches++;
      failedSamples += batch.length;
      lastError = error;
      if (error is TimeoutException) _sinkTimedOut = true;
    }).whenComplete(() {
      _inFlight = null;
      if (!_disposed && !_sinkTimedOut && _queue.isNotEmpty && _timer == null) {
        _timer = Timer(flushInterval, () {
          _timer = null;
          flush();
        });
      }
    });
    return _inFlight!;
  }

  /// Stops collecting immediately; discards queued data and awaits a bounded
  /// in-flight export. It cannot cancel work inside an application callback.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _unsubscribe?.call();
    _timer?.cancel();
    droppedSamples += _queue.length;
    _queue.clear();
    await _inFlight;
  }
}
