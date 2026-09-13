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

final result = await RefreshRate.enable();
print('${result.status.name}: ${result.backend}');
// submitted means the named backend accepted the request, not that 120 Hz was reached.

await RefreshRate.preferDefault();
```

`enable()` is the simple high-refresh preference entry point; `preferMax()` is equivalent. Call it after the app attaches its view, as shown in the runnable example.

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

Higher priority wins, with newer requests breaking ties. Temporary boosts use expiring leases. Backend submissions are serialized, and superseded results are identified explicitly. Unchanged successful preferences are reused without a native write (`result.reused`); failures remain retryable. Native attachment/recreation reapplies the active preference to its new target, including ordinary Activity replacement with a cached Flutter engine. Detachment clears the old native target; engine disposal clears the retained preference. Custom backends can use `controller.reconcile(force: true)` when their target changes. `disable()` and `preferDefault()` release the imperative owner; they preserve independent scopes and content requests.

## Platform support

| Platform | Queries | Control |
|---|---|---|
| Android | Active display rate/modes, power/thermal state, API 36 ARR evidence and suggested rates | Qualified live FlutterSurfaceView vote; explicit window fallback for ordinary high-rate preferences. API 35 categories and touch boost where supported. Fixed-source/at-least requests require a surface that supports their semantics. |
| iOS | Screen maximum, power/thermal state; explicit bounded display-link observation | Flutter-engine control is unsupported. No process-wide swizzling or forced default 60 FPS cap. |
| macOS | App window's display/modes, thermal state and supported low-power state | Flutter-engine control is unsupported; the plugin does not pretend a helper display link controls Flutter. |
| Windows | App window's monitor and display path | Query only. |
| Linux | App window's monitor via GDK; unknown mode capabilities remain unavailable | Query only. |
| Web | Raw requestAnimationFrame callback cadence, bounded by visibility/cancellation/timeout | Unsupported; browser scheduling remains in control. |

`RefreshRate.capabilities()` reports per-operation support. Results distinguish `submitted`, `unsupported`, `unavailable`, `failed`, and `superseded`. The native surface backend currently scopes content votes to the Flutter surface; it does not acquire or control an arbitrary video plugin's private playback surface.

Sessions, reports, stutter analysis, diagnostic exports use shared Dart code across all six platforms. Native health data and scheduling controls are available only where the backend supports them.

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

For animations, attach `RefreshRate.boostDuring(controller)` and retain its returned disposer. Call that disposer before disposing the animation controller. Running, repeating and reverse animations are supported. `AnimationController.stop()` sends no value/status notification, so the adapter checks for stops every 32 ms while it owns a running animation. That check releases the request and stops itself; it never schedules Flutter frames. Restarting the animation can reacquire the request.

## Opt-in automatic policies

```dart
final policy = RefreshRate.auto(policy: RefreshRatePolicy.balanced);
await policy.ready; // Initial device state and capabilities have been read.

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

The facade starts with system scheduling until initial display/power/thermal state and capabilities are read. A failed initial read leaves the policy at system scheduling. Policies release their requests in the background and under reported low-power/serious-thermal constraints. Explicit higher-priority requests remain independently owned. No FPS feedback loop continuously produces frames or keeps increasing the requested rate. Energy/performance gains are not asserted without measurements.

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

## Budget-aware overlays

```dart
RefreshRate.showOverlay(expectedFps: 120);
// Optional compact badges:
RefreshRate.showFPS(expectedFps: 120);
RefreshRate.showHz();
RefreshRate.hideOverlay();
```

The full overlay separates the requested preference (including numeric content FPS), OS-reported display Hz, explicit workload FPS and budget, Flutter cadence, and phase-budget overruns. For a 120 FPS workload the budget is 8.33 ms. Omitting `expectedFps` displays an unknown workload/budget; display capability is never substituted for application intent.

Updates are event-driven and throttled, including request decisions while the app is otherwise idle. Hz-only mode does not subscribe to Flutter timings. A graph shows recent pipeline latency and the declared workload budget. Single-record batches do not sustain repaint loops, so sparse activity can display idle/stale. Keep the overlay off when measuring the application itself; use the separate overhead experiment when measuring the observer.

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

Exports allow all tags by default. Supply an allowlist and redaction callback for your application's context; the default bundle limit is 262,144 UTF-8 bytes. Export-size failures are explicit, and the package configures no network destination. Completed reports support JSON, CSV, Markdown and one-report-per-line `toNdjson()`.

## Stutter episodes and workload context

Session reports retain bounded cadence-gap episodes, recovery/interruption state, longest budgeted interval and full-session stall counts. A long stall must both exceed 1.5 workload budgets and last at least 100 ms. Work with no declared cadence is not classified against a guessed budget.

Use `session.setTag()` and `session.mark()` for application-owned context. Target, power and thermal changes are exported as timestamped segments. Thermal degradation stays visible in the measured workload rather than being automatically excluded. Explicit pause/resume and background warmup delimit excluded periods. Session duration uses a monotonic clock; detected wall-clock discontinuities make event coverage incomplete.

## Policy shadow mode

```dart
final shadow = RefreshRate.auto(shadowMode: true);
await shadow.ready;
final activity = shadow.beginActivity();
// Exercise the workload; inspect shadow.history or listen to shadow.decisions.
shadow.endActivity(activity);
await shadow.dispose();
```

Shadow mode records bounded policy proposals without acquiring native preferences. Scopes and policies own preferences on the shared native surface/window; they do not give widget subtrees independent physical refresh rates.

## Touch-boost restoration

