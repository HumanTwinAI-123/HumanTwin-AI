# HumanTwin AI — Day 7 Viewer Verification Evidence

- Date: 2026-08-15
- Device: `emulator-5554` / `sdk_gphone64_arm64`
- Platform: Android 16 / API 36
- Day 7 goal: Processing Success → Viewer → local GLB
- Implementation commit: `b5e0ea7ff691d9fbff34ed56266bc862c52c846e`

## Delivered Viewer flow

Day 7 formally connects the successful mock-generation state to `/viewer` and preserves the existing Day 1 local-model POC contract. The validated Viewer supports:

- bundled local GLB rendering
- drag rotation
- pinch zoom
- auto-rotate
- reload
- UI back and Android system back
- repeated entry without unexpected regeneration
- a static poster while the WebView/model initializes

The Viewer remains under `lib/features/viewer/`. It does not introduce a Viewer Riverpod controller, repository, package change, new GLB, or a second 3D implementation.

## Original P1 reproduction

Before the exit guard, leaving the Viewer during the `model_viewer_plus` initialization window reproduced a real P1:

- the app stopped responding to input
- Android reported `Input dispatching timed out`
- an application ANR dialog appeared
- the failure propagated into a system input-dispatch ANR
- navigation could not be relied on to recover normally

The `pre-fix-p1/` directory preserves the valid reproduction recording, ANR dialog screenshot, `dumpsys activity lastanr`, and the relevant pre-recovery logcat. The original files remain preserved under `/tmp/humantwin-day7-stress.rsDUPl/` at archive time.

For repository hygiene, trailing horizontal whitespace was removed mechanically from archived text-log copies so `git diff --check` remains clean. Event text and line order were otherwise preserved, and the untouched `/tmp` originals remain the raw source evidence.

## Exit lifecycle guard

The final implementation uses:

- `PopScope` for UI and Android system-back handling
- browser/model-viewer lifecycle messages for page-ready, model-loaded, and model-error
- one pending exit while disposal is unsafe
- exactly one committed pop when a lifecycle safety signal arrives
- a readiness watchdog that may probe page readiness but cannot unlock exit merely because a fixed duration elapsed
- no forced `ModelViewer` key recreation

Reload keeps the established exit-safe state and does not start a new protected initialization cycle.

## Post-fix verification

| Check | Result |
| --- | --- |
| Release rapid Viewer exits | 20/20 PASS |
| Viewer UI back | 10/10 PASS |
| Android system back | 10/10 PASS |
| Mixed/repeated back | 4/4 PASS; exactly one pop |
| Debug rapid exits | 5/5 PASS |
| Complete normal Viewer cycles | 3/3 PASS |
| GLB / rotate / zoom / auto-rotate / reload | PASS |
| Processing Success preserved | PASS |
| Unexpected regeneration | 0 |
| App ANR after fix | 0 |
| Flow-caused system_server ANR after fix | 0 |
| FATAL EXCEPTION | 0 |
| `setState() called after dispose` | 0 |
| Flutter app process restart | 0 |
| `flutter analyze --no-pub` | No issues found |
| `flutter test --no-pub` | 46/46 PASS |

The post-fix Release app PID remained `2196 → 2196`; the Debug PID remained `11889 → 11889`.

## Known Limitation (P2) — WebView renderer teardown log artifact on Viewer exit

On Android API 36 using `model_viewer_plus 1.10.0` / `webview_flutter 4.14.1`, exiting the 3D Viewer may log:

```text
Renderer process (...) crash detected (code -1)
```

Seven events were observed during the full Day 7 stress suite. Final log correlation established that every post-fix occurrence:

- happened only after intentional Viewer exit
- was associated with WebView/platform-view teardown
- left the Flutter app PID alive
- caused no ANR, FATAL EXCEPTION, or FlutterError
- caused no sustained blank Viewer or input failure
- allowed the next Viewer session to create a fresh renderer and render the GLB

This is a documented P2 teardown artifact, not an app crash, and requires no Day 7 remediation.

`post-fix/raw-verification-summary.txt` preserves the verifier's raw pre-correlation classification. The final DSH correlation above supersedes only that classification; it does not alter the recorded counts or behavior.

## Evidence inventory

### `pre-fix-p1/`

- `early-exit-stress-recording.mp4`
- `early-exit-anr-dialog.png`
- `early-exit-lastanr.txt`
- `early-exit-logcat.txt`

### `post-fix/`

- `release-rapid-20-cycles.mp4`
- `release-processing-success-after-stress.png`
- `final-healthy-viewer.png`
- `final-processing-success.png`
- `release-logcat-final.txt`
- `debug-logcat-final.txt`
- `release-ui-back-10.txt`
- `release-system-back-10.txt`
- `release-mixed-back.txt`
- `debug-rapid-5.txt`
- `release-lastanr-final.txt`
- `debug-lastanr-final.txt`
- `flutter-analyze.txt`
- `flutter-test.txt`
- `raw-verification-summary.txt`

## Final conclusion

```text
DAY 7 — PASS / FROZEN
P0 = 0
P1 = 0
P2 = 1 documented known limitation
```

Day 8 was not started.
