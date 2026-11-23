# 仓库工作流（保守规则）

本仓库只放代码与文档，**不放任何真实数据**。

## 一、仓库分工

| 位置 | 内容 | 可见性 |
| --- | --- | --- |
| `sumodream/personal-note-web` | `灵感工作台.html`、`index.html`、`cloudflare-sync/` 与文档 | Public（GitHub Pages 需要） |
| `sumodream/personal-note-data` | 只有 `state.json`，由页面云同步读写 | Private |

数据只存在于：浏览器 localStorage / IndexedDB、`personal-note-data` 私有仓库。代码仓库的提交历史里从未出现数据文件，也不应该出现。

## 二、提交规则

1. 一次提交只做一件事，信息以 `feat:` / `fix:` / `chore:` / `docs:` 开头，正文写清改了什么、为什么。
2. 提交前必须：
   - `python _shots\extract_js.py` 成功
   - `node --check _shots\inline.js` 通过
   - `_shots` 下的 `fixture_*.js` 与 `smoke_test.js` 全绿
3. 主产物改了必须同步 `index.html`（两者字节一致），否则不提交。
4. 禁止提交：`_backup/`、`_shots/`、`灵感工作台-备份-*.json`、任何 token / `.dev.vars`。这些已在 `.gitignore` 里兜住。
5. 不改写已经推送过的提交（不用 `rebase`、`filter-branch`、`commit --amend` 去改历史）。

## 三、拉取规则

1. 动代码前先 `git fetch origin`，确认本地是否落后。
2. 只接受快进合并：`git merge --ff-only origin/main`。不自动 merge，不自动 rebase 已推送历史。
3. 出现分叉（本地与远端各有新提交）时停下来汇报，由人决定怎么合。

## 四、推送规则

1. 只 `git push origin main`，**永不** `--force` / `--force-with-lease` / 删除远端分支。
2. 推送前跑 `tools\safe_push.ps1`，它会：
   - 校验分支是 `main`
   - `fetch` 并拒绝在落后或分叉状态下推送
   - 校验 `index.html` 与主产物一致
   - 跑全部测试
   - 通过才推送（不带 force）
3. 推送失败（网络、代理、权限）就停下报告，不重试、不换写法绕过。
4. 每次推送后确认 `origin/main` 的 sha 与本地 HEAD 一致。

## 五. 手动命令备忘

Git 不在 PATH，用绝对路径；GitHub 443 直连超时，必须带代理：

```powershell
$git = 'D:\Git\cmd\git.exe'
& $git -c http.proxy=http://127.0.0.1:7897 -c https.proxy=http://127.0.0.1:7897 fetch origin
& $git merge --ff-only origin/main
.\tools\safe_push.ps1
```

仓库级 git 配置（已设置）：`pull.ff=only`、`push.default=simple`、`fetch.prune=false`。
