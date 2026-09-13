# refresh_rate

Request appropriate refresh rates and measure **Flutter frame production** with explicit source and coverage information.

Rate requests are preferences, not guarantees. Native display information, Flutter frame cadence, and display-link/browser callback cadence are separate measurements. Physical presentation FPS is unavailable unless a qualified presentation source is added.

## Installation

Requires Flutter 3.24 or later and Dart 3.5 or later.

```sh
flutter pub add refresh_rate
```

```dart
import 'package:flutter/material.dart';
import 'package:refresh_rate/refresh_rate.dart';
```

The examples below belong in your application's initialization, widget lifecycle or diagnostic flow. Retain controllers while their workload is active and dispose them when it ends.

## Request a preference

```dart
WidgetsFlutterBinding.ensureInitialized();

final result = await RefreshRate.preferMax();
print('${result.status.name}: ${result.backend}');
// submitted means the named backend accepted the request, not that 120 Hz was reached.

await RefreshRate.preferDefault();
```

Use independently owned leases when multiple parts of the app need preferences:

```dart
final lease = RefreshRate.request(
  const RatePreference.high(),
  owner: 'game-route',
  priority: 100,
);
final result = await lease.ready;
// ...
await lease.release(); // idempotent; does not clear another owner's preference
```

Higher priority wins, with newer requests breaking ties. Temporary boosts use expiring leases. Backend submissions are serialized, and superseded results are identified explicitly. `disable()` and `preferDefault()` release the imperative owner; they preserve independent scopes and content requests.

## Platform support

| Platform | Queries | Control |
|---|---|---|
| Android | Active display rate/modes, power/thermal state, API 30 thermal headroom, API 36 ARR evidence and suggested rates | Qualified live FlutterSurfaceView vote; explicit window fallback for ordinary high-rate preferences. API 35 categories/touch boost and API 24 sustained mode where supported. Fixed-source/at-least requests require a surface that supports their semantics. |
| iOS | Screen maximum, power/thermal state; explicit bounded display-link observation | Flutter-engine control is unsupported. No process-wide swizzling or forced default 60 FPS cap. |
| macOS | App window's display/modes, thermal state and supported low-power state | Flutter-engine control is unsupported; the plugin does not pretend a helper display link controls Flutter. |
| Windows | App window's monitor and display path | Query only. |
| Linux | App window's monitor via GDK; unknown mode capabilities remain unavailable | Query only. |
| Web | Raw requestAnimationFrame callback cadence, bounded by visibility/cancellation/timeout | Unsupported; browser scheduling remains in control. |

`RefreshRate.capabilities()` reports per-operation support. Results distinguish `submitted`, `unsupported`, `unavailable`, `failed`, and `superseded`. The native surface backend currently scopes content votes to the Flutter surface; it does not acquire or control an arbitrary video plugin's private playback surface.

Sessions, reports, stutter analysis, quality advice and telemetry use shared Dart code across all six platforms. Native health data and scheduling controls are available only where the backend supports them. Quality advice can use Flutter phase timings even without a native thermal source.

Android API 36 support uses `Display.hasArrSupport()`, display-defined suggested normal/high rates, and `FRAME_RATE_COMPATIBILITY_AT_LEAST`. High preferences use the display-suggested high rate when available. Surface lookup is matched to the registering Flutter engine; window fallback is refused if it would affect a different engine. Control preserves resolution rather than silently selecting a different-resolution mode. Supported SDK paths still require physical-device qualification for OEM, composition, and lifecycle behavior.

For eligible iOS ProMotion devices, add this Boolean inside the application's `ios/Runner/Info.plist` dictionary:

```xml
<key>CADisableMinimumFrameDurationOnPhone</key>
<true/>
```

`RefreshRate.doctor()` checks this application setting. The flag does not guarantee a refresh rate or enable this plugin to control Flutter's iOS engine cadence.

## Declarative preferences

```dart
RefreshRateScope(
  preference: const RatePreference.high(),
  child: const GamePage(),
)
```

Nested scopes arbitrate by depth. Background apps, inactive routes and disabled `TickerMode` release their preferences. Set `active: false` for custom hidden tabs that do not expose visibility through routes or TickerMode.

For animations, attach `RefreshRate.boostDuring(controller)` and retain its returned disposer. Call that disposer before disposing the animation controller. Running, repeating and reverse animations are supported.

## Opt-in automatic policies

```dart
final policy = RefreshRate.auto(policy: RefreshRatePolicy.balanced);

RefreshRateInteraction(
  controller: policy,
  child: const MyApp(),
);

// Dispose with the owning widget/service:
await policy.dispose();
```

The interaction widget reports pointer activity and scrolling, including ballistic flings. Other workloads can call `beginActivity()` and `endActivity(token)` directly. There is no automatic scan of arbitrary Flutter animations or third-party video players.

