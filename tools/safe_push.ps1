<#
  保守推送脚本：fetch → 检查分叉/落后 → 校验入口与主产物一致 → 跑测试 → 不带 force 推送
  用法：.\tools\safe_push.ps1        正常推送
        .\tools\safe_push.ps1 -SkipTests   跳过测试（仅限紧急，慎重）
#>
param([switch]$SkipTests)

$ErrorActionPreference = 'Stop'
$Root    = Split-Path -Parent $PSScriptRoot
$Git     = 'D:\Git\cmd\git.exe'
$Proxy   = 'http://127.0.0.1:7897'
$Branch  = 'main'
$Main    = '灵感工作台.html'
$Entry   = 'index.html'

function Step($m){ Write-Host ""; Write-Host "== $m ==" -ForegroundColor Cyan }
function Fail($m){ Write-Host "FAIL  $m" -ForegroundColor Red; exit 1 }
function Ok($m){ Write-Host "OK    $m" -ForegroundColor Green }

Push-Location $Root
try {
  Step '分支检查'
  $cur = (& $Git rev-parse --abbrev-ref HEAD).Trim()
  if ($cur -ne $Branch) { Fail "当前在 $cur，不是 $Branch" }
  Ok "branch=$cur"

  Step '工作区'
  $dirty = & $Git status --porcelain
  if ($dirty) { Fail ("有未提交改动，先提交：`n" + ($dirty -join "`n")) }
  Ok '工作区干净'

  Step 'fetch'
  & $Git -c "http.proxy=$Proxy" -c "https.proxy=$Proxy" fetch origin 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { Fail 'fetch 失败（确认 127.0.0.1:7897 代理在监听）' }

  Step '同步状态'
  $ahead  = [int](& $Git rev-list --count "origin/$Branch..HEAD")
  $behind = [int](& $Git rev-list --count "HEAD..origin/$Branch")
  if ($ahead -gt 0 -and $behind -gt 0) { Fail "已分叉：领先 $ahead、落后 $behind，需人工处理，不要自动 merge/rebase" }
  if ($behind -gt 0) { Fail "落后远端 $behind 个提交，先执行 git merge --ff-only origin/$Branch" }
  if ($ahead -eq 0) { Fail '没有需要推送的提交' }
  Ok "领先 $ahead 个提交、落后 0"

  Step '产物一致性'
  $h1 = (Get-FileHash -LiteralPath (Join-Path $Root $Main)  -Algorithm SHA256).Hash
  $h2 = (Get-FileHash -LiteralPath (Join-Path $Root $Entry) -Algorithm SHA256).Hash
  if ($h1 -ne $h2) { Fail "$Entry 与 $Main 不一致，先用 Copy-Item 覆盖并提交" }
  Ok 'index.html 与主产物字节一致'

  if (-not $SkipTests) {
    Step '语法检查'
    python _shots\extract_js.py | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail 'extract_js.py 失败' }
    node --check _shots\inline.js
    if ($LASTEXITCODE -ne 0) { Fail 'node --check 失败' }
    Ok 'inline.js 语法通过'

    Step '测试'
    $files = @(Get-ChildItem (Join-Path $Root '_shots') -Filter '*.js' |
               Where-Object { $_.Name -like 'fixture_*.js' -or $_.Name -eq 'smoke_test.js' } |
               Sort-Object Name)
    $bad = @()
    foreach ($f in $files) {
      $out = & node $f.FullName 2>&1
      $line = ($out | Select-String -Pattern 'passed|FAIL|ERROR' | Select-Object -Last 1)
      Write-Host ("  {0,-22} {1}" -f $f.Name, $line)
      if ($LASTEXITCODE -ne 0) { $bad += $f.Name }
    }
    if ($bad.Count -gt 0) { Fail ("测试未通过：" + ($bad -join ', ')) }
    Ok "共 $($files.Count) 套测试通过"
  }

  Step 'push'
  & $Git -c "http.proxy=$Proxy" -c "https.proxy=$Proxy" push origin $Branch
  if ($LASTEXITCODE -ne 0) { Fail '推送失败：不要改写成 force，先排查网络/代理/权限' }

  Step '核对'
  $local  = (& $Git rev-parse HEAD).Trim()
  $remote = (& $Git rev-parse "origin/$Branch").Trim()
  if ($local -ne $remote) { Fail "本地 $local 与 origin/$Branch $remote 不一致" }
  Ok "已推送 $($local.Substring(0,7))"
}
finally { Pop-Location }
