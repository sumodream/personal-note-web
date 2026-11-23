# 灵感工作台 · 云同步配置说明

两种存储后端，页面里选一种即可：

- **GitHub 私有仓库（推荐）**：不用部署任何服务，只要一个 Token。
- **Cloudflare Worker + R2**：需要自己部署 Worker，见文末附录。

只同步文字数据。正文里的图片存在本机 IndexedDB，只同步 `![图片](asset:img_xxx)` 占位符，换设备能看到文字、看不到图。

---

## 一、GitHub 私有仓库（推荐）

### 1. 建一个私有仓库

GitHub → New repository → 名字随意（如 `personal-note-data`）→ **必须选 Private** → 勾选 Add a README（让默认分支存在）→ Create。

仓库必须私有：公开仓库里的文件任何人都能读，数据就等于公开了。

### 2. 建 Token

推荐 fine-grained token：右上头像 → Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token

- Repository access：Only select repositories → 只选刚建的那个仓库
- Permissions：Repository permissions → **Contents: Read and write**（其余不用给）

生成的串以 `github_pat_` 或 `ghp_` 开头，只显示一次，复制下来。

### 3. 在工作台里填

侧栏底部「云同步」→ 存储方式选 GitHub → 仓库填 `你的用户名/personal-note-data` → 路径留空（默认 `state.json`）→ 分支 `main` → 粘贴 Token → 保存并同步。

云端为空时会把本机数据推上去；云端已有数据且本机也有内容时，会弹窗让你选保留哪一边。

---

## 二、同步机制与状态

- 打开页面自动拉取一次；本机改动后约 2.5 秒自动上传，另有每 60 秒兜底检查。
- 侧栏「云同步」右侧小圆点：无点=未配置，橙=有改动待上传，绿=已同步，红=上次失败。
- 冲突检测：GitHub 用文件 sha 做乐观锁，sha 变了就返回冲突，不会静默覆盖别的设备。

接口约定：

```
GET  https://api.github.com/repos/{repo}/contents/{path}?ref={branch}
     → 200 {sha, content(base64)} ｜ 404 文件不存在
PUT  同一地址
     body {message, content(base64 of {savedAt, data}), branch, sha?}
     → 200/201 {content:{sha}} ｜ 409 sha 不匹配 ｜ 422 缺 sha
请求头 Authorization: Bearer <token>，Accept: application/vnd.github+json
```

## 三、额度与限制

- 带 Token 的请求限额 5,000 次/小时，单人使用远远够（每次同步 1~2 个请求）。
- 单文件 100 MB 上限；整份 JSON 通常几十 KB。
- 每次同步产生一个 commit，仓库历史会变长但不影响使用；介意可以定期重建仓库。

## 四、已知取舍

- 图片不跨设备。
- 冲突粒度是整份数据，不做字段级合并。多设备交替用，建议等圆点变绿再换设备。
- Token 存在浏览器 localStorage，与数据同源。`file://` 与 `https://` 是不同来源，配置和数据互不相通，建议固定一种打开方式。

---

## 附录：Cloudflare Worker + R2（可选）

`cloudflare-sync` 目录已备好 Worker 代码与 `wrangler.toml`：

```powershell
npx wrangler login
npx wrangler r2 bucket create idea-studio
npx wrangler secret put SYNC_TOKEN
npx wrangler deploy
```

Worker 接口：`GET/PUT /api/sync`，`Authorization: Bearer <SYNC_TOKEN>`，R2 存单一对象（默认 `state.json`），PUT 带 `baseVersion` 做冲突检测，冲突返回 409 时前端同样弹选择框。

注意：`wrangler login` 的 OAuth 回调走 `localhost:8976`，如果本机浏览器/防火墙/代理拦住了这个回调，会一直报「Timed out waiting for authorization code」。遇到这种情况改用 `CLOUDFLARE_API_TOKEN` 环境变量部署，或直接走上面的 GitHub 方案。