On Android API 35+, `setTouchBoost()` captures the prior native window setting. `resetTouchBoost()` restores it while still owned; activity recreation restores and reapplies the preference. Unsupported native calls report errors/results explicitly. This control is separate from temporary `boost()` leases and automatic activity policies.

```dart
final caps = await RefreshRate.capabilities();
if (caps.touchBoost) {
  await RefreshRate.setTouchBoost(true);
  // Keep the preference only for the lifetime of its application owner.
  final result = await RefreshRate.resetTouchBoost();
  print(result.status.name);
}
```

## Example and integration tests

The example initializes Flutter bindings, starts the app, and then inspects a refresh request after the first frame. Native registration can precede surface attachment; Android retains and reapplies the preference when its target becomes available. An unsupported plugin backend is distinct from a display that cannot run above 60 Hz.

The example's **COMPARE DEFAULT / HIGH** action runs the same animation with the same explicit workload budget under both preferences, with the overlay disabled. Debug reports remain inconclusive for performance gates. Use profile mode on a physical device to compare costs and inspect power/thermal segments alongside the result.

From `example/`, run the functional suite against a connected target:

```sh
flutter test integration_test/refresh_rate_test.dart -d <device-id>
flutter test integration_test/example_workflow_test.dart -d <device-id>
```

Run each integration file in a separate Flutter invocation so the desktop runner starts a fresh debug connection. For Android cached-engine Activity replacement, run `flutter test integration_test/retained_engine_test.dart -d <android-device-id> --reporter expanded` from `example/`. Its Activity harness is included only in debug builds.

From the package root, exercise actual Android Home/resume/rotation transitions:

```sh
python3 scripts/test_android_lifecycle.py --device <android-device-id>
python3 scripts/test_android_power.py --device <android-device-id>
```

The host scripts select the streaming `expanded` reporter explicitly, including on CI, so native actions occur while the Dart test is waiting for them. Rotation mode is queried through Settings; changes and restoration use `set-user-rotation` on API 30 and `user-rotation` on newer Android versions.

The power test simulates an unplugged battery at 50%, waits for PowerManager to observe that state, enables Battery Saver and checks the native event when Saver is disabled. Thermal constraints still take precedence. The host scripts restore the device settings they change. If an OEM sleeps during installation with Battery Saver enabled, add `--after-launch`: the host enables it once the app is visible, before the automatic controller is created, while leaving the facade cache uninitialized.

For paired overlay-off/on captures on a physical device, run from `example/`:

```sh
flutter drive --profile --dart-define=REQUIRE_PROFILE=true --driver=test_driver/refresh_rate.dart --target=integration_test/overlay_overhead_test.dart -d <device-id>
```

Unit tests cover deterministic metric and ownership edge cases. Integration tests use the registered plugin and actual Flutter frame callbacks. CI includes native integration jobs, browser execution and `python3 scripts/generate_bindings.py --check` to check all generated Pigeon bindings, including Linux GObject and both Apple source layouts.

## Upgrading from 1.0.2

Version 2.0.0 includes API and measurement changes:

- Refresh-control methods that returned `void` now return `Future<RateRequestResult>`; `setTouchBoost()` returns `Future<void>`. Existing standalone invocations can still compile, but awaiting the call lets you inspect completion and handle errors. `boostDuring()` now returns a disposer that must be called before disposing its animation controller.
- `disable()` and `preferDefault()` release the imperative request. Release each independently owned lease or dispose its scope/controller to remove those preferences.
- The iOS display-link swizzle is removed. iOS and macOS engine-control requests report unsupported; queries and Flutter timing collection remain available.
- Report schema version 2 separates Flutter cadence, phase overruns and pipeline latency. FPS lows use inter-frame intervals. Update consumers of the earlier metric definitions.
- `observedAvgHz` is nullable. A timing-only session does not provide a native callback-rate observation. Legacy `missedFramePercent` means phase overruns, not physically missed frames.

- `SessionState.finalizing` is new; update exhaustive enum switches. Session scoring requires an explicit workload rate rather than assuming display maximum.
- Unknown legacy numeric display rates use zero rather than a fabricated 60 Hz. Prefer nullable observation getters and guard divisions by rate.
- `isProMotionReady` is deprecated. Use `isProMotionConfigured` for the plist setting and nullable `supportsHighRefreshRate` for reported display capability. Neither indicates a guaranteed engine cadence.

See the [2.0.0 changelog](CHANGELOG.md#200) for the release changes.

## Design decisions for 2.0

This README is the maintained design and support reference for the package. Version 2.0 keeps four capabilities: refresh requests, diagnostics, overlays and benchmark sessions. `enable()` requests a high rate; it cannot guarantee a peak panel or engine rate. Optional scopes and policies own preferences on a shared surface/window, not independent subtree refresh rates. Apple engine control is unsupported. Scoring uses explicit workload budgets, and thermal/power degradation remains visible in session segments. Broader profiling, quality controls and router integrations are deferred.

## Current limits

The release focuses on refresh requests, diagnostics, the workload-budget overlay and benchmark sessions. Automatic route tagging, rich report viewers, DevTools extensions, streaming telemetry, repeated-run distributions, adaptive quality advice, sustained mode, thermal-headroom polling, raster-cache context and readiness/input proxies are outside the 2.0.0 public API. Manual session tags, diagnostic exports and single-report comparisons remain available.

JankStats, MetricKit and private player-surface integrations are not bundled. Independent per-window/scene controllers and Flutter presentation telemetry require further integration. Apple engine control remains unsupported; removing the swizzle does not remove the device's high-refresh capability.

Windows/Linux runtime results, physical refresh switching, energy savings, long thermal workloads and observer overhead must be qualified on their actual targets. Passing functional tests or emulator builds does not establish those physical performance results.
