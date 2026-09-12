# Implementation status

Updated 13 September 2026, against baseline `96b9861` (1.0.2). This implementation targets the next major revision; no package release has been published. The source audit inventory is in [improvement-plan.md](improvement-plan.md); breaking changes are in [migration.md](migration.md).

## Implemented

| Audit area | Delivered behavior |
|---|---|
| M1–M4: metric correctness | Flutter cadence from valid intervals; slow-tail FPS lows with minimum counts; independent UI/raster overruns, pipeline latency and cadence gaps; bounded rolling history plus whole-session histograms and worst frames. |
| M5–M8: sessions and evidence | Event-time clock bridge, active/background/warmup/paused segments, bounded delayed-batch finalization, tags, markers, changing targets and device labels, coverage flags, debug/insufficient-data qualification. Expected continuous workload exposure prevents idle periods from producing false benchmark passes. |
| M9–M10: collection/overlays | One shared timing callback with independent subscribers; bounded event-driven overlays, stale/idle states, Hz-only without frame collection, cancellation of obsolete insertions. |
| C1–C3/C9: control contracts | Awaitable result/status/backend/scope, capabilities, input validation, serialized priority leases, expiry/cancellation, stale-result handling, independent event setup and generation-guarded cache reads. |
| C5–C6: Android implementation | Identified live FlutterSurfaceView votes, owned-surface cleanup/rebinding, visible window fallback for ordinary preferences, preserved resolution, API 35 owned native view-category hints, API 36 ARR/suggested-rate/at-least gates, exact content and transition strategy. Runtime qualification remains open. |
| C7: Apple safety | Removed process-wide display-link swizzling. Unsupported Flutter-engine control is explicit. iOS observer is opt-in and bounded; screen capabilities and callback observations are separate. |
| D1–D6: observations | Native versus engine/callback sources separated; unknown values retained; macOS/Windows/Linux select the app window's monitor; web rAF uses raw measurements, shared in-flight collection, visibility/timeout/cancellation and sampling metadata. |
| D7: display identity foundation | Flutter display enumeration, optional view-specific engine-reported display snapshot and native active-display identifiers. |
| Declarative/workload APIs | Nested scopes, route/TickerMode/background release, pointer/ballistic-scroll activity, detachable animation boosts and fractional content-state preferences with playback speed/buffering/visibility. |
| Reports and CI gates | Schema 2 JSON/CSV/Markdown, phase/interval percentiles, worst frames, low-FPS sample qualification, pass/fail/inconclusive thresholds and environment/scenario compatibility checks. |
| A1–A4: policy foundation | Explicit system/balanced/performance/battery policies, immediate activity escalation and delayed release, independent priorities, power/thermal/background handling, no frame-generating FPS feedback loop. |
| T1–T2: optional telemetry foundation | Sampled bounded asynchronous sink, drop/failure accounting, backpressure and timeout handling; optional Dart timeline decisions/markers and read-only diagnostics service extension. |
| R1–R6: delivery foundation | Value equality, regression coverage, Apple source parity script, repaired macOS SwiftPM source layout, cross-platform CI workflow and rewritten claims/migration examples. |

## Validation performed locally

- Root Flutter tests: 37 passed, including final in-flight close ordering and invalid histogram input coverage.
- Example Flutter smoke test: 1 passed.
- `flutter analyze --no-pub`: no issues found.
- Android debug APK: built successfully, including owned surface and native category preference changes.
- iOS simulator debug app: built successfully through CocoaPods.
- macOS debug app: built successfully through CocoaPods.
- Web example: built successfully, including the compiler's Wasm dry run.
- Apple mirrored-source parity: passed.

Builds used the locally installed Flutter SDK. Flutter automatically migrated temporary example host settings for its current deployment requirements during builds; those unrelated host/lockfile edits were reverted. Native compilation validates integration with that SDK, not on-device frame-rate behavior or the declared minimum Flutter version.

## Partial items and remaining work

| Inventory | Remaining scope / acceptance gate |
|---|---|
| C4/C5/C8 | Qualify request restoration with external native owners, touch-boost ownership, activity/engine recreation, surface replacement and platform-view composition on devices. Surface lifecycle reapplication exists, but only physical scenarios can validate OEM behavior. |
| D4/D5/R5 | Windows/Linux source changes and CI jobs are present; builds and monitor-move runtime checks were not run on this Mac. Execute the CI matrix, including minimum Flutter 3.24, before release. |
| D7 | Full native multi-window control/enumeration and per-view Flutter frame attribution are not implemented. Public Flutter timing does not establish universal per-view presentation attribution. |
| A2/A5 | Idle hysteresis exists. A separately configurable minimum-residence/transition-frequency governor, measured observer overhead, device policy comparisons and sustained thermal/energy validation remain open. No energy savings are claimed. |
| T1 | Core telemetry has no network destination and exports only timing samples. Application-specific tag redaction/export policy and integrations with production monitoring services remain application responsibilities. |
| T2 | Timeline and service endpoint are present; a standalone DevTools inspector UI and native trace-clock correlation are not implemented. |
| T3 | JankStats/FrameMetrics, MetricKit and presentation/Perfetto/Instruments adapters are not bundled. Establish actual Flutter-surface coverage before adding those metrics; physical presented FPS remains unavailable. |
| T4 | Generic content-state adapter is present; third-party video plugins' actual player-surface ownership and pacing integrations remain open. |
| R3 | SwiftPM source paths/parity are repaired; a consuming SwiftPM build still needs qualification. CocoaPods builds passed. |
| R4/R5 | Browser visibility/runtime automation, platform-native lifecycle tests and broad SDK/device matrix execution remain open. The added CI workflow has not run remotely. |
| R7 | Schema and migration changes are documented as a major revision; choose the release version after qualification. `pubspec.yaml` is intentionally still the baseline version and must not be published unchanged. |

The referenced chat's final audit was truncated by the conversation reader. This implementation does not claim to cover recommendations in text that could not be retrieved.
