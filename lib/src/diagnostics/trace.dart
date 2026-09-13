import 'dart:async';
import 'dart:developer' as developer;
import 'dart:convert';
import '../refresh_rate.dart';
import '../control/rate_controller.dart';
import '../models/session_report.dart';
import '../telemetry/export_policy.dart';

/// Optional Dart timeline/DevTools service integration. No collector is enabled.
class RefreshRateTrace {
  /// Registers a reusable read-only service extension and begins decision tracing.
  RefreshRateTrace() {
    _subscription = RefreshRate.onDecision.listen(_decision);
    if (!_registered) {
      _registered = true;
      developer.registerExtension(
          'ext.refresh_rate.session',
          (_, __) async => developer.ServiceExtensionResponse.result(
              _sessionJson ??
                  '{"available":false,"reason":"No completed session supplied"}'));
      developer.registerExtension('ext.refresh_rate.diagnostics',
          (_, __) async {
        final diagnostics = await RefreshRate.diagnostics();
        return developer.ServiceExtensionResponse.result(jsonEncode({
          'schemaVersion': 1,
          'requestedPreference': diagnostics.requestedPreference.toMap(),
          'nativeDisplayHz': diagnostics.nativeReportedDisplayHz.toMap(),
          'engineDisplayHz': diagnostics.engineReportedDisplayHz.toMap(),
          'nativeCallbackHz': diagnostics.nativeCallbackCadenceHz.toMap(),
          'presentedFps': null,
          'decisions': RefreshRate.decisionHistory
              .map((event) => {
                    'time': event.timestamp.toIso8601String(),
                    'owner': event.owner,
                    'reason': event.reason,
                    'status': event.result.status.name,
                    'backend': event.result.backend,
                    'preference': event.result.preference.toMap(),
                  })
              .toList(),
        }));
      });
    }
  }
  static bool _registered = false;
  static String? _sessionJson;

  /// Supplies a bounded, privacy-filtered completed report for DevTools clients.
  /// Clear it with null when the application no longer needs the evidence.
  static void setSessionReport(SessionReport? report,
      {TelemetryExportPolicy? policy}) {
    _sessionJson = report == null
        ? null
        : (policy ?? TelemetryExportPolicy()).encode(report.toMap());
  }

  StreamSubscription<RefreshRateDecision>? _subscription;
  void _decision(RefreshRateDecision event) =>
      developer.Timeline.instantSync('refresh_rate.request', arguments: {
        'owner': event.owner,
        'reason': event.reason,
        'status': event.result.status.name,
        'backend': event.result.backend,
        'kind': event.result.preference.kind.name,
        'fps': event.result.preference.fps
      });

  /// Adds a timeline marker for correlation with a session marker or native trace.
  void mark(String label) =>
      developer.Timeline.instantSync('refresh_rate.marker',
          arguments: {'label': label});

  /// Stops decision tracing. Dart service extensions are process registrations.
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
