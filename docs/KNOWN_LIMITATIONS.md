# HumanTwin AI — Known Limitations

本文记录当前 **Mock v1 源码快照**的能力边界与验证限制。历史正式发布 `v0.1.0` 是六屏 Demo；当前 v1 已增加本机形象库、持久化与分享保存，尚未作为新正式版本发布。

## 1. AI Reconstruction

- 默认 Repository 为 Mock，创建进度是模拟，Viewer 展示预生成的本地示例 GLB。
- 默认模式中，三张照片不会真实生成 Viewer 内的模型；多个模拟结果使用同一示例，不代表用户本人的形象。
- 当前示例基于 MakeHuman 官方 CC0 核心资产，经 Blender 加工；不使用用户照片。当前与历史模型来源见 [第三方说明](../THIRD_PARTY_NOTICES.md)。
- 当前不包含人体重建算法、人体测量或医疗分析能力。

## 2. Backend

- 当前没有生产 backend 或 cloud storage。
- 未指定 `HUMANTWIN_API_BASE_URL` 时，`DigitalTwinRepository` 使用 `MockDigitalTwinRepository`；构建时指定代理地址才使用 `ApiDigitalTwinRepository`。设置页的生成方式说明是只读信息，不是模式切换按钮。
- `server/meshy_proxy.py` 是本机开发代理，其默认 fake 模式不调用 Meshy。本机 fake 链路不等于生产服务或真实重建。
- 真实 Meshy 接入代码已预留，但本轮没有真实 API 调用、真实照片上传或付费生成验证；详见 [Meshy 接入说明](meshy-api.md)。
- 默认 Mock 不发送照片；本机 fake 模式仅发送到开发代理，不外发到 Meshy。App 会在私有目录保存用于草稿和任务恢复的照片副本，不能把“不上传”理解为“不保存”。

## 3. Local Storage and Sharing

- 当前已实现本机形象库、任务记录、草稿及设置持久化；Mock 记录保存示例模型的资产引用，服务返回的文件模型保存到 App 私有目录。
- 默认在模型保存后清理任务照片副本，可在隐私设置中关闭；相册原图不删除。清除应用数据或卸载会删除本机记录；产品没有云端同步或备份功能，系统级备份与设备迁移不在本轮验收范围。
- PNG 预览、GLB 导出、系统分享、相册保存和系统文件选择器保存路径已实现；本轮 API 36 模拟器的分享、相册与 GLB 文件保存已验收，平台覆盖边界见本轮报告。
- 删除本机形象不撤回已分享的副本。临时分享/导出文件位于缓存，启动时清理，不作为持久化形象库。

## 4. Android-first Verification

- 2026-10-01 已有 `flutter analyze --no-pub` 为 0 issues，`flutter test --no-pub` 为 **122/122 PASS**；设备验收使用 **Android API 36 模拟器**。
- 本轮模拟器收尾用例已通过；公开归档验证摘要见 [发布盘点](PUBLISH_STATUS_2026-10-02.md)；完整原始验收材料仅保留本地。
- Day 9 / Day 10 的 Xiaomi `23049RAD8C`、Android 15 / API 35 物理机证据属于历史六屏版本，不是当前本地 v1 的真机验收。
- 当前不宣称已完成等价的 iOS 全流程与稳定性验证。
- WebView 首次初始化、贴图解析与首帧耗时依赖设备和构建模式；当前有 Debug 分段计时，最终观察以本轮设备报告为准。模拟器结果不能直接推广到所有 Android 版本和文件提供器。

## 5. `retrieveLostData()` Extreme Lifecycle Path

历史 Day 8 在 MIUI 设备上尝试了低内存与 Activity 重建场景，但没有形成可确定复现的 `retrieveLostData()` 恢复回调。

历史常规 Gallery / Camera Activity 切换、取消、替换和状态保持已有证据；当前 v1 有草稿及待选角度持久化、lost-data 恢复实现与单元测试。普通重启恢复不等于确定复现了极端系统回收回调，仍不宣称已完成该路径的确定性实机验证。

## 6. Historical WebView Renderer Teardown Logs

历史六屏版本的 Viewer 主动退出期间出现过 Chromium isolated renderer：

```text
Renderer process (...) crash detected (code -1)
```

对应历史物理机压力验证中：

- 主 App PID 保持不变
- ANR：0
- FATAL EXCEPTION：0
- FlutterError：0
- Viewer 可正常重新进入
- 完整 Demo loop：3/3 PASS

当时的对应进程被 Android `ApplicationExitInfo` 识别为不再需要的隔离 WebView sandbox，状态为 0，记录为非阻塞 P2 observation。该历史分类不替代当前 v1 的日志与退出稳定性验收。

## 7. Product Scope

当前 v1 已包括本机生成记录与形象管理，不再是只有六屏、没有历史记录的版本。以下能力仍不包含：

- Login
- Profile
- 云端历史 / 跨设备同步
- Medical Analysis
- AR
- Real AI reconstruction
- Production backend
- Cloud storage
- Payments

这些能力不属于当前本地 Mock v1 的实现与验收范围。
