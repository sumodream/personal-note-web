# 灵感工作台 · 云同步部署说明

一套 Cloudflare Worker + R2 的最简同步后端：前端整份 `state` JSON 存进 R2 的一个对象，靠 `version` 做覆盖冲突检测。

## 一、部署（一次性，约 5 分钟）

在 `cloudflare-sync` 目录执行：

```powershell
npx wrangler login
npx wrangler r2 bucket create idea-studio
npx wrangler secret put SYNC_TOKEN   # 粘贴一个足够长的随机串，比如 openssl rand -hex 24
npx wrangler deploy
```

`deploy` 会打印 Worker 地址，形如 `https://idea-studio-sync.<你的子域>.workers.dev`。

> 第一次用 `npx wrangler` 时，它可能提示安装包，直接同意即可。需要 Node 18+。
> 如果 Node 在 `file://` 页面下访问 Worker 报 CORS，本 Worker 已返回 `Access-Control-Allow-Origin: *`，正常无需改动。

## 二、前端启用

打开「灵感工作台」→ 侧栏底部 **云同步** → 填：

- **Worker 地址**：`https://idea-studio-sync.xxx.workers.dev`（不用带 `/api/sync`，会自动剥掉）
- **同步口令**：与 `SYNC_TOKEN` 一致

点「保存并同步」。云端为空则把本机数据上传；云端有数据且本机也有内容时会弹冲突窗口让你选。

侧栏按钮右侧的小圆点表示状态：无点=未配置，橙=有改动待上传，绿=已同步，红=上次失败。

## 三、接口约定

```
GET  /api/sync   → 200 {version, savedAt, data} ｜ 404 {empty:true}
PUT  /api/sync   → body {data, baseVersion, force}
                   → 200 {ok:true, version, savedAt}
                   → 409 {conflict:true, version, savedAt, data}
                   → 401 口令不匹配
请求头：Authorization: Bearer <SYNC_TOKEN>
```

`baseVersion` 与云端当前 `version` 不一致且 `force` 不为 `true` 时返回 409，前端据此弹冲突选择框；`force=true` 直接覆盖。

## 四、费用与限制

- Workers Free：100,000 请求/天。本方案每次同步 1 个请求，60 秒兜底轮询只在有改动时才发，日常用量远低于额度。
- R2 Free：10 GB 存储、Class A（写）1,000 万次/月、Class B（读）1,000 万次/月。整份 JSON 几十 KB 级，完全够用。
- 单次请求体上限：Workers 免费版 100 MB 请求体，数据量远达不到。

## 五、已知取舍

- **图片不同步**：正文里的图片存在本机 IndexedDB，只同步文字与占位符 `![图片](asset:img_xxx)`。换设备能看到文字但看不到图；需要图片也跨设备，得另加对象存储通道。
- **冲突粒度是整份数据**：不做字段级合并。两端同时改会由你选一边，另一边被覆盖。多设备交替使用时，建议每次改完等圆点变绿再换设备。
- **口令存在 localStorage**：与数据同源。如果页面同时用 `file://` 和 `https://` 打开，两边的配置互不相通，需各自填一次。
- 没有服务端历史版本；想要回滚，靠侧栏「导出备份」的 JSON。
