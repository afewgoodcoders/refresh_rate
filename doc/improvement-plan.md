# refresh_rate: audit and execution checklist

Reviewed: 12 September 2026. Baseline: local commit `96b9861`, package version `1.0.2`.

This document preserves the audit and acceptance inventory against commit `96b9861`. Implementation work followed on 13 September 2026; see [implementation status](implementation-status.md) for delivered changes, validation, partial items and remaining qualification. The evidence table below describes the original baseline, not the modified source.

The conversation reader returned the initial ideas answer, but truncated the later audit at 20,000 characters during its content-adapter inventory. This checklist covers the retrieved recommendations plus identified repository findings; it cannot reproduce the unseen remainder. Browser recovery did not expose that conversation's remaining text.

Checked items indicate implemented code/contracts, not physical-device qualification. Unchecked items can be partly implemented; consult the status document before treating them as absent.

## 1. Findings verified in the checkout

| Area | Current evidence | Required action |
|---|---|---|
| Average FPS | `lib/src/verification/fps_tracker.dart`, `_fpsFromWindow`: counts intervals between reported Flutter vsync timestamps. | Preserve its mathematical basis, name its scope, segment inactive periods, and expose stale/insufficient data. It does not establish physical presentation FPS. |
| Low FPS | `onePercentLowFps` / `fivePercentLowFps` invert `totalUs`. | Calculate from valid inter-frame intervals; expose pipeline latency separately. |
| Jank/missed frames | `jankyFrameCount` uses `totalUs > budget`; `missedFramePercent` counts those records. | Separate UI/raster overruns, pipeline latency, cadence gaps, and qualified presentation misses. |
| Session completeness | Tracker retains 600 frames; sessions use this same rolling tracker. | Add whole-session accumulation independent of rolling history. |
| Session lifecycle | `refresh_rate_session.dart` registers `_tracker.addTimings` directly; state changes do not filter event timestamps. | Filter by timestamped active segments, account for partial exclusions, and finalize delayed batches. |
| Session target | Target and device snapshot are fixed at creation from `info.maxRate`. | Record expected workload cadence and display/power/thermal changes over time. |
| Misleading report fields | `session_scorer.dart` assigns `observedAvgHz: avgFps`. | Stop describing Flutter cadence as measured display Hz. |
| Diagnostic verdicts | Low power directly implies `powerLimited`; an FPS ratio directly implies `displayCapped`. | Report observations separately from tentative explanations. |
| Overlay observer effect | `_OverlayStateMixin` starts a continuous ticker for every badge; Hz-only also subscribes to Flutter timings. | Replace with bounded event-driven updates; qualify benchmarks with overlay off. |
| Android control | `setSurfaceFrameRate` writes window attributes; its compatibility argument and local strategy are unused. | Name the actual backend and implement real surface votes only where lifecycle/ownership is qualified. |
| Android mode selection | API 30+ helper selects modes without filtering current resolution. | Preserve resolution for automatic preferences. |
| Android capabilities | ARR and VRR are inferred from mode counts/ranges; `compileSdk = 35`. | Add version-gated API 36 evidence and report unknown where evidence is unavailable. |
| iOS control | `DisplayLinkSwizzle.m` installs process-wide interception in `+load`; `resetCap` applies 60. | Remove interception from the default path and define actual clear/restore semantics. |
| Apple measurement | Separate display links use `1 / duration`; fallback and supported-rate fields contain assumptions. | Distinguish link observations, screen information, and unknown engine/presentation state. |
| macOS control | `preferDefault()` calls `enable()`; a helper display link is the controlled object. | Fix reset semantics and qualify what control can affect. |
| Windows display | Current rate uses the first target; supported modes use the default display; engine rate is constant 60. | Resolve the Flutter window's monitor and stop synthesizing engine state. |
| Linux display | Aggregates different monitors' current rates as supported modes; infers VRR from their differences. | Keep per-monitor identity, capabilities, and observations separate. |
| Web measurement | rAF detector snaps rates; lacks timeout, visibility handling, cancellation; adapter treats the observation as max/engine rate. | Preserve raw callback cadence and bound observer lifetime; unsupported values remain unavailable. |
| Request completion | Public controls return `void`, discarding adapter futures; enable/disable refresh without awaiting control. | Await and serialize control results, propagate errors, and reject stale responses. |
| Competing requests | Native boost timers reset shared preferences independently. | Introduce request ownership and arbitration before scopes or auto policies. |
| Cache/events | Native callback registration depends on access to `onChanged`; test reset does not reset cached info. | Define initialization, subscription, cache freshness, and reset ownership. |

