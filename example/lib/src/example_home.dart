import 'dart:async';

import 'package:flutter/material.dart';
import 'package:refresh_rate/refresh_rate.dart';

import 'models/action_spec.dart';
import 'models/info_item.dart';
import 'sections/action_panel.dart';
import 'sections/benchmark_panel.dart';
import 'sections/display_info_panel.dart';
import 'sections/hero_panel.dart';
import 'sections/scroll_test_panel.dart';
import 'sections/status_panel.dart';

class ExampleHome extends StatefulWidget {
  const ExampleHome({super.key});

  @override
  State<ExampleHome> createState() => _ExampleHomeState();
}

class _ExampleHomeState extends State<ExampleHome> {
  RefreshRateSession? _session;
  SessionReport? _lastReport;
  String _status = 'System nominal';
  StreamSubscription<DisplayInfo>? _infoSubscription;

  @override
  void initState() {
    super.initState();
    _infoSubscription = RefreshRate.onChanged.listen((_) {
      if (mounted) setState(() {});
    });
    RefreshRate.refresh().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _infoSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = RefreshRate.info;
    final width = MediaQuery.sizeOf(context).width;
    final wideLayout = width >= 1040;
    final largeHero = width >= 760;
    final frameBudgetMs = info.currentRate > 0 ? 1000 / info.currentRate : 0.0;
    final maxBudgetMs = info.maxRate > 0 ? 1000 / info.maxRate : 0.0;
    final supportedRatesText = _supportedRatesText(info);
    final liveStateColor = _liveStateColor(context, info);

    final displayInfoItems = [
      InfoItem('OS-reported rate', _hz(info.nativeReportedDisplayHz)),
      InfoItem('Display maximum', _hz(info.displayModeMaxHz)),
      InfoItem('Known minimum', _hz(info.minRate > 0 ? info.minRate : null)),
      InfoItem('Supported rates', supportedRatesText),
      InfoItem('VRR / LTPO',
          info.reportedVariableRefreshRate?.toString() ?? 'Unknown'),
      InfoItem(
        'ProMotion ready',
        RefreshRate.isProMotionReady ? 'Ready' : 'Unavailable',
      ),
      InfoItem(
        'Low power mode',
        RefreshRate.isLowPowerMode ? 'Enabled' : 'Off',
      ),
      InfoItem('Thermal state', RefreshRate.thermalState.name),
      InfoItem('Android API', '${info.androidApiLevel ?? 'n/a'}'),
      InfoItem('Display server', info.displayServer ?? 'n/a'),
      InfoItem('Monitor count', '${info.monitorCount}'),
      InfoItem('Engine display information', _hz(info.engineReportedDisplayHz)),
    ];

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF151515), Color(0xFF101010), Color(0xFF131313)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 12, 16, width >= 760 ? 24 : 16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1320),
                child: wideLayout
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 7,
                            child: Column(
                              children: [
                                HeroPanel(
                                  info: info,
                                  status: _status,
                                  frameBudgetMs: frameBudgetMs,
                                  maxBudgetMs: maxBudgetMs,
                                  liveStateColor: liveStateColor,
                                  largeHero: largeHero,
                                  supportedRatesText: supportedRatesText,
                                ),
                                const SizedBox(height: 16),
                                DisplayInfoPanel(items: displayInfoItems),
                                const SizedBox(height: 16),
                                ActionPanel(
                                  eyebrow: 'Control',
                                  title: 'Rate Requests',
                                  subtitle:
                                      'Exercise the plugin APIs directly and verify device behavior against the live telemetry above.',
                                  actions: _controlActions(),
                                ),
                                const SizedBox(height: 16),
                                ScrollTestPanel(info: info),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 4,
                            child: Column(
                              children: [
                                ActionPanel(
                                  eyebrow: 'Overlay',
                                  title: 'Verification HUD',
                                  subtitle:
                                      'Toggle lightweight or full in-app overlays to validate frame pacing without leaving the example app.',
                                  actions: _overlayActions(),
                                  footer: _overlayFooter(),
                                ),
                                const SizedBox(height: 16),
                                BenchmarkPanel(
                                  actions: _benchmarkActions(),
                                  reportItems: _lastReport == null
                                      ? null
                                      : _reportItems(_lastReport!),
                                ),
                                const SizedBox(height: 16),
                                StatusPanel(status: _status),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          HeroPanel(
                            info: info,
                            status: _status,
                            frameBudgetMs: frameBudgetMs,
                            maxBudgetMs: maxBudgetMs,
                            liveStateColor: liveStateColor,
                            largeHero: largeHero,
                            supportedRatesText: supportedRatesText,
                          ),
                          const SizedBox(height: 16),
                          DisplayInfoPanel(items: displayInfoItems),
                          const SizedBox(height: 16),
                          ActionPanel(
                            eyebrow: 'Control',
                            title: 'Rate Requests',
                            subtitle:
                                'Exercise the plugin APIs directly and verify device behavior against the live telemetry above.',
                            actions: _controlActions(),
                          ),
                          const SizedBox(height: 16),
                          ActionPanel(
                            eyebrow: 'Overlay',
                            title: 'Verification HUD',
                            subtitle:
                                'Toggle lightweight or full in-app overlays to validate frame pacing without leaving the example app.',
                            actions: _overlayActions(),
                            footer: _overlayFooter(),
                          ),
                          const SizedBox(height: 16),
                          BenchmarkPanel(
                            actions: _benchmarkActions(),
                            reportItems: _lastReport == null
                                ? null
                                : _reportItems(_lastReport!),
                          ),
                          const SizedBox(height: 16),
                          ScrollTestPanel(info: info),
                          const SizedBox(height: 16),
                          StatusPanel(status: _status),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<ActionSpec> _controlActions() {
    return [
      ActionSpec(
        label: 'ENABLE',
        accent: const Color(0xFF36FF8B),
        outlined: false,
        onTap: () async {
          final result = await RefreshRate.enable();
          _setStatus("${result.status.name}: ${result.backend}");
        },
      ),
      ActionSpec(
        label: 'DISABLE',
        accent: const Color(0xFFFFBA20),
        outlined: true,
        onTap: () async {
          final result = await RefreshRate.disable();
          _setStatus("${result.status.name}: ${result.backend}");
        },
      ),
      ActionSpec(
        label: 'PREFER MAX',
        accent: const Color(0xFF00F0FF),
        outlined: true,
        onTap: () async {
          final result = await RefreshRate.preferMax();
          _setStatus("${result.status.name}: ${result.backend}");
        },
      ),
      ActionSpec(
        label: 'DEFAULT',
        accent: const Color(0xFFB9CACB),
        outlined: true,
        onTap: () async {
          final result = await RefreshRate.preferDefault();
          _setStatus("${result.status.name}: ${result.backend}");
        },
      ),
      ActionSpec(
        label: 'MATCH 24FPS',
        accent: const Color(0xFF00F0FF),
        outlined: false,
        onTap: () async {
          final result = await RefreshRate.matchContent(24.0);
          _setStatus(
              "${result.status.name}: ${result.backend}${result.message == null ? '' : ' — ${result.message}'}");
        },
      ),
      ActionSpec(
        label: 'BOOST 3S',
        accent: const Color(0xFFFFBA20),
        outlined: false,
        onTap: () async {
          final result = await RefreshRate.boost(const Duration(seconds: 3));
          _setStatus(
              "${result.status.name}: ${result.backend}${result.message == null ? '' : ' — ${result.message}'}");
        },
      ),
      ActionSpec(
        label: 'CATEGORY HIGH',
        accent: const Color(0xFF36FF8B),
        outlined: true,
        onTap: () async {
          final result = await RefreshRate.category(RateCategory.high);
          _setStatus(
              "${result.status.name}: ${result.backend}${result.message == null ? '' : ' — ${result.message}'}");
        },
      ),
      ActionSpec(
        label: 'TOUCH BOOST',
        accent: const Color(0xFF00F0FF),
        outlined: true,
        onTap: () async {
          try {
            await RefreshRate.setTouchBoost(true);
            _setStatus('Touch hint submitted');
          } catch (error) {
            _setStatus('Touch hint unavailable: $error');
          }
        },
      ),
    ];
  }

  List<ActionSpec> _overlayActions() {
    return [
      ActionSpec(
        label: 'SHOW FPS',
        accent: const Color(0xFF00F0FF),
        outlined: true,
        onTap: () {
          RefreshRate.showFPS();
          _setStatus('FPS overlay shown');
        },
      ),
      ActionSpec(
        label: 'SHOW HZ',
        accent: const Color(0xFF36FF8B),
        outlined: true,
        onTap: () {
          RefreshRate.showHz();
          _setStatus('Hz overlay shown');
        },
      ),
      ActionSpec(
        label: 'FULL OVERLAY',
        accent: const Color(0xFFFFBA20),
        outlined: false,
        onTap: () {
          RefreshRate.showOverlay();
          _setStatus('Full overlay mounted');
        },
      ),
      ActionSpec(
        label: 'HIDE',
        accent: const Color(0xFFB9CACB),
        outlined: true,
        onTap: () {
          RefreshRate.hideOverlay();
          _setStatus('Overlay hidden');
        },
      ),
    ];
  }

  List<ActionSpec> _benchmarkActions() {
    return [
      ActionSpec(
        label: _session == null ? 'START SESSION' : 'SESSION ACTIVE',
        accent: const Color(0xFF36FF8B),
        outlined: _session != null,
        onTap: _session == null
            ? () {
                setState(() {
                  _session = RefreshRate.startSession('example_scroll');
                  _status = 'Benchmark session running';
                });
              }
            : null,
      ),
      ActionSpec(
        label: 'END SESSION',
        accent: const Color(0xFFFFBA20),
        outlined: true,
        onTap: _session == null
            ? null
            : () async {
                final activeSession = _session;
                if (activeSession == null) return;
                final report = await activeSession.end();
                if (!mounted) return;
                setState(() {
                  _lastReport = report;
                  _session = null;
                  _status = 'Session ended: ${report.verdict.name}';
                });
              },
      ),
    ];
  }

  Widget _overlayFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E0E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: RefreshRate.isOverlayVisible
                  ? const Color(0xFF36FF8B)
                  : const Color(0xFF3B494B),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            RefreshRate.isOverlayVisible
                ? 'Overlay currently visible'
                : 'Overlay currently hidden',
            style: const TextStyle(
              color: Color(0xFFB9CACB),
            ),
          ),
        ],
      ),
    );
  }

  List<InfoItem> _reportItems(SessionReport report) {
    return [
      InfoItem('Verdict', report.verdict.name),
      InfoItem('Bottleneck', report.likelyBottleneck.name),
      InfoItem('Avg FPS', report.avgFps.toStringAsFixed(1)),
      InfoItem(
          '1% Low',
          report.intervalCount >= 100
              ? report.onePercentLowFps.toStringAsFixed(1)
              : 'Insufficient data'),
      InfoItem('Phase overrun %',
          report.phaseOverrunPercent?.toStringAsFixed(1) ?? 'Unknown'),
      InfoItem('Valid duration', '${report.validDuration.inMilliseconds} ms'),
      InfoItem('Excluded', '${report.excludedDuration.inMilliseconds} ms'),
    ];
  }

  void _setStatus(String value) {
    if (mounted) setState(() => _status = value);
  }

  String _hz(double? rate) =>
      rate == null ? 'Unknown' : '${rate.toStringAsFixed(1)} Hz';

  String _supportedRatesText(DisplayInfo info) {
    if (info.supportedRates.isEmpty) return 'n/a';
    return info.supportedRates
        .map((rate) => '${rate.toStringAsFixed(0)}Hz')
        .join(' • ');
  }

  Color _liveStateColor(BuildContext context, DisplayInfo info) {
    if (RefreshRate.isLowPowerMode) return const Color(0xFFFFBA20);
    if (RefreshRate.thermalState.name != 'nominal') {
      return const Color(0xFFFFBA20);
    }
    if (info.currentRate >= info.maxRate && info.maxRate > 0) {
      return const Color(0xFF36FF8B);
    }
    return Theme.of(context).colorScheme.primary;
  }
}
