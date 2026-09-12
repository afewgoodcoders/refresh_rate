import 'dart:async';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:refresh_rate/refresh_rate.dart';
import 'package:refresh_rate/src/verification/frame_collector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('bounded sink batches do not block frame delivery', () async {
    final gate = Completer<void>();
    final received = <List<FrameSample>>[];
    final telemetry = FrameTelemetry(sampleEvery: 1, capacity: 4, batchSize: 2,
      sink: (frames) async { received.add(frames); await gate.future; });
    List<FrameTiming> frames(int offset) => List.generate(10, (i) => FrameTiming(
      vsyncStart: offset + i * 16667, buildStart: offset + i * 16667,
      buildFinish: offset + i * 16667 + 1000, rasterStart: offset + i * 16667 + 1000,
      rasterFinish: offset + i * 16667 + 2000, rasterFinishWallTime: 1700000000000000 + offset + i * 16667 + 2000));
    PlatformDispatcher.instance.onReportTimings!(frames(0));
    final flushing = telemetry.flush();
    await Future<void>.delayed(Duration.zero);
    expect(received.single.length, 2);
    PlatformDispatcher.instance.onReportTimings!(frames(200000));
    expect(telemetry.droppedSamples, greaterThan(0));
    expect(received.length, 1);
    gate.complete(); await flushing; await telemetry.dispose();
    expect(FrameCollector.instance.subscriberCount, 0);
  });
  test('invalid telemetry configuration fails before collecting', () {
    expect(() => FrameTelemetry(sink: (_) async {}, sampleEvery: 0), throwsArgumentError);
    expect(FrameCollector.instance.subscriberCount, 0);
  });
}
