# HumanTwin AI — 本地生成代理与 Meshy 接入

本文说明「选三张照片 → 创建任务 → 轮询状态 → 下载 GLB → 3D Viewer 查看」链路的运行方式。
当前只用本地 fake API 验证；**没有调用过真实 Meshy API**，也没有上传过真实照片。

## 运行模式

| 模式 | 如何启用 | 行为 |
| --- | --- | --- |
| Mock（默认） | 普通 `flutter run` | 完全离线，模拟生成，显示内置示例模型。 |
| 本地 fake API | 启动 `server/meshy_proxy.py`（默认 fake）并传入 `HUMANTWIN_API_BASE_URL` | App 真实走「创建任务、轮询、下载 GLB」协议；代理返回模拟任务和内置示例 GLB。界面标注「模拟生成 / 示例模型」。 |
| Meshy（未来，未实测） | 代理加 `--upstream meshy`，并在代理进程环境设置 `MESHY_API_KEY` | 代理把三张照片转发给 Meshy Multi-Image to 3D，**会消耗 Meshy 额度**。 |

无论哪种模式，App 都不会声称模型是根据照片重建的：模拟任务和示例模型会明确标注；
服务返回的模型只说明「仅供演示，不代表精确人体数据」。

## 快速开始（fake API + Android）

```bash
python3 server/meshy_proxy.py
```

```bash
adb reverse tcp:8787 tcp:8787
```

```bash
flutter run --dart-define=HUMANTWIN_API_BASE_URL=http://127.0.0.1:8787
```

- 代理只监听本机回环地址（默认 `127.0.0.1:8787`）。`adb reverse` 让模拟器或 USB 真机的
  `127.0.0.1:8787` 指向电脑上的代理，无需修改 Android 网络配置。
- 使用 `adb reverse` 时如果代理没有启动，App 会显示「未确认任务是否已创建」（连接在请求发出后才被关闭，
  无法判断是否已提交）；启动代理后点「重试」即可，代理会按照片内容去重。
- `HUMANTWIN_API_BASE_URL` 不是密钥；不传时 App 保持 Mock 模式。
- 健康检查：`curl http://127.0.0.1:8787/v1/health`。
- 模拟任务时长可调：`--fake-duration 6`（秒）。

## 链路与接口

`PhotoFlowController`（唯一持有三张照片）→ `GenerationController` → `DigitalTwinRepository`：
Mock 模式为 `MockDigitalTwinRepository`，配置了 URL 时为 `ApiDigitalTwinRepository`。

| 步骤 | 请求 | 说明 |
| --- | --- | --- |
| 创建 | `POST /v1/generations` | JSON：按正面、侧面、背面顺序的 3 个 JPEG/PNG data URI。App 端先检查文件头，单张不超过 8 MB。 |
| 轮询 | `GET /v1/generations/{task_id}` | 返回 `PENDING / IN_PROGRESS / SUCCEEDED / FAILED / CANCELED` 和进度。 |
| 下载 | `GET /v1/generations/{task_id}/model.glb` | 仅 `SUCCEEDED` 后可用。App 限制 64 MB、校验 GLB 头和长度，原子写入应用临时目录 `humantwin_models/<task_id>.glb`。 |

Viewer 通过 `file://` 加载下载的模型，沿用现有 WebView host、重新加载和安全退出逻辑。

## 防止重复创建付费任务

代理是唯一能创建上游任务的组件，按「三张照片有序原始字节」的 SHA-256 识别同一输入：

- 同一组照片再次提交会返回同一个任务（`reused: true`），不会再次调用上游创建接口。
- 创建请求串行处理；调用上游前先把记录写为 `creating`。
- 上游明确拒绝（400/401/402/403/422/429 或连接被拒绝）时删除记录，之后可以重新提交。
- 超时、连接中断、5xx 或响应格式异常时，无法确定是否已创建，记录为 `submission_unknown`；
  代理之后对这组照片返回 `409 submission_unknown`，**永不自动重新提交**。代理进程在创建中途退出时，
  下次启动会把残留的 `creating` 记录同样转为 `submission_unknown`。

App 端：

