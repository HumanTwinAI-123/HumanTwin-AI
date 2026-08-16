# HumanTwin AI — Demo Script

目标时长：2–3 分钟。主演示使用已验证的 Android Release Candidate。

## 0. Opening — 15 秒

讲解：

> HumanTwin AI 是一个 AI 数字人体移动端体验 Demo。当前重点验证三视图采集、Mock AI Processing 和 3D Digital Human Viewer 的完整前端流程。真实 AI backend 尚未接入。

## 1. Home — 15 秒

- 展示 HumanTwin AI 品牌与 Day 9 Approved Hero v2。
- 点击“开始创建”。

## 2. Photo Guide — 15 秒

- 简要说明正面、侧面、背面三视图要求。
- 强调清晰、完整与背景简洁即可，不扩展医疗或人体分析描述。

## 3. Photo Selection — 30 秒

- 展示 Front、Side、Back 三个照片位。
- 使用 Gallery 或 Camera 完成三张照片选择。
- 确认三个照片位均已填充后继续。
- 主演示不需要刻意测试 Cancel、Replace、Remove 等异常或回归路径。

## 4. Confirmation — 15 秒

- 确认三张照片映射正确。
- 点击 CTA 进入生成流程。

## 5. Processing — 15 秒

讲解：

> 这里当前运行的是 Mock AI generation pipeline，用于验证生成状态和完整产品体验；它不代表真实人体重建正在运行。

- 展示 Processing 到 Success 的状态变化。

## 6. Viewer — 40 秒

- 进入 3D Viewer，等待 Local GLB 完成加载。
- 拖动模型展示 rotate。
- 双指手势展示 zoom。
- 展示 autoRotate。
- 点击 Reload，确认模型重新加载。
- 说明 Viewer 已完成真实 Android 物理机稳定性验证，包括重复进入、快速退出与完整流程循环。

## 7. Closing — 20 秒

讲解：

> 当前版本验证了从三视图采集到数字人体查看的完整前端体验。Repository 和六屏流程已经为未来接入真实 AI API 保留替换边界。

## Demo Fallback

主演示路径始终是 Local GLB interactive Viewer。如果 Viewer 临时加载异常：

1. 点击 Viewer 内的 Reload。
2. 返回 Processing Success 后再次进入 Viewer。
3. 必要时使用现有 Static Poster / Preview 继续说明 Viewer 体验边界。

不要临时切换新的 3D package，也不要联网寻找 Remote GLB。

## Presenter Guardrails

- 不宣称三张照片真实生成当前 GLB。
- 不宣称真实 AI reconstruction 或 backend 已完成。
- 不使用“医疗级”“自研人体重建算法”等表述。
- 不将当前 Demo 描述为已正式发布的生产系统。
