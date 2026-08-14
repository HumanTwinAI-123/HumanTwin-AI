# HumanTwin AI — Day 6 final Android evidence

Date: 2026-08-14

Frozen implementation commit: `44cba626ce364a2c612f161370c9e7098eeddb93` (`44cba62`)

## Environment

- Device: `emulator-5554` (`sdk_gphone64_arm64`)
- Android: Android 16 / API 36
- Normal device capture: 1080x2400 at 420 dpi (approximately 411x914 dp)
- 390x844-equivalent capture: 1024x2216 at 420 dpi
- Short viewport capture: 1080x1800 at 420 dpi (approximately 411x686 dp)
- Large-text capture: system font scale 2.0 (200%)

## Verification result

- Full flow: **PASS**
  - Cold start succeeded.
  - Used the Android system Photo Picker for front, side, and back photos.
  - Verified Home -> Photo Guide -> Photo Selection -> Photo Confirmation -> AI Processing -> Success.
  - Verified the three selected photos remained present after back navigation and re-entry.
- Processing -> Success: **PASS**
  - Processing was visible at approximately 0.35 seconds and 1.25 seconds after starting generation.
  - The "查看数字人体" CTA was not visible while processing.
  - Success and the CTA were visible after the mock repository completed.
  - Clicking the CTA did not crash or navigate; Viewer integration remains a Day 7 boundary.
  - Returning to Confirmation and re-entering Processing preserved Success without a visible generation restart.
- Layout checks: **PASS**
  - No observed RenderFlex overflow or clipped headline/status.
  - Short-screen and 200% text layouts remained scrollable.
  - The Success CTA remained reachable and outside the Android gesture/system area.
- Android log review: no matching app crash, Flutter exception, ANR, or RenderFlex overflow markers.
- `flutter analyze --no-pub`: **No issues found**
- `flutter test --no-pub`: **30/30 passed**
- Codex final Android verification: **PASS**
- DSH Final Review: **PASS**
- P0: **0**
- P1: **0**

## Evidence files

- `day6-final-home.png` — cold-start Home screen.
- `day6-final-selection-filled.png` — all three photo slots filled.
- `day6-final-confirmation.png` — Photo Confirmation with all three photos.
- `day6-final-processing-0350ms.png` — Processing at approximately 0.35 seconds; CTA absent.
- `day6-final-processing-1250ms.png` — Processing at approximately 1.25 seconds; CTA absent.
- `day6-final-success.png` — Success state with the CTA visible.
- `day6-final-success-after-cta.png` — Success remains after clicking the Day 7 boundary CTA.
- `day6-final-success-reentry-0350ms.png` — Success preserved on Processing re-entry.
- `day6-final-390x844-success.png` — 390x844-equivalent Success layout.
- `day6-final-short-top.png` — short-viewport Success layout, top position.
- `day6-final-short-bottom.png` — short-viewport Success layout, scrolled to the CTA.
- `day6-final-large-text-top.png` — 200% text Success layout, top position.
- `day6-final-large-text-bottom.png` — 200% text Success layout, scrolled to the CTA.
- `day6-final-logcat.txt` — logcat captured during the final Android verification; trailing horizontal whitespace was normalized during archival, with no log events removed.

## Recording status

No valid Day 6 MP4 was produced. No video has been fabricated, reused, or archived as Day 6 evidence.

## Archive boundary

- This archive does not modify application code, tests, dependencies, assets, Viewer code, or `AGENTS.md`.
- Day 7 has not started.
- The evidence archive is intentionally left uncommitted and unpushed pending explicit approval.