- 创建请求已发出但响应丢失时，状态为「未确认任务是否已创建」，不会自动重试；重新进入 Processing
  也不会自动提交。只有用户点「重试」才会用同一组照片再次请求代理，由代理按内容去重。
- 已拿到任务后，重新进入 Processing、轮询重试、下载重试都只发 `GET`；已下载并校验的模型直接复用。
- 轮询默认最长 10 分钟，超时只停止查询，点「重试」继续查询同一任务。
- 已失败（`FAILED` / `CANCELED`）的任务对同一组照片会一直返回失败结果，需要更换照片后重新开始。

处理 `submission_unknown`：先列出未确认记录，按提交时间在 Meshy 控制台确认是否已有对应任务：

```bash
sqlite3 server/.data/generation_tasks.sqlite3 "SELECT upstream, input_hash, datetime(created_at, 'unixepoch') FROM generations WHERE state = 'submission_unknown';"
```

只有确认 Meshy 上**没有**对应任务后，才停止代理并按 `upstream` 和 `input_hash` 删除那一条记录；
如果任务已存在，不要删除记录，否则同一组照片会再次创建付费任务：

```bash
sqlite3 server/.data/generation_tasks.sqlite3 "DELETE FROM generations WHERE state = 'submission_unknown' AND upstream = '<upstream>' AND input_hash = '<input_hash>';"
```

## 密钥、照片与数据保留

- `MESHY_API_KEY` 只从代理进程环境读取，不写入 Flutter 源码、`--dart-define`、APK、日志或任何响应。
- 代理只在内存中校验并转发照片，不把照片写入磁盘；日志不包含照片、密钥、签名 URL 或上游原始错误。
  带 `Origin` 头的浏览器请求会被拒绝。
- 任务元数据（输入哈希、任务 ID、状态、进度、时间戳）保存在 `server/.data/generation_tasks.sqlite3`，
  已被 Git 忽略，会一直保留到手动删除。记录按上游范围隔离：每个 fake 故障场景、每个 Meshy 地址各自独立，
  演练数据不会影响默认演示或真实 API。
- Meshy 模式下，下载过的模型缓存在 `server/.data/models/`，重试和重新进入不会重复下载；fake 模式不缓存。
- 使用 Meshy 模式时，照片会上传到 Meshy，适用 Meshy 自身的数据政策。

## 故障演练（仅 fake 模式）

`python3 server/meshy_proxy.py --fake-scenario <场景>`（每个场景的任务记录互相独立）：

| 场景 | 效果 |
| --- | --- |
| `ok` | 默认，正常完成。 |
| `task-failed` | 任务最终为 `FAILED`。 |
| `lost-create-response` | 新任务已创建但不返回响应，模拟 App 丢失创建响应；「重试」会拿回同一任务。 |
| `upstream-unknown` | 模拟代理与上游之间超时，记录变为 `submission_unknown`。 |
| `flaky-poll` | 每隔一次状态查询返回临时错误，App 只用 `GET` 重试。 |

## 接入真实 Meshy（尚未验证）

需要可用于 API 的 Meshy 密钥和额度。只在本机当前 shell 中设置密钥，不要写入仓库文件：

```bash
MESHY_API_KEY=<your key> python3 server/meshy_proxy.py --upstream meshy
```

代理固定使用 `ai_model: meshy-7.1`、`geometry_resolution: standard`、`should_texture: true`、
`should_remesh: true`、`target_polycount: 30000`、`target_formats: ["glb"]`，不启用 2k 几何、PBR 或高分辨率贴图。
协议依据 2026-09-30 查阅的官方文档：
[Multi-Image to 3D](https://docs.meshy.ai/en/api/multi-image-to-3d)、
[Errors](https://docs.meshy.ai/en/api/errors)。
首次真实调用、费用、耗时、返回模型大小与 Viewer 表现都需要另行验收。

## 已知限制

- 只支持 JPEG / PNG；HEIC、WebP 等格式会被拒绝，需要换图。
- 下载的模型在应用临时目录，系统清理缓存后需要重新下载（只发 `GET`）。
- 生成质量、人体比例与精度均未验证，不用于测量或医疗用途。

## 测试

```bash
python3 -m unittest -v server/test_meshy_proxy.py
```

```bash
flutter test --no-pub
```
