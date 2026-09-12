# Migration from 1.0.2

This working revision changes metric meanings and removes unsafe Apple control. Treat it as a major API/behavior change before publishing. No package has been published by this implementation task.

1. Await control methods and inspect `RateRequestResult`. `submitted` is native submission, not guaranteed display behavior. Use leases for independently owned preferences.
2. `disable`/`preferDefault` release the imperative owner. They do not impose 60 FPS or clear unrelated scopes. Release other leases explicitly.
3. iOS/macOS engine-control requests now report unsupported. iOS no longer intercepts all process display links. Querying and Flutter frame timing remain available. Do not restore the old swizzle simply to retain an “unlock” claim.
4. Prefer nullable diagnostic observations over numeric `DisplayInfo` fields. Legacy numbers use zero for unavailable; legacy booleans cannot encode unknown. Use `reportedVariableRefreshRate` for nullable capability evidence.
5. `observedAvgHz` is nullable and no longer populated from Flutter cadence. Physical `presentedFps` is unavailable.
6. FPS lows use inter-frame intervals and require minimum sample counts. Report JSON uses null for insufficient evidence. Legacy numeric low getters use zero; prefer checking interval count.
7. `missedFramePercent`/jank legacy names now describe UI/raster phase overruns. Pipeline-latency percentiles are separate. Update labels and stored-data comparisons.
8. Pass `expectedFps` only when the scenario is expected to render continuously. Pause intentional idle portions. Record target changes explicitly; sessions no longer assume the display maximum is the workload target.
9. `end()` is idempotent and waits for a bounded delivery interval. Inspect `boundaryCoverageComplete`; a session ending without further frame delivery may remain incomplete. No extra frames are forced merely to improve coverage.
10. Retain and call the disposer returned by `boostDuring`, then dispose the animation controller. Dispose automatic/content controllers and telemetry subscriptions.
11. `auto()` requires explicit activity signals or the interaction widget. It does not discover arbitrary animations/media globally. Hidden custom tabs must provide active/visibility state.
12. Reports use schema version 2. Do not compare prior “low FPS”, “missed frames” or “observed Hz” values as if their definitions were unchanged.

Swift sources are mirrored for CocoaPods and Swift Package Manager. Run `python3 scripts/check_apple_sources.py --sync` after changing canonical Apple sources; CI checks parity. Android compiles against API 36 and gates newer calls by runtime API level.
