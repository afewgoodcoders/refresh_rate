import 'package:flutter/foundation.dart';
import '../control/rate_controller.dart';
import '../models/display_info.dart';
import '../models/rate_diagnostics.dart';

/// An actionable setup finding, separate from measured rendering performance.
class ConfigurationFinding {
  /// A stable code lets applications select or localize findings.
  const ConfigurationFinding(this.code, this.message, this.action);

  /// Stable machine-readable identifier.
  final String code;

  /// Observed limitation or configuration condition.
  final String message;

  /// Suggested application action.
  final String action;

  /// Serializable finding.
  Map<String, Object?> toMap() =>
      {'code': code, 'message': message, 'action': action};
}

/// Source-based configuration checks. A clean report is not performance proof.
class ConfigurationReport {
  /// Creates an immutable report from existing observations; no frames produced.
  ConfigurationReport(
      {required this.platform,
      required this.diagnostics,
      required List<ConfigurationFinding> findings})
      : findings = List.unmodifiable(findings);

  /// Backend family (web remains distinct from its host operating system).
  final String platform;

  /// Raw qualified observations used to produce findings.
  final RateDiagnostics diagnostics;

  /// Setup findings and supported next actions.
  final List<ConfigurationFinding> findings;

  /// Checks actual capabilities and setup, never guessed refresh rates.
  factory ConfigurationReport.inspect(
      {required DisplayInfo info,
      required RateDiagnostics diagnostics,
      required String platform,
      bool debugBuild = kDebugMode}) {
    final caps = diagnostics.capabilities;
    final findings = <ConfigurationFinding>[
      if (debugBuild)
        const ConfigurationFinding(
            'debugBuild',
            'Debug instrumentation changes frame costs.',
            'Use profile or release for performance comparisons.'),
      if (!caps.surfaceVoting && !caps.windowPreferences && !caps.engineControl)
        const ConfigurationFinding(
            'controlUnsupported',
            'This backend cannot control Flutter refresh scheduling.',
            'Use the supported queries and telemetry; inspect request results before relying on a policy.'),
      if (platform == 'ios' && info.iosProMotionEnabled != true)
        const ConfigurationFinding(
            'promotionConfiguration',
            'CADisableMinimumFrameDurationOnPhone is not enabled in the app bundle.',
            'Set this Info.plist Boolean to true for eligible ProMotion devices; it does not guarantee a cadence.'),
      if (caps.windowPreferences && !caps.surfaceVoting)
        const ConfigurationFinding(
            'windowFallback',
            'Only a window-level refresh hint is available.',
            'Fixed-source content needs a supported live rendering surface.'),
      if (caps.surfaceVoting)
        const ConfigurationFinding(
            'surfaceAttachment',
            'Surface API support does not establish a uniquely attached FlutterSurfaceView.',
            'Await each request and inspect backend/scope; texture and multi-engine hosts need explicit qualification.'),
      if (diagnostics.requestedPreference.kind == PreferenceKind.category &&
          !caps.categoryHints)
        const ConfigurationFinding(
            'categoryUnsupported',
            'The active request uses an unsupported category.',
            'Choose a supported preference or system policy.'),
      if (diagnostics.nativeReportedDisplayHz.value == null &&
          diagnostics.displayModeMaxHz.value == null)
        const ConfigurationFinding(
            'displayUnavailable',
            'No native display-rate source is available for this target.',
            'Query after attaching the view; on web use callback cadence with its source label.'),
      const ConfigurationFinding(
          'presentationUnavailable',
          'Flutter timings do not establish physical presentation FPS.',
          'Use a qualified platform presentation trace when physical presentation evidence is required.'),
    ];
    return ConfigurationReport(
        platform: platform, diagnostics: diagnostics, findings: findings);
  }

  /// Full evidence, capabilities and actionable findings.
  Map<String, Object?> toMap() => {
        'schemaVersion': 1,
        'platform': platform,
        'diagnostics': diagnostics.toMap(),
        'findings': findings.map((f) => f.toMap()).toList()
      };
}