- `system`: no policy preference.
- `balanced`: high during activity, then release after the idle delay.
- `performance`: high during activity, with twice the configured idle grace period.
- `battery`: normal-category preference during activity where supported, then release. Unsupported backends keep system policy.

Policies release their requests in the background and under reported low-power/serious-thermal constraints. Explicit higher-priority requests remain independently owned. No FPS feedback loop continuously produces frames or keeps increasing the requested rate. Energy/performance gains are not asserted without measurements.

## Exact content rates

```dart
final playerPreference = RefreshRateContentController();
final result = await playerPreference.update(
  sourceFps: 24000 / 1001,
  playbackSpeed: 1,
  playing: true,
  buffering: false,
  visible: true,
  strategy: FrameRateSwitchStrategy.seamlessOnly,
);
await playerPreference.dispose();
```

Wire these values to your player's actual state. Non-seamless transitions require explicit opt-in and native support. Unsupported semantics produce a visible result. This adapter does not pace or release video frames itself.

## Source-qualified diagnostics

```dart
final diagnostics = await RefreshRate.diagnostics(view: View.of(context));
print(diagnostics.requestedPreference.kind);
print(diagnostics.nativeReportedDisplayHz.value);
print(diagnostics.engineReportedDisplayHz.value);
print(diagnostics.nativeCallbackCadenceHz.value);
print(diagnostics.presentedFps); // null

final displays = RefreshRate.displays; // Flutter-reported display identities
```

Observations include source, scope, collection time and, where meaningful, sample count/window. Flutter display information is not an observed engine frame-rate cap. `RefreshRate.observeNativeCadence()` explicitly enables a bounded observer where available; that observer changes the workload and does not measure Flutter presentation.

Legacy `DisplayInfo` numeric fields use **zero for unavailable**, never fabricated 60 Hz. Prefer the nullable observation getters. `reportedVariableRefreshRate` retains unknown capability; the legacy boolean cannot express it. Apple supported/minimum rate lists are not invented.

## Whole-session benchmarks

```dart
final session = RefreshRate.startSession('feed_scroll', expectedFps: 120);
session.setTag('screen', 'feed');
session.mark('scroll_start');

// Exercise a continuously active workload.
// Call session.pause()/resume() around intentionally excluded idle portions.
// Call session.setExpectedFps(24) when workload expectations change.

final report = await session.end();
print(report.flutterFrameCadenceFps);
print(report.percentilesMs['rasterP99']);
print(report.phaseOverrunPercent);
print(report.boundaryCoverageComplete);
print(report.toJson());
print(report.toMarkdown());
```

Collection uses one shared Flutter timing callback. Recent history is bounded to 600 records; independent whole-session aggregates and worst-frame records survive eviction. Histograms have at most 1% relative bucket width; counts and means are exact, while quantiles and partial-tail means are approximate. A 1% low requires at least 100 valid intervals; 0.1% requires 1,000.

The report separates:

- Flutter frame cadence, based on valid inter-frame intervals.
- UI and raster budget overruns, using the expected workload rate at event time.
- Pipeline latency, from vsync start to raster finish.
- Cadence gaps, estimated when an interval exceeds 1.5 times the expected interval.
- Physical presentation measurements, which remain unavailable.

Sessions filter background/warmup and boundary records by event time, using Flutter's raster-finish wall-time bridge on native platforms and `performance.timeOrigin` for relative browser timings. Tags, target changes, power and thermal transitions are segmented instead of retroactively applied to an entire delayed batch. Ending waits up to 1.1 seconds by default for batched timing delivery. Missing timestamps, missing end witnesses, invalid ordering or dropped metadata make coverage incomplete. No additional animation is scheduled to manufacture that witness.

Provide expected FPS only for a known workload. Without it, budget-based judgments remain inconclusive. Continuous-workload coverage also accounts for the expected frames over the active duration, so brief smooth rendering followed by long idle time cannot pass a continuous benchmark. Use profile/release builds and physical devices for performance qualification.

## CI gates and comparisons

```dart
final result = report.evaluate(RefreshRateThresholds(
  minAverageFps: 110,
  minOnePercentLowFps: 80,
  maxPhaseOverrunPercent: 5,
  maxP99RasterMs: 8,
));
expect(result.passed, isTrue, reason: '${result.failures} ${result.missingEvidence}');
```

Gates require sufficient samples, known workload coverage, non-debug builds and complete boundaries by default. Missing evidence cannot pass. Comparisons use `report.compareTo(baseline, environmentKey: ..., baselineEnvironmentKey: ...)`; the application supplies a stable device/build/scenario identity. Incompatible or missing identities yield an inconclusive comparison.

JSON and CSV remain available with report schema version 2. Legacy `missedFramePercent` is an alias for phase overruns, not a count of physically missed frames. `observedAvgHz` is null for timing-only sessions.

