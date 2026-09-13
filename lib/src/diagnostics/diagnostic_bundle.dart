import 'dart:collection';
import '../control/rate_controller.dart';
import '../models/session_report.dart';
import '../telemetry/export_policy.dart';
import 'configuration_doctor.dart';

/// A bounded snapshot for an application to save or share explicitly.
/// The package never uploads it or supplies a network destination.
class DiagnosticBundle {
  /// Captures bounded request/session evidence and caller-provided reproduction
  /// context. Caller-provided environment identity is never invented.
  DiagnosticBundle(
      {required ConfigurationReport configuration,
      SessionReport? session,
      Iterable<RefreshRateDecision> decisions = const [],
      Map<String, String> environment = const {},
      String? reproduction,
      TelemetryExportPolicy? policy}) {
    if (environment.length > 32 ||
        environment.entries
            .any((e) => e.key.length > 128 || e.value.length > 1024) ||
        (reproduction?.length ?? 0) > 4096) {
      throw ArgumentError('Diagnostic context exceeds bounded limits');
    }
    final retained = Queue<RefreshRateDecision>();
    var droppedDecisions = 0;
    for (final decision in decisions) {
      if (retained.length == 200) {
        retained.removeFirst();
        droppedDecisions++;
      }
      retained.add(decision);
    }
    _json = (policy ?? TelemetryExportPolicy()).encode({
      'schemaVersion': 1,
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
      'configuration': configuration.toMap(),
      'environment': environment,
      'reproduction': reproduction,
      'session': session?.toMap(),
      'droppedDecisions': droppedDecisions,
      'decisions': retained.map((d) => d.toMap()).toList(),
      'observationAssociation':
          'The configuration snapshot was collected after these package decisions; sequence does not establish fulfilment or causality.',
    });
  }
  late final String _json;

  /// Already filtered, size-checked JSON; subsequent caller mutations cannot change it.
  String toJson() => _json;

  /// One complete bundle per line.
  String toNdjson() => '$_json\n';
}
