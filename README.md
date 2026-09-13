# refresh_rate

Request appropriate refresh rates and measure **Flutter frame production** with explicit source and coverage information.

This checkout prepares the `2.0.0-dev.1` development prerelease. Rate requests are preferences, not guarantees. Native display information, Flutter frame cadence, and display-link/browser callback cadence are separate measurements. Physical presentation FPS is unavailable unless a qualified presentation source is added.

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
| Android | Active display rate/modes, power/thermal state, API 36 ARR evidence and suggested rates | Qualified live FlutterSurfaceView vote; transparent window fallback for ordinary high-rate preferences. API 35 view-category hints use the identified FlutterSurfaceView. Fixed-source/at-least requests require a surface that supports their semantics. |
| iOS | Screen maximum, power/thermal state; explicit bounded display-link observation | Flutter-engine control is unsupported. No process-wide swizzling or forced default 60 FPS cap. |
| macOS | App window's display and native modes | Flutter-engine control is unsupported; the plugin does not pretend a helper display link controls Flutter. |
| Windows | App window's monitor and display path | Query only. |
| Linux | App window's monitor via GDK; unknown mode capabilities remain unavailable | Query only. |
| Web | Raw requestAnimationFrame callback cadence, bounded by visibility/cancellation/timeout | Unsupported; browser scheduling remains in control. |

`RefreshRate.capabilities()` reports per-operation support. Results distinguish `submitted`, `unsupported`, `unavailable`, `failed`, and `superseded`. The native surface backend currently scopes content votes to the Flutter surface; it does not acquire or control an arbitrary video plugin's private playback surface.

Android API 36 support uses `Display.hasArrSupport()`, display-defined suggested normal/high rates, and `FRAME_RATE_COMPATIBILITY_AT_LEAST`. Control preserves resolution rather than silently selecting a different-resolution mode. Supported SDK paths still require physical-device qualification for OEM, composition, and lifecycle behavior.

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
- `battery`: normal-category preference during activity, then release.

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

Sessions filter background/warmup and boundary records by event time, using Flutter's raster-finish wall-time bridge. Tags, target changes, power and thermal transitions are segmented instead of retroactively applied to an entire delayed batch. Ending waits up to 1.1 seconds by default for batched timing delivery. Missing timestamps, missing end witnesses, invalid ordering or dropped metadata make coverage incomplete. No additional animation is scheduled to manufacture that witness.

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

## Validation and migration

See [migration notes](doc/migration.md), [implementation status](doc/implementation-status.md), and the [audit checklist](doc/improvement-plan.md).

Native View/HWUI counters, MetricKit aggregates and callback cadence are not automatically Flutter presentation measurements. JankStats, MetricKit and native player-surface integrations are not bundled in this revision. A qualified integration must establish its coverage before exposing presentation metrics.