## Overlays and optional telemetry

`showFPS()`, `showHz()`, `showOverlay()` and `hideOverlay()` remain available. Updates are event-driven and throttled; Hz-only does not subscribe to Flutter timings or run a ticker. A graph shows recent pipeline latency. Single-record batches are not used to sustain overlay refresh loops, so sparse activity can display idle/stale. Benchmark with the overlay off.

`FrameTelemetry` sends sampled, bounded batches to an application-provided asynchronous sink. It tracks drops and failures, limits concurrent exports and disables further export after a sink timeout. It configures no network destination. Dispose it when unused.

`RefreshRateTrace` optionally emits request decisions to the Dart timeline and registers the read-only `ext.refresh_rate.diagnostics` service extension for DevTools clients. This is an integration endpoint, not a standalone DevTools extension UI.

## Configuration and diagnostic bundles

`await RefreshRate.doctor(view: View.of(context))` reports setup and capability limitations with stable finding codes and suggested actions. It does not claim that setup guarantees performance.

```dart
final configuration = await RefreshRate.doctor(view: View.of(context));
for (final finding in configuration.findings) {
  print('${finding.code}: ${finding.message} ${finding.action}');
}
```

Missing native registration, failed platform queries and query timeouts produce a `queryFailed` finding. The optional `view` identifies the Flutter display observation; it does not create an independent native controller for that view.

```dart
final bundle = await RefreshRate.diagnosticBundle(
  session: report,
  environment: {'scenario': 'feed_scroll', 'build': 'app-build-id'},
  reproduction: 'Open the feed and fling twice',
  policy: TelemetryExportPolicy(
    allowedTags: {'route', 'screen'},
    maxBytes: 262144,
    redact: (path, value) => path.endsWith('.owner') ? null : value,
  ),
);
final json = bundle.toJson(); // Save/share only through your application.
```

The bundle includes capabilities, source-qualified observations, recent decisions and reproduction context, plus bounded frame evidence when a session report is supplied. Oversized exports fail explicitly. Native observations are associated with the preceding decisions without claiming that a request was fulfilled or caused a change.

`JsonFrameTelemetry` applies the same filtering to sampled batches, with one JSON batch per line:

```dart
final telemetry = JsonFrameTelemetry(
  sampleEvery: 10,
  capacity: 256,
  batchSize: 64,
  policy: TelemetryExportPolicy(allowedTags: {'route', 'screen'}),
  sink: (ndjson) async {
    // Save the batch through your application's chosen storage or transport.
  },
);
// Collect while the workload runs, then stop with its owner.
await telemetry.dispose();
```

`exportedSamples` counts samples acknowledged by the sink before timeout. `failedSamples`, `failedBatches`, `droppedSamples` and `lastError` expose delivery problems. Disposal discards queued samples and waits for bounded in-flight work; `flush()` sends one batch when a final export is needed. Neither export API configures a network destination. Tags are all allowed by default; supply an allowlist and redaction callback for your application's context. The default export limit is 262,144 UTF-8 bytes per bundle or NDJSON batch.

## Stutters, milestones and report inspection

Session reports include consecutive cadence-gap episodes, recovery/interruption state, longest budgeted interval and long-stall counts. A long stall must both exceed 1.5 workload budgets and last at least 100 ms. Idle work with no expected cadence is not classified as a stutter workload.

```dart
final session = RefreshRate.startSession('checkout', expectedFps: 60,
    includeRenderingContext: true);
session.markInteraction('pay_tapped'); // Call in the actual input handler.
session.markReady(); // Application-declared readiness, distinct from first frame.
```

`report.milestones` separates the first observed Flutter frame, readiness and input-to-next-observed-frame latency. The input proxy does not prove that the next frame contains the response, and is not touch-to-photon latency. `RefreshRateNavigatorObserver(session: () => activeSession)` adds named-route context to an app-owned session; supply its `routeName` mapper to sanitize route identifiers.

`includeRenderingContext` opts into Flutter's layer/picture raster-cache counters, not heap or GPU-allocation profiling. It is also available on `FrameTelemetry`. Session time is anchored to a monotonic clock; detected wall-clock discontinuities make event coverage incomplete.

`RefreshRateReportView(report: report, decisions: RefreshRate.decisionHistory)` displays recent build/raster/pipeline costs, workload budgets, percentiles, stutters and request history on a separate diagnostics route. It inspects completed evidence without starting a collector. `RefreshRateTrace.setSessionReport(report, policy: ...)` supplies a filtered report to the read-only `ext.refresh_rate.session` endpoint after a `RefreshRateTrace` instance has registered the extensions. This endpoint is not a standalone DevTools tab.

## Shadow mode and application quality advice

`RefreshRate.auto(shadowMode: true)` records proposed decisions in `history` and `decisions` without acquiring native requests. Capability-aware policies preserve system scheduling when their preference is unsupported.

