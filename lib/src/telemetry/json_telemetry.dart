import 'frame_telemetry.dart';
import 'export_policy.dart';

/// Sampled, bounded, policy-filtered NDJSON batches for application-owned sinks.
class JsonFrameTelemetry {
  /// Uses the same shared collector and backpressure as FrameTelemetry.
  JsonFrameTelemetry(
      {required Future<void> Function(String ndjson) sink,
      TelemetryExportPolicy? policy,
      int sampleEvery = 10,
      int capacity = 256,
      int batchSize = 64,
      Duration flushInterval = const Duration(seconds: 1)}) {
    final exportPolicy = policy ?? TelemetryExportPolicy();
    _telemetry = FrameTelemetry(
        sampleEvery: sampleEvery,
        capacity: capacity,
        batchSize: batchSize,
        flushInterval: flushInterval,
        sink: (frames) => sink('${exportPolicy.encode({
                  'schemaVersion': 1,
                  'source': 'flutterFrameTiming',
                  'presentationCoverage': 'unavailable',
                  'frames': frames.map((f) => f.toMap()).toList(),
                })}\n'));
  }
  late final FrameTelemetry _telemetry;

  /// Queue overflow/disposal drops; failed batches are counted separately.
  int get droppedSamples => _telemetry.droppedSamples;

  /// Explicit number of failed or rejected export batches.
  int get failedBatches => _telemetry.failedBatches;

  /// Samples in batches whose delivery failed or remains unconfirmed.
  int get failedSamples => _telemetry.failedSamples;

  /// Samples acknowledged by the application sink before timeout.
  int get exportedSamples => _telemetry.exportedSamples;

  /// Most recent size, sink or timeout error.
  Object? get lastError => _telemetry.lastError;

  /// Flushes one bounded batch.
  Future<void> flush() => _telemetry.flush();

  /// Stops collection and waits for bounded in-flight work.
  Future<void> dispose() => _telemetry.dispose();
}
