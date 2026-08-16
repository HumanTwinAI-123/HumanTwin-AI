# HumanTwin AI — Known Limitations

本文记录当前 Release Candidate 的真实能力边界与已知验证限制。

## 1. AI Reconstruction

- 当前 AI Processing 是 Mock generation pipeline。
- Viewer 展示预生成的 Local GLB。
- 三张照片不会在当前版本中真实生成 Viewer 内展示的 GLB。
- 当前不包含人体重建算法、人体测量或医疗分析能力。

## 2. Backend

- 当前没有真实 backend API、照片上传或 cloud storage。
- `DigitalTwinRepository` 已保留未来替换实现的边界；当前使用 `MockDigitalTwinRepository`。
- 当前照片仅服务于前端演示流程，不代表已上传或持久化到云端。

## 3. Android-first Verification

- 当前正式验证重点为 Android。
- Day 9 Release Candidate 已在 Xiaomi `23049RAD8C`、Android 15 / API 35 物理设备上完成验证。
- 当前不宣称已完成等价的 iOS 全流程与稳定性验证。

## 4. `retrieveLostData()` Extreme Lifecycle Path

Day 8 在 MIUI 设备上尝试了低内存与 Activity 重建场景，但没有形成可确定复现的 `retrieveLostData()` 恢复回调。

常规 Gallery / Camera Activity 切换、取消、替换和照片状态保持均已通过；极端进程回收后的 lost-data 恢复路径仍属于验证限制，不宣称已经完成确定性实机验证。

## 5. WebView Renderer Teardown Logs

Viewer 主动退出期间可能出现 Chromium isolated renderer：

```text
Renderer process (...) crash detected (code -1)
```

现有物理机压力验证中：

- 主 App PID 保持不变
- ANR：0
- FATAL EXCEPTION：0
- FlutterError：0
- Viewer 可正常重新进入
- 完整 Demo loop：3/3 PASS

对应进程被 Android `ApplicationExitInfo` 识别为不再需要的隔离 WebView sandbox，状态为 0。因此当前分类为非阻塞 P2 observation，不等同于 App crash。

## 6. Product Scope

当前版本不包含：

- Login
- Profile
- History
- Medical Analysis
- AR
- Real AI reconstruction
- Production backend
- Cloud storage
- Payments

这些能力不属于当前六屏 Demo 的已交付范围。