```dart
final shadow = RefreshRate.auto(shadowMode: true);
final activity = shadow.beginActivity();
// Exercise the workload; inspect shadow.history or listen to shadow.decisions.
shadow.endActivity(activity);
await shadow.dispose();
```

```dart
final quality = RefreshRate.adviseQuality(
  onRecommendation: (advice) {
    // Your application decides whether to adjust effects or background work.
  },
);
quality.setWorkload(60); // Explicitly active, continuous work.
// Run the workload before stopping collection.
quality.setWorkload(null); // Stop collecting during idle periods.
await quality.dispose();
```

Quality advice uses consecutive phase-budget overruns, reported power/thermal state and sustained healthy-frame recovery. Missing frames do not establish recovery. Visual changes remain application-owned.

## Android thermal and sustained workload support

```dart
final headroom = await RefreshRate.thermalHeadroom(forecastSeconds: 10);
print(headroom.value); // null means unavailable; zero is a valid reading.

final sustained = RefreshRate.sustainedPerformance(
  previousEnabled: false, // Your application's known prior window preference.
  duration: const Duration(minutes: 10),
);
final outcome = await sustained.ready;
print(outcome.status.name);
// Run the sustained workload before releasing the lease.
await sustained.release();
```

Thermal headroom requires Android API 30; readings may be unavailable on individual devices. Zero is valid. Polling is limited to once per ten seconds across consumers. `watchThermalHeadroom()` is foreground-only and must be disposed. Forecasts require native warmup; cached values retain their observation time.

An active quality controller can receive a fresh reading through `updateThermalHeadroom(headroom.value)`. Supplying null clears the optional reading. The controller does not start thermal-headroom polling automatically.

Sustained mode requires native device support and API 24. It requests consistency for long workloads and can reduce peak performance. Android exposes no public getter for the prior sustained state, so the application must supply its known baseline. Overlapping leases share that baseline; the final owner restores it. The application must coordinate this window-level mode with other plugins. Other platforms return unsupported.

On API 35+, `setTouchBoost()` captures the prior native state. `resetTouchBoost()` restores it when still owned; activity recreation restores/reapplies the owned preference. Unsupported legacy calls report errors. Native attachment and deferred request outcomes are available in `diagnostics.nativeMetadata`.

## Repeated-run comparisons

`BenchmarkSeries(reports: runs, environmentKey: deviceBuildScenario)` compares at least three qualified runs against another series. `compareTo()` exposes per-run distributions and a caller-selected median regression gate. Missing coverage, incompatible workloads/environments and unusable zero baselines remain inconclusive. These are descriptive comparisons, not statistical-significance claims. Session reports also support one-report-per-line `toNdjson()` exports.

```dart
final baseline = BenchmarkSeries(
  reports: baselineRuns,
  environmentKey: comparisonEnvironment,
);
final current = BenchmarkSeries(
  reports: currentRuns,
  environmentKey: comparisonEnvironment,
);
final comparison = current.compareTo(
  baseline,
  metric: BenchmarkMetric.rasterP99,
  maxRegressionPercent: 5,
);
print(comparison.passed);
print(comparison.missingEvidence);
```

`baselineRuns` and `currentRuns` are lists of completed `SessionReport` objects from repeated executions. Use a matching environment key only when device, build configuration, renderer and workload are comparable. Other supported metrics are `flutterCadence` and `phaseOverrunPercent`; positive regression percentages mean worse results for the selected metric.

## Upgrading from 1.0.2

Version 1.0.3 includes API and measurement changes:

- Refresh-control methods return `RateRequestResult`. Update explicitly typed `Future<void>` wrappers and inspect the result before relying on a submitted preference.
- `disable()` and `preferDefault()` release the imperative request. Release each independently owned lease or dispose its scope/controller to remove those preferences.
- The iOS display-link swizzle is removed. iOS and macOS engine-control requests report unsupported; queries and Flutter timing collection remain available.
- Report schema version 2 separates Flutter cadence, phase overruns and pipeline latency. FPS lows use inter-frame intervals. Update consumers of the earlier metric definitions.
- `observedAvgHz` is nullable. A timing-only session does not provide a native callback-rate observation. Legacy `missedFramePercent` means phase overruns, not physically missed frames.

See the [1.0.3 changelog](CHANGELOG.md#103) for the release changes.

## Current limits

JankStats, MetricKit and native player-surface integrations are not bundled. There is no standalone DevTools inspector or independent per-window/scene measurement controller. Native View/HWUI counters and callback cadence do not automatically establish Flutter presentation metrics.

Windows and Linux runtime integration qualification remains outstanding. Physical presentation FPS, energy savings, sustained thermal performance and instrumentation overhead require physical-device measurements; functional integration tests do not establish those results.
