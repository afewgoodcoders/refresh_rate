import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:refresh_rate/refresh_rate.dart';

void main() {
  test('closing drains an in-flight vote and clears the backend exactly once',
      () async {
    final gate = Completer<void>();
    final seen = <PreferenceKind>[];
    final controller = RateController((preference) async {
      seen.add(preference.kind);
      if (preference.kind == PreferenceKind.high) await gate.future;
      return RateRequestResult(
          status: RequestStatus.submitted, preference: preference);
    });
    final lease = controller.acquire(const RatePreference.high());
    await Future<void>.delayed(Duration.zero);
    final closing = controller.close();
    expect(identical(closing, controller.close()), isTrue);
    expect(seen, [PreferenceKind.high]);
    gate.complete();
    expect((await lease.ready).status, RequestStatus.superseded);
    expect((await closing).submitted, isTrue);
    expect(seen, [PreferenceKind.high, PreferenceKind.system]);
    expect(() => controller.acquire(const RatePreference.high()),
        throwsStateError);
  });
  test('serializes async writes and supersedes old in-flight results',
      () async {
    final gate = Completer<void>();
    final seen = <PreferenceKind>[];
    final controller = RateController((preference) async {
      seen.add(preference.kind);
      if (seen.length == 1) await gate.future;
      return RateRequestResult(
          status: RequestStatus.submitted, preference: preference);
    });
    final old = controller.acquire(const RatePreference.high());
    await Future<void>.delayed(Duration.zero);
    final newer = controller.acquire(RatePreference.content(24));
    gate.complete();
    expect((await old.ready).status, RequestStatus.superseded);
    expect((await newer.ready).submitted, true);
    expect(seen, [PreferenceKind.high, PreferenceKind.content]);
    await old.release();
    expect(controller.effectivePreference.kind, PreferenceKind.content);
    await newer.release();
    controller.dispose();
  });
  test('backend failure is observable and does not poison future requests',
      () async {
    var first = true;
    final controller = RateController((preference) async {
      if (first) {
        first = false;
        throw StateError('native failure');
      }
      return RateRequestResult(
          status: RequestStatus.submitted, preference: preference);
    });
    final lease = controller.acquire(const RatePreference.high());
    expect((await lease.ready).status, RequestStatus.failed);
    expect((await lease.release()).submitted, true);
    expect(identical(lease.release(), lease.release()), true);
    controller.dispose();
  });
}