Two useful correctness examples:

- Frames spaced every 16,667 microseconds with 2,000-microsecond pipeline spans produce roughly 60 average FPS but **500 low FPS** in the current code. The latter is inverse latency, not low cadence.
- A 1,200-frame benchmark can lose all its first 600 frames from the report. Early stutters disappear even though the duration describes the full session.

Flutter explicitly distinguishes phase budget overruns from pipeline latency and batches timing delivery. These are constraints on the measurement design, not reasons to abandon Flutter timings. [Flutter timing callback documentation](https://api.flutter.dev/flutter/scheduler/SchedulerBinding/addTimingsCallback.html)

## 2. P0 — trustworthy measurements

Core measurement work is implemented; empirical qualification remains separate.

- [x] **M1 — Write metric contracts.** Define units, source, clock, scope, freshness, window, sample count, denominator, unavailable state, and coverage for every metric. Separate requested preference, native display information, Flutter cadence, callback cadence, and qualified presentation data.
- [x] **M2 — Correct cadence statistics.** Use consecutive frame intervals within explicit active segments. Specify the slowest-tail averaging convention separately from percentile latency. Support insufficient-data results; do not hide bad calculations with display-rate clamping.
- [x] **M3 — Separate overrun metrics.** Provide UI and raster budget-overrun counts/percentages, pipeline-latency statistics, and expected-cadence gaps. Require explicit evidence for presentation misses. Preserve severe-gap/overrun thresholds as named definitions.
- [x] **M4 — Split rolling and session storage.** Use a bounded ring buffer for recent samples and independent whole-session counts, sums, histograms, and bounded worst-frame records. Specify approximation/error bounds for histogram percentiles.
- [x] **M5 — Model sessions as timestamped segments.** Cover active, background, warmup, user-paused, and finalizing states. Filter frames by event time, not callback arrival or current state alone. Avoid intervals crossing exclusions. Retain thermal/power changes as labels rather than silently erasing degradation.
- [x] **M6 — Resolve clocks and boundaries.** Map session markers and native events into a defined time domain. Do not compare raw Flutter timestamps directly with `DateTime` epoch values. Use bounded finalization for late batches and report incomplete boundary coverage when it cannot be established.
- [x] **M7 — Track changing expectations.** Support workload target FPS distinct from display maximum and observed display rate. Segment target/display transitions. Do not classify idle UI or intentional 24 FPS content against an unconditional 120 FPS target.
- [x] **M8 — Make diagnostics evidence-based.** Replace causal verdicts inferred from single flags/ratios with observed facts and qualified hypotheses. Add insufficient data, unknown target, stale observation, and debug-mode qualification.
- [x] **M9 — Share collection.** Overlay, sessions, and export subscribe to one service with explicit listener ownership. Keep sorting, serialization, file/network I/O, and expensive analysis outside timing callbacks. Disable unused native observers and detach on teardown.
- [x] **M10 — Fix overlay behavior.** Throttle updates from observations; isolate repainting; show idle/stale/unknown. Hz-only must not collect FPS unnecessarily. Prevent a hide or mode change from being undone by a queued post-frame insertion.

Acceptance gate: synthetic cadence and phase durations vary independently; long sessions preserve early stalls; idle/background/warmup do not create synthetic gaps; delayed and crossing batches are handled explicitly; session completion is deterministic; an unchanged Hz badge does not keep scheduling continuous frames.

The raw timing epoch is not guaranteed to match wall time, and performance analysis should use profile/release data. [Flutter FrameTiming reference](https://api.flutter.dev/flutter/dart-ui/FrameTiming-class.html)

## 3. P0 — safe, explicit control

- [x] **C1 — Capabilities and results.** Introduce per-operation capabilities for query, window preferences, surface voting, category hints, engine control, and presentation observation. Requests return the submitted preference, backend, scope, error/unavailable reason, and observation status. Submission is not proof of fulfilment.
- [x] **C2 — Validate input.** Reject non-finite/non-positive content rates, inconsistent ranges, invalid durations, and invalid categories before platform calls. Make clearing a request explicit. Define fractional FPS precision and native conversion behavior.
- [x] **C3 — Centralize request ownership.** Leases have identities, priorities, cancellation/expiry, idempotent release, and deterministic arbitration. Ignore stale async results and expired timer callbacks. The package releases only its own request and does not blindly restore obsolete external state.
- [ ] **C4 — Define reset consistently.** Separate clear-package-preference, explicit 60 FPS, and restore-owned-baseline operations. Include touch-boost/category hints in ownership. Migrate existing `disable`/`preferDefault` semantics explicitly.
- [ ] **C5 — Android backend qualification.** Implement real surface voting only for an identified live Flutter rendering surface; handle attach/replacement/detach and platform-view composition. Expose window/category/same-resolution-mode fallbacks honestly. Never take the first arbitrary SurfaceView as sufficient evidence.
- [x] **C6 — Android API 36.** Raise/qualify compile SDK and build tooling; gate `hasArrSupport`, suggested normal/high rates, and `FRAME_RATE_COMPATIBILITY_AT_LEAST`. Keep earlier API-level fallbacks explicit. ARR support must not be guessed from a rate range.
- [x] **C7 — Apple default safety.** Remove unconditional global swizzling from normal initialization. Investigate supported engine integration before promising engine control. Any retained interception backend must be explicitly experimental/opt-in with documented affected scope and teardown behavior.
- [ ] **C8 — Lifecycle and events.** Reconcile requests after activity recreation and window/surface changes; cancel timers/listeners during engine teardown. Handle requests before attachment with an explicit pending/unavailable result and bounded lifetime. Register power/thermal events where supported rather than relying solely on display-change events.
- [x] **C9 — Cache consistency.** Initialize event reception independently from whether callers access a getter; make cached observations timestamped and stale-aware; prevent older reads from overwriting newer state. Reset the test adapter and cache together.

Acceptance gate: overlapping boosts cannot undo a newer request; detached targets cannot receive stale writes; failures reach Dart callers; unsupported control never appears fulfilled; clearing restores package ownership correctly; Android mode selection preserves resolution; default Apple initialization performs no global interception.

API 36 exposes ARR detection and display-defined suggested rates. Its at-least surface compatibility is intended for UI/animation/scrolling, while fixed-source compatibility remains appropriate for video. [Android Display](https://developer.android.com/reference/android/view/Display), [Android Surface](https://developer.android.com/reference/android/view/Surface)

Frame-rate requests can be declined by system policy. Exact content rate, clearing, and seamless/non-seamless transition strategy must reach the actual backend. [Android frame-rate guidance](https://developer.android.com/media/optimize/performance/frame-rate)

## 4. P0/P1 — correct observations on every advertised platform

- [x] **D1 — Android:** distinguish mode/render-rate information from physical instantaneous panel behavior; report the active display/mode/resolution and source. Do not copy display Hz into an engine-target field.
- [x] **D2 — iOS:** distinguish maximum screen capability from display-link expected interval and observed callback spacing; avoid invented exhaustive rate lists/minima; bind to the relevant scene/window and make continuous monitoring opt-in.
- [x] **D3 — macOS:** bind queries and observers to the app window's screen, respond to screen moves/reconfiguration, remove constant engine targets and maximum-as-current fallback, and unregister native callbacks.
- [ ] **D4 — Windows:** map the Flutter HWND to its monitor/display path, use that identity for both current and supported modes, preserve rational precision, and handle monitor changes/query failures.
- [ ] **D5 — Linux:** report each monitor independently; select the app window's monitor where available; describe X11/Wayland coverage limits; preserve fractional precision and unknown capability states.
- [x] **D6 — Web:** report browser callback cadence with raw estimate, window/sample count and dispersion; add cancellation, timeout, visibility segmentation, and safe concurrent measurement. Do not populate hardware maximum/supported-rate/engine-target fields from rAF samples.
- [ ] **D7 — Multi-display API:** add display/window identifiers to records immediately; expose full enumeration and multi-window controls after the active-window correctness work. Do not promise per-view Flutter timing attribution without a supported source.

Fix wrong-monitor reporting early. Full multi-monitor management is an expansion that can ship later.

## 5. P1 — developer-facing features (baseline inventory)

| Feature | Existing state | Work remaining / acceptance |
|---|---|---|
| `RefreshRateScope` | Absent | Acquire/release leases on activation; nested scopes arbitrate correctly; hidden tabs/routes cannot retain foreground priority. |
| Interaction adapter | Native touch hint and simple timed boost exist | Track drag plus ballistic scroll and idle grace period; handle accessibility/keyboard-driven interactions where integrated. |
| Animation adapter | `boostDuring` listens for status and removes itself on completion | Handle already-running, repeating, reversing, canceled, and disposed animations; expose a detachable owner. |
| Content adapter | Bare `double fps` method exists | Exact fractional source rates, playback speed, pause/buffering/visibility, surface changes, seamless preference and explicit non-seamless opt-in. Qualify real player-surface integration. |
| Advanced analytics | Averages, incorrect lows, broad jank counters | p50/p90/p95/p99 for named phases/intervals, corrected 1%/5% lows, sufficiently sampled 0.1% lows, worst frames, overrun distributions and workload grouping. |
| Timeline tags | Absent | Timestamped screen/action tags, markers, interval attribution and bounded cardinality. Associate tags with frame event time, not delayed delivery time. |
| Decision history | Absent | Requested decision, owner, reason, backend submission and subsequent observations on a bounded timeline; do not invent reasons for OS behavior. |
| CI evaluation | Absent | Framework-independent `evaluate(thresholds)` with pass/fail/inconclusive and named failures. Support workload/target-aware gates and report compatibility checks. |
| Report exports | JSON and CSV exist | Version schema, source/coverage metadata, frame counts, segment coverage, environment and settings; add readable Markdown and comparable baseline reports. |
| Diagnostic overlay | FPS, Hz and full views exist | Add requested/native/Flutter distinction, named p99/overrun metrics, compact graph, source and freshness after correcting observer overhead. |

Acceptance gate: scopes, animation, interaction, video and timed requests coexist without resetting each other; exports describe exactly what was measured; CI cannot pass on missing data, hidden tabs, unsupported metrics, or an incompatible baseline.

## 6. P1/P2 — automatic policies and optional telemetry

- [x] **A1 — Build `auto()` over leases.** Define system/balanced/performance/battery policies. Base transitions on explicit workload signals and supported native observations; expose configuration, current decision, and a stop/dispose handle.
- [ ] **A2 — Add hysteresis.** Immediate interaction escalation, delayed idle downgrade, minimum residence time and bounded transition frequency; prevent repeated 120/60 oscillation.
- [x] **A3 — Respect competing workloads.** Explicit user/content requests participate in arbitration; power and thermal policy changes have documented precedence. App inactivity releases appropriate requests.
- [x] **A4 — Avoid feedback loops.** Low measured FPS does not automatically justify requesting the maximum forever. Do not keep generating frames merely to detect activity or let the overlay sustain its own boost.
- [ ] **A5 — Validate outcomes.** Compare system default and policy variants on the same physical devices/workloads; record cadence, overruns, request changes, observer overhead and sustained thermal behavior. Claims of energy savings require actual energy evidence.
- [ ] **T1 — Optional production sinks.** Build on the shared collector and versioned reports with sampling, bounded queues, batching, backpressure, explicit opt-in, tag redaction and no network dependency in the core path.
- [ ] **T2 — Trace/DevTools integration.** Correlate markers, request decisions and timing records; build a richer inspector only after the contracts and overhead are stable.
- [ ] **T3 — Qualified native evidence.** Investigate JankStats/FrameMetrics, MetricKit and trace integration as supplementary sources. Establish coverage for Flutter surfaces versus native views before mixing metrics or reporting presentation misses.
- [ ] **T4 — Player integrations.** Add optional adapters for actual video playback/surface ownership; borrow frame-release/pacing principles from native tools without promising that a generic plugin can replace Flutter's renderer pacing.

`auto()` should be a convenient policy API whose effects depend on platform capability. A universally guaranteed “one line unlocks maximum performance” promise is not an acceptance criterion.

## 7. Additional issues and release work found during this review

These additions come from this checkout review, not a claim about the truncated remainder of the conversation.

- [x] **R1 — Fix equality completeness.** `DisplayInfo.operator ==` omits supported rates and several capability/environment fields; `DeviceStateSnapshot` equality also omits serialized fields. Ensure equality reflects the chosen value contract and test changes in those fields.
- [x] **R2 — Fix overlay insertion races.** `_show` queues a callback without a generation/disposal guard; repeated show/hide calls can insert stale entries or leave orphan entries. Cancel obsolete work and handle unavailable overlay hosts honestly.
- [ ] **R3 — Qualify Swift Package Manager delivery.** macOS `macos/refresh_rate/Package.swift` points to `Classes` relative to that directory, but the checkout contains sources in `macos/Classes`. Correct packaging and verify a consuming build. Keep iOS CocoaPods and SPM source copies behaviorally aligned or consolidate them.
- [ ] **R4 — Repair tests and add meaningful coverage.** Current fixtures make pipeline span equal cadence interval, concealing the central measurement error. Decouple them; end every created session in cleanup; cover cache reset, lifecycle, delayed delivery, long history, invalid input, overlapping requests, web visibility, and overlay races.
- [ ] **R5 — Build compatibility matrix.** Verify minimum supported Flutter/Dart and current supported SDKs, Android API gates, CocoaPods/SPM consumption, web compilation, and Windows/Linux builds on suitable runners. No `.github` workflow directory is present in this checkout.
- [x] **R6 — Rewrite claims and migration guide.** Replace “unlock” guarantees with request/coverage language; correct physical-Hz/FPS and missed-frame descriptions. The locally installed Flutter iOS template already contains `CADisableMinimumFrameDurationOnPhone`; diagnose the consuming app instead of universally prescribing a missing key.
- [ ] **R7 — Version by compatibility impact.** Add deprecations and versioned report schemas first where practical. Changed reset semantics, nullable observations, revised metric meanings and backend safety can justify a major release independently of whether `auto()` is ready.

## 8. Execution sequence and release gates

| Order | Reviewable change group | Depends on | Done when |
|---|---|---|---|
| 1 | Metric contracts and independent timing fixtures | None | The two correctness examples above have meaningful regression coverage; source/units/coverage contracts are agreed. |
| 2 | Collector, whole-session storage and segmentation | 1 | Long-session, exclusion, clock/batch-boundary and target-transition cases pass. |
| 3 | Correct reports, diagnostic wording and overlay | 2 | No inverse-latency FPS, fabricated display Hz, or continuous Hz-only ticker; exports carry coverage. |
| 4 | Awaitable requests, capabilities and arbitration | Contract design can run alongside 1–3 | Errors and unsupported cases are visible; stale timers/results cannot overwrite current ownership. |
| 5 | Android and Apple backend corrections | 4 | Backend scope, lifecycle, reset and API gates are verified; default Apple path avoids global interception. |
| 6 | Desktop/web source correctness and packaging | Observation contracts; much can proceed alongside 2–5 | Active display identity and unknowns are correct; web observer lifetime is bounded; consuming builds work. |
| 7 | Scopes, interaction/animation/content adapters | 4–5 | Nested/hidden/canceled/repeating workload cases coexist correctly. |
| 8 | Advanced analytics, tags and CI reports | 2–3 | Full-session, source-qualified statistics and meaningful comparison gates pass. |
| 9 | `auto()` and profiles | 5, 7; telemetry from 8 | Policy tests and physical-device comparisons show stable decisions and acceptable overhead. |
| 10 | Optional production sinks, inspector and native adapters | Stable contracts and 8 | Coverage and overhead are measured; optional integrations do not burden basic control/query users. |

Suggested release milestones: **correctness and safe-control release → declarative integration and CI telemetry → adaptive policy release → optional advanced integrations**. Assign exact versions after the compatibility audit; do not retain the original feature-first 1.1/1.2 schedule automatically.

## 9. Validation record and outstanding qualification

The baseline audit passed 23 tests that did not establish the revised contracts. The implementation adds independent cadence/phase fixtures, whole-session and delayed-delivery coverage, request races, lifecycle/scopes and telemetry checks. Current results and platform build evidence are recorded in [implementation status](implementation-status.md).

Release gates still include physical-device comparisons, Perfetto/Instruments correlation, monitor movement, sustained power/thermal behavior, platform-view/player composition, supported SDK matrix execution and observer overhead. Successful compilation alone does not establish physical refresh behavior or presentation coverage.
