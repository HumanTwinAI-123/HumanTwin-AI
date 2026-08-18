# HumanTwin AI

HumanTwin AI 是一个面向中文用户的 Android-first AI 数字人体移动端前端 Demo，用于验证从三视图照片采集到数字人体查看的完整产品体验。

当前正式版本：**[v0.1.0 Final Demo Release](https://github.com/HumanTwinAI-123/HumanTwin-AI/releases/tag/v0.1.0)**

## Core Experience

```text
Home
→ Photo Guide
→ Photo Selection
→ Photo Confirmation
→ Mock AI Processing
→ 3D Digital Human Viewer
```

## Current Demo

当前已经真实实现：

- Flutter Android 前端与六屏完整产品流程
- Camera / Gallery 图片选择
- Front / Side / Back 三视图状态管理
- 图片替换、删除与确认
- Mock AI Processing 状态流程
- 预生成 Local GLB 3D Viewer
- Rotate / zoom / autoRotate / reload
- Android 真机完整 E2E 验证
- Android Release APK

## Demo Boundary

- AI Processing 当前为 **Mock AI generation pipeline**。
- 3D Viewer 当前展示预生成的 **Local GLB**。
- 用户选择的 Front / Side / Back 三张照片当前不会真实生成 Viewer 中展示的 GLB。
- 当前没有 production backend、cloud upload、real AI reconstruction 或 cloud storage。
- 当前不包含 Login、Profile、History、Medical Analysis、AR、Payments 等产品能力。
- 本项目仅是 Android-first 前端 Demo，不代表生产系统或医疗级产品。

## Verification

- `flutter analyze --no-pub`：0 issues
- `flutter test --no-pub`：46 / 46 PASS
- Physical Android：Xiaomi `23049RAD8C`，Android 15 / API 35
- Final Release Smoke：PASS
- Viewer re-entry：5 / 5 PASS
- Viewer rapid exit：10 / 10 PASS
- Full Demo loop：3 / 3 PASS
- P0：0
- P1：0

验证证据见 [Day 10 Evidence Index](docs/evidence/day-10/README.md)。

## Release

正式版本：**v0.1.0**

[HumanTwin AI v0.1.0 — Final Demo Release](https://github.com/HumanTwinAI-123/HumanTwin-AI/releases/tag/v0.1.0) 包含：

- Android Release APK
- Final Demo Video
- Delivery Manifest
- SHA256SUMS

## Design

- [Figma — HumanTwin AI / Approved Home Hero v2](https://www.figma.com/design/JN4IsUqG7tLuwqcGbjbd1k/HumanTwin-AI?node-id=274-15)

## Project Records

- [Notion — HumanTwin AI Day 10 Final Delivery](https://app.notion.com/p/3bf38defc2eb8139a6f5dd935fef86e1?pvs=204)

## Known Limitations

完整能力边界与已知限制见 [docs/KNOWN_LIMITATIONS.md](docs/KNOWN_LIMITATIONS.md)。

## Demo Script

正式演示流程见 [docs/DEMO_SCRIPT.md](docs/DEMO_SCRIPT.md)。

## Local Run

```bash
flutter pub get
flutter run -d <android-device-id>
```

```bash
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --release
```

## Architecture Boundary

```text
Flutter UI
→ Riverpod Controller
→ DigitalTwinRepository
→ MockDigitalTwinRepository
```

未来接入真实 AI API 时，目标是替换 Repository 实现，同时保持现有六屏产品流程与照片状态所有权不变。

## Next Stage

以下方向属于后续研究与产品验证，不属于当前 v0.1.0 正式交付：

- Higher-quality digital human GLB asset
- Visually aligned Front / Side / Back Demo Case
- Real AI reconstruction research / integration
- Backend API integration
- Further product and user validation

## Third-party Notice

本地 `human_demo.glb` 来自 Khronos glTF Sample Assets 的 RiggedFigure，采用 CC BY 4.0 许可。来源与署名见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
