# Changelog

## 2.0.0

- Corrected FPS lows to use frame intervals and kept benchmark aggregates for the full session. Added separate phase overruns, pipeline latency, cadence gaps, stutter episodes and recovery evidence.
- Added explicit workload budgets, pause/resume, timestamped tags and markers, monotonic session duration and complete-boundary checks. Power and thermal transitions remain visible in session segments.
- Added awaitable refresh results, independently owned requests, timed boosts, optional scopes/activity policies and fractional content preferences. Unchanged successful requests no longer repeat native writes; failed requests can retry.
- Fixed native refresh preferences being lost when a cached Flutter engine attaches to a replacement Android Activity. The old target is cleared before the active preference is reapplied.
- Fixed animation boosts surviving `AnimationController.stop()`. The adapter supports reuse and returns an explicit disposer.
- Automatic policies now read initial device state and capabilities before requesting a rate. Failed initialization preserves system scheduling. Added policy shadow mode.
- Added Android surface voting, API 35 categories and API 36 ARR/at-least support, using suggested high rates where available. Surface requests match the registering engine and reapply after attachment/recreation. Touch-boost reset restores the captured native setting.
- Removed the iOS display-link swizzle. Apple engine-control requests explicitly report unsupported; display queries and Flutter timing measurements remain available. Separated ProMotion plist configuration from high-refresh capability.
- Fixed late iOS view attachment, desktop monitor queries and browser timing clocks/short observations. Added macOS power and thermal notifications.
- Added configuration diagnostics, bounded diagnostic bundles, filtering/redaction and export-size limits. Expanded JSON/CSV reports and added Markdown/NDJSON exports, metric definitions, comparison checks and benchmark thresholds.
- Restored numeric workload targets and budgets in the overlay, alongside requested content FPS, display Hz and Flutter phase overruns. Request decisions update the overlay even without display events; updates remain throttled and event-driven.
- Moved all native operations to generated Pigeon messages, including Linux GObject bindings. Added regeneration checks and native/browser integration jobs to CI.
- Lifecycle integration checks now wait for fresh native surface restoration after resume and rotation. Preserved the active Android rotation policy in the host test fixture. Clarified that reused request results describe the original submission.
- Fixed integration-test coordination on CI: streaming Android host markers, API 30 rotation handling, separate desktop launches and explicit Chrome/WebDriver binary pairing.
- Added a controlled system-default versus requested-high example, Android OS lifecycle/Battery Saver tests and separate paired overlay-overhead captures.

**Breaking changes:** Existing controls now return futures/results, resets preserve independently owned requests, `boostDuring()` requires disposal, `observedAvgHz` is nullable, session states include `finalizing`, and report schema version 2 uses revised metric definitions. Unknown display values no longer assume 60 Hz. See [Upgrading from 1.0.2](README.md#upgrading-from-102).

## 1.0.2

- Added Swift Package Manager support.

## 1.0.1

### Web support
- Added web platform implementation using `requestAnimationFrame` interval
  timing to detect the display's current refresh rate (same technique as TestUFO).
- Control methods are graceful no-ops (browsers own vsync scheduling).
- FPS overlay and benchmark sessions work unchanged on web.

### Documentation
- Added comprehensive Dartdoc comments to all public APIs.

### Platform fixes
- Restructured `Package.swift` into `ios/refresh_rate/` and `macos/refresh_rate/`
  for correct Swift Package Manager module resolution.
- Resolved minor lint warnings from test suites.

## 1.0.0

Initial stable release — unlock, query, overlay, and benchmark display refresh rates across all Flutter platforms.

### Control

- `RefreshRate.enable()` — one-line unlock of peak display refresh rate
- `RefreshRate.preferMax()` / `preferDefault()` — explicit rate preference
- `RefreshRate.matchContent(fps)` — sync display cadence to content frame rate (fixes 24 fps video judder)
- `RefreshRate.boost(duration)` — temporary max-rate spike for gesture-driven animations
- `RefreshRate.category(RateCategory)` — Android 15 semantic rate category
- `RefreshRate.setTouchBoost(bool)` — Android 15 touch-driven rate boost

### Diagnostics

- `RefreshRate.info` — synchronous cached `RefreshRateInfo` snapshot (current rate, max, min, supported rates, VRR, API level)
- `RefreshRate.onChanged` — stream fires on rate change, Low Power Mode toggle, or thermal state change
- `RefreshRate.isLowPowerMode` / `thermalState` / `isProMotionReady`

### Debug overlay

- `RefreshRate.showOverlay()` — full diagnostic HUD with live FPS, build/raster timings, frame budget
- `RefreshRate.showFPS()` / `showHz()` — individual overlay badges
- FPS colour is relative to the device's actual target rate, not a hard-coded 60 Hz baseline

### Benchmark sessions

- `RefreshRate.startSession(name)` returns `RefreshRateSession`
- `session.end()` returns `SessionReport` with verdict, bottleneck, avgFps, 1% low FPS, missed-frame %, and JSON export
- Sessions auto-exclude backgrounded periods, resume warmup, LPM changes, and thermal changes

### Platform coverage

- **Android 6+** (API 23): `SurfaceControl.Transaction.setFrameRate()` (API 34+), `preferredRefreshRate` + `preferredDisplayModeId` (API 30–33), legacy `preferredDisplayModeId` fallback (API 23–29)
- **iOS 15+**: `CADisplayLink.preferredFrameRateRange` with runtime `Info.plist` ProMotion validation
- **macOS 14+**: `CADisplayLink`-based control via `NSView.displayLink`
- **macOS < 14 / Windows / Linux**: query-only (reports real monitor refresh rate)
- All platform bridges use [pigeon](https://pub.dev/packages/pigeon) — fully typed, zero codec overhead
