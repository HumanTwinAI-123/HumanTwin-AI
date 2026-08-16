# HumanTwin AI

HumanTwin AI 是一个 Flutter Android-first AI 数字人体前端体验 Demo，用于验证完整、可信且可演示的移动端产品流程。

## 核心流程

```text
Home
→ Photo Guide
→ Photo Selection
→ Photo Confirmation
→ Mock AI Processing
→ 3D Viewer
```

## 当前边界

- 三视图照片选择、Camera / Gallery 与跨页面照片状态是真实 Flutter 功能。
- AI Processing 使用 Mock Repository，不执行真实 AI 人体重建。
- 3D Viewer 展示预生成的 Local GLB，支持旋转、缩放、自动旋转和重新加载。
- 当前没有真实 backend API、照片上传或云存储。
- Demo 的目标是验证从照片采集到数字人体查看的完整移动端产品体验。

## 技术栈

- Flutter 3.44.9 / Dart 3.12.2
- Material 3
- Riverpod
- `go_router`
- `image_picker` / `XFile`
- `model_viewer_plus`
- Local GLB
- Mock Repository

## 当前完成状态

- Six-screen flow complete
- Physical Android verified
- Release APK validated
- Home Hero v2 approved on Day 9
- Release Candidate ready for Day 10 final delivery

## 稳定性摘要

- `flutter analyze --no-pub`：0 issues
- `flutter test --no-pub`：46/46 PASS
- Physical Android E2E：PASS
- Viewer re-entry：5/5 PASS
- Viewer rapid exit：10/10 PASS
- Full demo loop：3/3 PASS
- P0：0
- P1：0

完整验证证据见 [Day 9 Evidence Index](docs/evidence/day-9/README.md)。项目限制见 [Known Limitations](docs/KNOWN_LIMITATIONS.md)，正式演示流程见 [Demo Script](docs/DEMO_SCRIPT.md)。

## 本地运行与验证

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

## Third-party Notice

本地 `human_demo.glb` 来自 Khronos glTF Sample Assets 的 RiggedFigure，采用 CC BY 4.0 许可。来源与署名见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
