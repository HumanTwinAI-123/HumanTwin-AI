# Mock v1 source publication inventory — 2026-10-02

This commit archives the existing local Mock v1 implementation and its required sample-model source material. It does not declare a new production release, a release APK, real photo reconstruction, or a medical product. Existing repository visibility remains public.

## Included

Current Flutter UI/controllers/repositories, native Android/iOS sharing bridges, tests, the local development proxy, sample GLB and thumbnail, and the official MakeHuman CC0 inputs with source/asset licenses. Package manifest and lockfile are unchanged. Photo selection is real; default generation is simulated and unrelated to the selected photos.

## Validation evidence

Read on 2026-10-02 from the local 2026-10-01 completion records: analyze reported zero issues, Flutter tests 122/122, snapshot-bridge tests 7/7, and Android Debug build passed. The final verification record contains 11 source hashes (including pubspec/lock); all 11 match the files included here. Other selected implementation-file timestamps predate the recorded analyze/test results. These are existing results, not checks rerun during this archive operation.

Android API 36 emulator evidence covers task recovery, sample-model controls, PNG/GLB sharing and saving, SAF overwrite/failure preservation, and short-screen 200% text/error recovery. Physical Android v1 end-to-end, iOS equivalence, real Meshy calls/cost/quality and production service behavior remain unverified.

## Excluded from this update

All newly generated device screenshots, original/working recordings, app-private backups, attachments, replaced-file backups, design proposals/research archives, AI-tool rule changes, build/cache directories, local service data, credentials, model weights and the separate promo project. Local files were not deleted or changed to create this export. Historical repository media already present in the parent commit was left unchanged; it was not newly privacy-cleared by this inventory.

## Licensing and scope limits

The current sample avatar uses official MakeHuman CC0 core assets; 37 source asset/license files were checked against their manifests. The existing photo-guide reference images already tracked in the parent commit still lack documented source rights. This archive does not certify those legacy images for external promotion. The separate promo archive is private and contains only its approved demo materials.

## Source fingerprint evidence

- `lib/features/library/avatar_detail_screen.dart`: `a55d3a3b1e4dc2e428993b8fde9b643fbea62f9c3b2b5bc9eff04bbfe7aafbec`
- `lib/features/viewer/digital_twin_viewer.dart`: `093344bc22c59066cabd2e93ef698bc7c249feb492d9433f4691d4edaefddc80`
- `lib/features/share/share_controller.dart`: `586e7110094123339948928b93eb6e0829ded52f5c68a761cf718c9c0f953714`
- `lib/features/share/share_preview_screen.dart`: `a0399239db1e6b40aa261de1803eec701f7b165a0c6ae93fcc99dc2016978dbc`
- `android/app/src/main/kotlin/com/example/human_twin_ai/MainActivity.kt`: `9ade3aeb7231ab480cb274f5044c7d91e9b11b4548b4b5db6457b50abde2a571`
- `test/share_test.dart`: `50cae91d6f4bdef8e09e3f7ed21908b87d1d56cbe0bd3888af110858cfcf6cb0`
- `test/share_capture_test.dart`: `185b24b50c6ac0489cc8409156fc3c03014c1d2136526ac20f70ab9105b5acfd`
- `test/share_capture_js_test.cjs`: `3d724b1f2c785c41c07d5d7b38be050544bd9667106b28bec14572460e8afbd1`
- `test/viewer_screen_test.dart`: `afe2b2961b91609228bcc0ecdcf0259bee0044320012e6dfd04212d94c99640e`
- `pubspec.yaml`: `1d5f9ee26fa2a1a06f2798e1cc003bf3a278282fe06cf9a5c0d77bd2d4540ee9`
- `pubspec.lock`: `7d625f2b3e66133aae77ef395ab0dadc66817f7a24f58e370f21279bc9e2f06b`
