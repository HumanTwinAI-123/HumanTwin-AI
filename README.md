# HumanTwin AI

HumanTwin AI 是面向中文用户的 Android-first 3D 形象 App。当前源码快照是 **Mock v1**：选择三视图照片、模拟生成、查看示例模型，并在本机保存记录、管理形象、分享或导出。模拟结果不是根据所选照片重建的个人形象。

历史正式发布：**[v0.1.0 Final Demo Release](https://github.com/HumanTwinAI-123/HumanTwin-AI/releases/tag/v0.1.0)**。该发布对应早期六屏 Demo；当前 v1 源码已归档；尚未发布新的正式 APK/Release。

## Core Experience

```text
欢迎页 → 首页 / 我的形象 / 设置
创建：拍摄说明 → 选择照片 → 检查并提交 → 模拟生成进度
结果：3D 形象详情 → 本机形象库 → PNG / GLB 分享或保存
```

## Current Local v1 (Mock)

当前代码已实现，设备验收状态见下文：

- 欢迎页、首页、我的形象、设置及创建、任务、详情、分享流程
- Camera / Gallery 三视图选择、替换、删除与本机草稿恢复
- Mock 任务进度、持久化任务记录及中断恢复机制
- 本机形象库、重命名、删除、来源标签与文件状态
- 本地 GLB 查看、旋转、缩放、自动旋转、重置视角与重新加载
- PNG 预览、GLB 导出、系统分享、相册与系统文件选择器保存
- 拍摄说明开关、照片副本自动清理、隐私说明、清除本机数据、帮助与许可页

## Demo Boundary

- 默认 **Mock** 不上传照片，所有模拟生成结果使用同一个预生成的本地示例 GLB。
- 草稿、任务、设置与形象记录保存在 App 私有目录；默认在模型保存后删除任务照片副本，不删除相册原图。
- 当前有本机形象库与生成记录；没有账号、个人资料、跨设备同步、云端历史、生产后端、支付、AR、人体测量或医疗分析。
- 删除本机形象不会撤回已经分享给其他应用的文件。本地 v1 不代表生产系统或真实重建能力。

## Generation Modes

- 默认：离线 Mock 模式，模拟生成并显示内置示例模型，界面会明确标注「模拟生成 / 示例模型」。
- 开发配置：构建时设置非秘密的 `HUMANTWIN_API_BASE_URL`，Repository 才切换为 `ApiDigitalTwinRepository`。设置页只显示生成方式，不能在应用内切换。
- 本机代理默认 fake 模式，可执行「创建任务 → 轮询 → 下载 GLB → Viewer」链路，结果仍为示例；照片只发送到本机代理。
- 真实 Meshy 接入代码已预留，**本轮没有实际调用、真实照片上传或付费生成验证**。配置代理地址不等于真实生成已验收。

运行方式、防重复创建规则与限制见 [docs/meshy-api.md](docs/meshy-api.md)。

## Verification

- 2026-10-01 已有本地检查：`flutter analyze --no-pub` 为 0 issues，`flutter test --no-pub` 为 **122 / 122 PASS**。
- 2026-10-01 **Android API 36 模拟器**的收尾用例已通过：中断恢复、PNG / GLB 系统分享与保存、SAF 覆盖和失败保留、小屏 200% 字体及错误重载。
- 公开源码归档范围、已核对的源码哈希及验证边界见 [发布盘点](docs/PUBLISH_STATUS_2026-10-02.md)。完整设备截图、备份和原始日志仅保留本地，没有随本次代码归档上传。
- 以上本地检查及模拟器结果不构成当前 v1 的物理机完整验收，也不构成真实 API 或生产验证。

## Historical v0.1.0 Verification

以下是历史六屏版本的验证记录，保留用于追溯，不代表当前本地 v1 已完成同等真机验收：

- `flutter analyze --no-pub`：0 issues
- `flutter test --no-pub`：46 / 46 PASS
- Physical Android：Xiaomi `23049RAD8C`，Android 15 / API 35
- Final Release Smoke：PASS
- Viewer re-entry：5 / 5 PASS
- Viewer rapid exit：10 / 10 PASS
- Full Demo loop：3 / 3 PASS
- P0：0
- P1：0

历史证据见 [Day 10 Evidence Index](docs/evidence/day-10/README.md)。

## Release

历史正式版本：**v0.1.0**，不是当前本地 v1 的新发布。

[HumanTwin AI v0.1.0 — Final Demo Release](https://github.com/HumanTwinAI-123/HumanTwin-AI/releases/tag/v0.1.0) 包含：

- Android Release APK
- Final Demo Video
- Delivery Manifest
- SHA256SUMS

## Design

- v1 产品与页面设计提案仅保留本地，没有随本次代码归档发布；当前行为与验收状态以源码和验证说明为准。
- [Figma — 历史 Approved Home Hero v2](https://www.figma.com/design/JN4IsUqG7tLuwqcGbjbd1k/HumanTwin-AI?node-id=274-15)

## Project Records

- [Notion — 历史 Day 10 Final Delivery](https://app.notion.com/p/3bf38defc2eb8139a6f5dd935fef86e1?pvs=204)

## Known Limitations

完整能力边界与已知限制见 [docs/KNOWN_LIMITATIONS.md](docs/KNOWN_LIMITATIONS.md)。

## Historical Demo Script

历史六屏版本的演示流程见 [docs/DEMO_SCRIPT.md](docs/DEMO_SCRIPT.md)，不是当前 v1 全流程验收脚本。

## Local Run

```bash
flutter run --no-pub -d <android-device-id>
```

```bash
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --release --no-pub
```

## Architecture Boundary

```text
Flutter UI
→ Riverpod Controllers (PhotoFlow / Library / Settings / Share)
→ DigitalTwinRepository
→ MockDigitalTwinRepository / ApiDigitalTwinRepository
```

`PhotoFlowController` 管理创建草稿；`LibraryController` 管理持久化任务与形象记录。生成服务仍通过 Repository 接入，UI 不直接持有供应商密钥。

## Next Stage

当前本地 Mock v1 的本轮模拟器收尾已完成；以下能力尚未完成验证：

- 当前 v1 的物理 Android 设备完整验收及 iOS 等价验收
- 真实生成 API、真实模型质量、成本与 Android 性能验证
- 生产服务与公开发布准备

## Third-party Notice

当前 `human_demo.glb` 基于 MakeHuman 官方 CC0 核心资产，经 Blender 加工为合成示例模型。历史 RiggedFigure 等旧模型及署名在历史版本或本地材料中保留；来源与导出规则见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
