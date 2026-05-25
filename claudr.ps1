# claudr.ps1 — launch Claude Code routed through OpenRouter,
# with a model picker driven by OpenRouter's live programming leaderboard.
#
# Usage:
#   claudr                          # launch with saved tier config (first run: setup wizard)
#   claudr -Tiers                   # re-run the 3-pick wizard to change tier config
#   claudr -Tiers -Preset coding    # run wizard and save picks as a named preset
#   claudr -Preset coding           # launch with a named preset
#   claudr -Presets                 # list saved presets, exit
#   claudr -Model kimi              # override only the main model for this launch
#   claudr -Ask "your prompt"       # one-shot non-interactive: prints just the reply
#   claudr -Doctor                  # health check: claude, fzf, key, tier slugs, caches
#   claudr -List                    # print top N, exit
#   claudr -View month              # ranking window: day | week | month | trending
#   claudr -Refresh                 # bypass 6h cache
#   claudr -- --resume              # forward remaining args to claude

[CmdletBinding()]
param(
  [string]$Model = $env:OPENROUTER_MODEL,
  [string]$Preset,
  [switch]$Tiers,
  [switch]$Presets,
  [switch]$Doctor,
  [string]$Ask,
  [switch]$List,
  [switch]$ListAll,
  [string]$View = $(if ($env:OPENROUTER_RANK_VIEW) { $env:OPENROUTER_RANK_VIEW } else { 'week' }),
  [int]$Top = $(if ($env:OPENROUTER_TOP_N) { [int]$env:OPENROUTER_TOP_N } else { 25 }),
  [switch]$Refresh,
  [Parameter(ValueFromRemainingArguments = $true)] [string[]]$Rest
)

$ErrorActionPreference = 'Stop'
$ConfigDir       = Join-Path $env:USERPROFILE '.claudr'
$KeyFile         = Join-Path $ConfigDir 'key'
$ModelsCache     = Join-Path $ConfigDir 'models.json'
$RankCache       = Join-Path $ConfigDir "rankings.v3.$View.tsv"
$TiersFile       = Join-Path $ConfigDir 'tiers.conf'
$PresetsDir      = Join-Path $ConfigDir 'presets'
$StatuslineFile  = Join-Path $ConfigDir 'statusline.ps1'
$SettingsFile    = Join-Path $ConfigDir 'settings.json'
if (-not (Test-Path $ConfigDir)) { New-Item -ItemType Directory -Path $ConfigDir | Out-Null }

# --- per-launch Tavily MCP config (NOT registered at user scope) ---
$TavilyKeyFile        = Join-Path $ConfigDir 'tavily-key'
$McpConfigFile        = Join-Path $ConfigDir 'mcp.json'
$GlobalCleanupMarker  = Join-Path $ConfigDir '.global-mcp-cleaned.v2'

# Read-only modes skip interactive setup so they work without keys configured.
$SkipInteractiveSetup = ($Doctor -or $Presets -or $List -or $ListAll)

function Prompt-TavilyKey {
  if (-not [Environment]::UserInteractive) { return $false }
  Write-Host ""
  Write-Host "  Set up web search (Tavily)" -ForegroundColor White
  Write-Host "  ----------------------------------------------------" -ForegroundColor DarkGray
  Write-Host "  Free tier 1000 queries/mo, AI-agent-friendly (no per-second cap)." -ForegroundColor DarkGray
  Write-Host "  Sign up: https://app.tavily.com   (no card required)" -ForegroundColor DarkGray
  Write-Host "  Press Enter to skip (you can set it later by writing it to $TavilyKeyFile)." -ForegroundColor DarkGray
  Write-Host ""
  $k = (Read-Host "  Key").Trim()
  if (-not $k) {
    Write-Host "  (skipped - search registration deferred)" -ForegroundColor DarkGray
    return $false
  }
  Set-Content -Path $TavilyKeyFile -Value $k -NoNewline -Encoding ascii
  Write-Host "  saved to $TavilyKeyFile" -ForegroundColor Green
  Write-Host ""
  return $true
}

# One-time cleanup of stale user-scope Tavily registrations from older versions.
if (-not (Test-Path $GlobalCleanupMarker) -and (Get-Command claude -ErrorAction SilentlyContinue)) {
  $prevEAP = $ErrorActionPreference
  $ErrorActionPreference = 'SilentlyContinue'
  try {
    foreach ($name in @('tavily','tavily-search','ddg-search','brave-search')) {
      & claude mcp remove -s user $name 2>&1 | Out-Null
    }
  } catch { }
  $ErrorActionPreference = $prevEAP
  $global:LASTEXITCODE = 0
  New-Item -ItemType File -Path $GlobalCleanupMarker -Force | Out-Null
}

# Tavily MCP config — skip in read-only modes.
if (-not $SkipInteractiveSetup) {
  $tkey = $env:TAVILY_API_KEY
  if (-not $tkey -and (Test-Path $TavilyKeyFile)) { $tkey = (Get-Content $TavilyKeyFile -Raw).Trim() }
  if (-not $tkey) {
    if (Prompt-TavilyKey) { $tkey = (Get-Content $TavilyKeyFile -Raw).Trim() }
  }
  if ($tkey) {
    $mcp = @{
      mcpServers = @{
        tavily = @{
          type = 'http'
          url  = "https://mcp.tavily.com/mcp/?tavilyApiKey=$tkey"
        }
      }
    } | ConvertTo-Json -Compress -Depth 5
    Set-Content -Path $McpConfigFile -Value $mcp -NoNewline -Encoding ascii
  } elseif (Test-Path $McpConfigFile) {
    Remove-Item $McpConfigFile -Force
  }
}

# --- API key prompt/save (re-invocable on Ctrl+A) ---
function Read-AndSaveApiKey {
  param([switch]$Rotate)
  if (-not [Environment]::UserInteractive) {
    Write-Error "claudr: no OpenRouter key. Set `$env:OPENROUTER_API_KEY or write $KeyFile"
    exit 1
  }
  $title   = if ($Rotate) { 'Change OpenRouter API key' } else { 'Set OpenRouter API key' }
  $divider = '────────────────────────────────────────────────────'
  Write-Host ""
  Write-Host "  🔑 $title" -ForegroundColor Cyan
  Write-Host "  $divider" -ForegroundColor DarkGray
  if ($Rotate) {
    Write-Host "  Current key: " -NoNewline -ForegroundColor DarkGray
    Write-Host "$KeyFile  " -NoNewline
    Write-Host "(will be replaced)" -ForegroundColor DarkGray
  }
  Write-Host "  Get a key at: " -NoNewline -ForegroundColor DarkGray
  Write-Host "https://openrouter.ai/keys" -ForegroundColor Cyan
  Write-Host "  Press " -NoNewline -ForegroundColor DarkGray
  Write-Host "Enter" -NoNewline -ForegroundColor Yellow
  Write-Host " on empty to cancel." -ForegroundColor DarkGray
  Write-Host ""

  $new = (Read-Host "  Key").Trim()

  if ([string]::IsNullOrWhiteSpace($new)) {
    if ($Rotate) { Write-Host "  cancelled - key unchanged." -ForegroundColor Yellow; Write-Host ""; return $false }
    Write-Host "  empty key, aborting." -ForegroundColor Yellow; exit 1
  }

  $preview = $new.Substring(0, [Math]::Min(12, $new.Length)) + '........'
  Write-Host ""

  if (-not $new.StartsWith('sk-or-')) {
    Write-Host "  Key doesn't start with 'sk-or-'." -ForegroundColor Yellow
    Write-Host "  Confirm: " -NoNewline
    Write-Host "Set API-KEY: " -NoNewline -ForegroundColor White
    Write-Host $preview
    $confirm = Read-Host "  Save anyway? [y/N]"
    if ($confirm -notmatch '^(y|yes)$') {
      Write-Host "  aborted - key unchanged." -ForegroundColor Yellow; Write-Host ""
      if ($Rotate) { return $false } else { exit 1 }
    }
  } else {
    Write-Host "  Confirm: " -NoNewline
    Write-Host "Set API-KEY: " -NoNewline -ForegroundColor White
    Write-Host $preview
    $confirm = Read-Host "  Save? [Y/n]"
    if ($confirm -match '^(n|no)$') {
      Write-Host "  cancelled - key unchanged." -ForegroundColor Yellow; Write-Host ""
      if ($Rotate) { return $false } else { exit 1 }
    }
  }
  Set-Content -Path $KeyFile -Value $new -NoNewline
  try {
    $acl = Get-Acl $KeyFile
    $acl.SetAccessRuleProtection($true, $false)
    $acl.Access | ForEach-Object { [void]$acl.RemoveAccessRule($_) }
    $rule = New-Object Security.AccessControl.FileSystemAccessRule(
      [Security.Principal.WindowsIdentity]::GetCurrent().Name, 'FullControl','Allow')
    $acl.AddAccessRule($rule)
    Set-Acl -Path $KeyFile -AclObject $acl
  } catch {}
  $script:Key = $new
  if (Test-Path $ModelsCache) { Remove-Item -Force $ModelsCache -ErrorAction SilentlyContinue }
  # Also wipe ranking caches so a re-key under a different account refetches.
  Get-ChildItem -Path $ConfigDir -Filter 'rankings.v3.*.tsv' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
  Write-Host "  ✓ saved" -NoNewline -ForegroundColor Green
  Write-Host " to $KeyFile"
  Write-Host ""
  return $true
}

# --- key ---
$Key = $env:OPENROUTER_API_KEY
if (-not $Key -and (Test-Path $KeyFile)) { $Key = (Get-Content $KeyFile -Raw).Trim() }
if (-not $Key -and -not $SkipInteractiveSetup) { [void](Read-AndSaveApiKey) }

# --- short aliases (mirror bash launcher) ---
function Resolve-Model([string]$m) {
  switch ($m) {
    { $_ -in 'kimi','kimi-k2' }      { 'moonshotai/kimi-k2.6'; break }
    'kimi-thinking'                  { 'moonshotai/kimi-k2-thinking'; break }
    'sonnet'                         { 'anthropic/claude-sonnet-4.6'; break }
    'opus'                           { 'anthropic/claude-opus-4.7'; break }
    'haiku'                          { 'anthropic/claude-haiku-4.5'; break }
    { $_ -in 'deepseek','dsv4' }     { 'deepseek/deepseek-v4-pro'; break }
    'deepseek-flash'                 { 'deepseek/deepseek-v4-flash'; break }
    { $_ -in 'glm','glm5' }          { 'z-ai/glm-5.1'; break }
    'qwen'                           { 'qwen/qwen3.6-plus'; break }
    'qwen-coder'                     { 'qwen/qwen3-coder-plus'; break }
    'gemma'                          { 'google/gemma-4-31b-it'; break }
    'gemini'                         { 'google/gemini-2.5-pro'; break }
    'minimax'                        { 'minimax/minimax-m2.7'; break }
    'grok'                           { 'x-ai/grok-4.3'; break }
    'grok-code'                      { 'x-ai/grok-code-fast-1'; break }
    'gpt'                            { 'openai/gpt-5'; break }
    'hy3'                            { 'tencent/hy3-preview'; break }
    default                          { $m }
  }
}

function Get-CacheAgeHours([string]$f) {
  if (-not (Test-Path $f)) { return 999999 }
  return ((Get-Date) - (Get-Item $f).LastWriteTime).TotalHours
}

# Wrapper around Invoke-WebRequest that follows 308 manually (PS 5.1 doesn't).
function Invoke-WebRequestFollow308 {
  param([string]$Uri, [hashtable]$Headers = @{}, [int]$TimeoutSec = 20, [int]$MaxRedirects = 5)
  for ($i = 0; $i -lt $MaxRedirects; $i++) {
    try {
      return Invoke-WebRequest -Uri $Uri -Headers $Headers -TimeoutSec $TimeoutSec -UseBasicParsing -MaximumRedirection 5
    } catch {
      $resp = $_.Exception.Response
      if ($null -ne $resp -and [int]$resp.StatusCode -eq 308) {
        $loc = $resp.Headers['Location']
        if ($loc) {
          if ($loc -notmatch '^https?://') {
            $base = [Uri]$Uri
            $loc = (New-Object Uri($base, $loc)).AbsoluteUri
          }
          $Uri = $loc; continue
        }
      }
      throw
    }
  }
  throw "Too many redirects fetching $Uri"
}

function Get-Catalog {
  if (-not $Refresh -and (Get-CacheAgeHours $ModelsCache) -lt 6) {
    return (Get-Content $ModelsCache -Raw | ConvertFrom-Json).data
  }
  try {
    $raw = (Invoke-WebRequestFollow308 -Uri 'https://openrouter.ai/api/v1/models' `
              -Headers @{Authorization="Bearer $Key"} -TimeoutSec 15).Content
    $resp = $raw | ConvertFrom-Json
    Set-Content $ModelsCache -Value $raw
    return $resp.data
  } catch {
    if (Test-Path $ModelsCache) { return (Get-Content $ModelsCache -Raw | ConvertFrom-Json).data }
    throw
  }
}

function Find-BraceStart([string]$s, [int]$pos) {
  $d = 0
  for ($j = $pos; $j -ge 0; $j--) {
    $c = $s[$j]
    if ($c -eq '}') { $d++ }
    elseif ($c -eq '{') { if ($d -eq 0) { return $j }; $d-- }
  }
  return -1
}
function Find-BraceEnd([string]$s, [int]$start) {
  $d = 0
  for ($j = $start; $j -lt $s.Length; $j++) {
    $c = $s[$j]
    if ($c -eq '{') { $d++ }
    elseif ($c -eq '}') { $d--; if ($d -eq 0) { return $j + 1 } }
  }
  return -1
}

# Output TSV: id\tctx\tprice\tname\trank\ttokens\tdesc\tprice_out
function Get-RankedTsv([string]$view) {
  $cache = Join-Path $ConfigDir "rankings.v3.$view.tsv"
  if (-not $Refresh -and (Get-CacheAgeHours $cache) -lt 6) {
    $cached = Get-Content $cache
    if ($cached -and $cached.Count -gt 0) { return $cached }
  }
  $catalog = Get-Catalog
  $idSet    = @{}; foreach ($m in $catalog) { $idSet[$m.id] = $true }
  $nameToId = @{}; foreach ($m in $catalog) { if ($m.name) { $nameToId[$m.name] = $m.id } }
  $meta     = @{}; foreach ($m in $catalog) { $meta[$m.id] = $m }

  $tokens = @{}
  $permToName = @{}
  try {
    $html = (Invoke-WebRequestFollow308 -Uri "https://openrouter.ai/rankings/programming?view=$view" -TimeoutSec 20).Content
    $pushes = [regex]::Matches($html, 'self\.__next_f\.push\(\[1,"([\s\S]*?)"\]\)')
    $sb = New-Object System.Text.StringBuilder
    foreach ($p in $pushes) {
      try { [void]$sb.Append((ConvertFrom-Json ('"' + $p.Groups[1].Value + '"'))) } catch {}
    }
    $allText = $sb.ToString()

    foreach ($m in [regex]::Matches($allText, '"request_count":\d+')) {
      $start = Find-BraceStart $allText $m.Index
      if ($start -lt 0) { continue }
      $end = Find-BraceEnd $allText $start
      if ($end -lt 0) { continue }
      try { $obj = $allText.Substring($start, $end - $start) | ConvertFrom-Json } catch { continue }
      if ($obj.slug -and $obj.name) { $permToName[$obj.slug] = $obj.name }
    }

    $tokRe  = [regex]'"model_permaslug":"([^"]+)"[\s\S]{0,400}?"total_completion_tokens":(\d+)[\s\S]{0,400}?"total_prompt_tokens":(\d+)'
    foreach ($m in $tokRe.Matches($allText)) {
      $perm = $m.Groups[1].Value
      $sum  = [int64]$m.Groups[2].Value + [int64]$m.Groups[3].Value
      if ($tokens.ContainsKey($perm)) { $tokens[$perm] += $sum } else { $tokens[$perm] = $sum }
    }
  } catch { } # scrape failed → fall through to curated fallback

  function Resolve-Canonical($perm) {
    if ($idSet[$perm]) { return $perm }
    if ($permToName[$perm] -and $nameToId[$permToName[$perm]]) { return $nameToId[$permToName[$perm]] }
    $stripped = $perm -replace '-\d{8}$|-\d{4}-\d{2}-\d{2}$|-\d{4}$|-0\d{3}$',''
    if ($idSet[$stripped]) { return $stripped }
    return $null
  }

  $ranked = $tokens.GetEnumerator() | Sort-Object { -[int64]$_.Value }
  $lines = New-Object System.Collections.Generic.List[string]
  $rank = 0
  $seen = @{}
  foreach ($e in $ranked) {
    $cid = Resolve-Canonical $e.Key
    if (-not $cid -or $seen[$cid]) { continue }
    $seen[$cid] = $true
    $rank++
    $mm = $meta[$cid]
    $ctx = if ($mm.context_length) { [int64]$mm.context_length } else { 0 }
    $pm = 0.0; $cm = 0.0
    try { if ($mm.pricing.prompt)     { $pm = [double]$mm.pricing.prompt     * 1e6 } } catch {}
    try { if ($mm.pricing.completion) { $cm = [double]$mm.pricing.completion * 1e6 } } catch {}
    $tokB = "{0:F1}B" -f ($e.Value / 1e9)
    $desc = ($mm.description -replace "[\r\n\t]"," ").Trim()
    if ($desc.Length -gt 160) {
      $cut = $desc.IndexOf(". ")
      if ($cut -gt 0 -and $cut -lt 180) { $desc = $desc.Substring(0, $cut + 1) }
      else { $desc = $desc.Substring(0, 160).TrimEnd() + "…" }
    }
    $lines.Add(("{0}`t{1}`t{2:F2}`t{3}`t{4}`t{5}`t{6}`t{7:F2}" -f $cid, $ctx, $pm, $mm.name, $rank, $tokB, $desc, $cm))
  }

  # OpenRouter moved rankings to client-side loading — supply a curated catalog.
  if ($tokens.Count -eq 0) {
    $curated = @(
      'anthropic/claude-sonnet-4.6','anthropic/claude-opus-4.7','anthropic/claude-haiku-4.5',
      'moonshotai/kimi-k2.6','moonshotai/kimi-k2-thinking',
      'deepseek/deepseek-v4-pro','deepseek/deepseek-v4-flash',
      'openai/gpt-5','google/gemini-2.5-pro','google/gemma-4-31b-it',
      'qwen/qwen3.6-plus','qwen/qwen3-coder-plus',
      'x-ai/grok-4.3','z-ai/glm-5.1','minimax/minimax-m2.7','meta-llama/llama-4-scout'
    )
    $cRank = 0
    foreach ($cid in $curated) {
      if (-not $meta.ContainsKey($cid)) { continue }
      $cRank++
      $mm = $meta[$cid]
      $ctx = if ($mm.context_length) { [int64]$mm.context_length } else { 0 }
      $pm = 0.0; $cm = 0.0
      try { if ($mm.pricing.prompt)     { $pm = [double]$mm.pricing.prompt     * 1e6 } } catch {}
      try { if ($mm.pricing.completion) { $cm = [double]$mm.pricing.completion * 1e6 } } catch {}
      $desc = ($mm.description -replace "[\r\n\t]"," ").Trim()
      if ($desc.Length -gt 160) {
        $cut = $desc.IndexOf(". ")
        if ($cut -gt 0 -and $cut -lt 180) { $desc = $desc.Substring(0, $cut + 1) }
        else { $desc = $desc.Substring(0, 160).TrimEnd() + "…" }
      }
      $lines.Add(("{0}`t{1}`t{2:F2}`t{3}`t{4}`t{5}`t{6}`t{7:F2}" -f $cid, $ctx, $pm, $mm.name, $cRank, "-", $desc, $cm))
    }
  }

  $lines | Set-Content $cache
  return $lines
}

# Catalog as TSV with the same 8-col schema as Get-RankedTsv (used by combined picker).
function Get-AllTsv {
  $catalog = Get-Catalog
  $lines = New-Object System.Collections.Generic.List[string]
  foreach ($m in ($catalog | Sort-Object id)) {
    $cid = $m.id
    $ctx = if ($m.context_length) { [int64]$m.context_length } else { 0 }
    $pm = 0.0; $cm = 0.0
    try { if ($m.pricing.prompt)     { $pm = [double]$m.pricing.prompt     * 1e6 } } catch {}
    try { if ($m.pricing.completion) { $cm = [double]$m.pricing.completion * 1e6 } } catch {}
    $desc = ($m.description -replace "[\r\n\t]"," ").Trim()
    if ($desc.Length -gt 160) {
      $cut = $desc.IndexOf(". ")
      if ($cut -gt 0 -and $cut -lt 180) { $desc = $desc.Substring(0, $cut + 1) }
      else { $desc = $desc.Substring(0, 160).TrimEnd() + "…" }
    }
    $lines.Add(("{0}`t{1}`t{2:F2}`t{3}`t-`t-`t{4}`t{5:F2}" -f $cid, $ctx, $pm, $m.name, $desc, $cm))
  }
  return $lines
}

# Combined: ranked top-N first, then every other catalog entry — for fuzzy search.
function Get-CombinedTsv([string]$view, [int]$topN) {
  $ranked = (Get-RankedTsv $view) | Select-Object -First $topN
  $all    = Get-AllTsv
  $seen = @{}
  foreach ($l in $ranked) { $seen[($l -split "`t")[0]] = $true }
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($l in $ranked) { $out.Add($l) }
  foreach ($l in $all)    { $cid = ($l -split "`t")[0]; if (-not $seen[$cid]) { $out.Add($l) } }
  return $out
}

function Format-Ctx([int64]$n) {
  if ($n -ge 1000000) { return ("{0:F1}M" -f ($n / 1MB)).Replace(".0M","M") }
  if ($n -ge 1000)    { return "{0}k" -f [int]($n / 1000) }
  return "$n"
}

function Show-Table([string[]]$rows) {
  $i = 0
  $objs = foreach ($l in $rows) {
    $i++
    $f = $l -split "`t"
    [pscustomobject]@{
      '#'           = $i
      ID            = $f[0]
      CTX           = (Format-Ctx ([int64]$f[1]))
      'PromptUSD/M' = ('${0}' -f $f[2])
      Tokens        = $f[5]
      Name          = $f[3]
    }
  }
  $objs | Format-Table -AutoSize | Out-Host
}

# Polished fzf picker — single-line rows with optional border label / step indicator.
# Matches the bash version's color scheme and chrome. Returns @{Key=...; Id=...}.
function Invoke-FzfPicker {
  param(
    [string[]]$Rows,
    [string]$TierLabel = 'model picker',
    [string]$StepLabel = ''
  )
  $fzfCmd = Get-Command fzf -ErrorAction SilentlyContinue
  if (-not $fzfCmd) { return $null }

  $borderText = if ($StepLabel) { " claudr · $StepLabel · $TierLabel " } else { " claudr · $TierLabel " }

  $C = [char]27 + '[36m'
  $D = [char]27 + '[2m'
  $W = [char]27 + '[97m'
  $R = [char]27 + '[0m'

  # Render each row as: id\trendered\tdescription  (tab-delimited, plain newline)
  $ms = New-Object IO.MemoryStream
  $sw = New-Object IO.StreamWriter($ms, (New-Object Text.UTF8Encoding($false)))
  foreach ($l in $Rows) {
    $f = $l -split "`t"
    while ($f.Count -lt 8) { $f += '' }
    $cid, $ctx, $price, $name, $rank, $tokens, $desc, $priceOut = $f[0..7]
    if (-not $priceOut) { $priceOut = '0.00' }
    $ctxs = Format-Ctx ([int64]$ctx)
    $rankStr = if ($rank -and $rank -ne '-') { "#$rank" } else { '' }
    $pricePair = "`$$price / `$$priceOut"

    $row = "$D$('{0,4}' -f $rankStr)$R  $C$('{0,-42}' -f $cid)$R  $D$('{0,5}' -f $ctxs) ctx$R   $W$('{0,17}' -f $pricePair)$R $D/M$R"
    $sw.Write("$cid`t$row`t$desc")
    $sw.Write("`n")
  }
  $sw.Flush()
  $bytes = $ms.ToArray()
  $sw.Dispose()

  $psi = New-Object Diagnostics.ProcessStartInfo
  $psi.FileName = $fzfCmd.Source
  $psi.UseShellExecute        = $false
  $psi.RedirectStandardInput  = $true
  $psi.RedirectStandardOutput = $true
  $argList = @(
    '--ansi',
    '--reverse',
    '--border=rounded',
    "--border-label=$borderText",
    '--border-label-pos=3',
    '--pointer=▶',
    '--marker= ',
    '--prompt= search › ',
    '--header=  ↑↓ navigate   Enter confirm   Ctrl+A change key   Esc cancel',
    '--header-first',
    '--info=inline-right',
    '--no-scrollbar',
    '--gutter= ',
    '--margin=1,2',
    '--padding=0,1',
    '--expect=ctrl-a',
    "--delimiter=`t",
    '--with-nth=2',
    '--color=border:cyan:dim,label:cyan:bold,header:dim,prompt:cyan:bold,pointer:cyan:bold,marker:cyan,bg+:236,fg+:bright-white:bold,hl+:bright-cyan:bold,hl:cyan,info:dim,separator:cyan:dim'
  )
  $psi.Arguments = ($argList | ForEach-Object {
    if ($_ -match '\s|"') { '"' + ($_ -replace '"','\"') + '"' } else { $_ }
  }) -join ' '

  $proc = [Diagnostics.Process]::Start($psi)
  try {
    $proc.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    $proc.StandardInput.Close()
    $picked = $proc.StandardOutput.ReadToEnd()
    $proc.WaitForExit()
  } catch {
    return @{ Key = $null; Id = $null }
  }
  if ([string]::IsNullOrWhiteSpace($picked)) { return @{ Key = $null; Id = $null } }
  $outLines = $picked -split "`r?`n"
  $key  = $outLines[0].Trim()
  $body = if ($outLines.Count -gt 1) { $outLines[1] } else { '' }
  $id   = ($body -split "`t")[0].Trim()
  return @{ Key = $key; Id = $id }
}

# --- tier config ---
function Get-PresetPath([string]$name) {
  if ([string]::IsNullOrWhiteSpace($name)) { return $TiersFile }
  return (Join-Path $PresetsDir "$name.conf")
}

function Load-Tiers([string]$name = '') {
  $file = Get-PresetPath $name
  if (-not (Test-Path $file)) { return $null }
  $vals = @{}
  foreach ($line in (Get-Content $file)) {
    if ($line -match '^\s*(OPUS|SONNET|HAIKU)\s*=\s*(.+?)\s*$') {
      $vals[$matches[1]] = $matches[2]
    }
  }
  if (-not ($vals.ContainsKey('OPUS') -and $vals.ContainsKey('SONNET') -and $vals.ContainsKey('HAIKU'))) { return $null }
  return $vals
}

function Save-Tiers([string]$name, [string]$opus, [string]$sonnet, [string]$haiku) {
  $file = Get-PresetPath $name
  $dir = Split-Path $file -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  $reRunHint = if ($name) { "claudr -Tiers -Preset $name" } else { "claudr -Tiers" }
  $content = @"
# claudr tier config - what each Claude Code model alias resolves to.
# OPUS    = main session model + the 'opus' alias for subagents
# SONNET  = the 'sonnet' alias for subagents / mid-tier work
# HAIKU   = the 'haiku' alias for subagents / background / fast tasks
# Edit by hand, or re-run: $reRunHint
OPUS=$opus
SONNET=$sonnet
HAIKU=$haiku
"@
  Set-Content -Path $file -Value $content -Encoding ascii
}

function List-Presets {
  if (-not (Test-Path $PresetsDir)) { return @() }
  return @(Get-ChildItem -Path $PresetsDir -Filter '*.conf' -File -ErrorAction SilentlyContinue |
           ForEach-Object { $_.BaseName } | Sort-Object)
}

function Print-PresetSummary([string]$name) {
  $label = if ($name) { $name } else { '(default)' }
  $vals = Load-Tiers $name
  Write-Host "    $label" -ForegroundColor Green
  if ($vals) {
    Write-Host ("      opus    {0}" -f $vals['OPUS'])   -ForegroundColor Gray
    Write-Host ("      sonnet  {0}" -f $vals['SONNET']) -ForegroundColor Gray
    Write-Host ("      haiku   {0}" -f $vals['HAIKU'])  -ForegroundColor Gray
  } else {
    Write-Host "      (could not parse)" -ForegroundColor DarkGray
  }
}

# Interactive 3-pick wizard. Sets script:OpusModel / SonnetModel / HaikuModel.
# Returns $true on success, $false on cancel.
function Run-TierWizard {
  if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
    Write-Error "claudr: tier wizard requires fzf (install: winget install junegunn.fzf)"
    return $false
  }
  $rows = Get-CombinedTsv $View $Top
  if (-not $rows -or $rows.Count -eq 0) {
    Write-Error "claudr: no models available."
    return $false
  }
  $tiers = @('OPUS (main)','SONNET','HAIKU')
  $picks = @()
  for ($i = 0; $i -lt 3; $i++) {
    while ($true) {
      $pick = Invoke-FzfPicker -Rows $rows -TierLabel $tiers[$i] -StepLabel ("{0}/3" -f ($i + 1))
      if ($pick.Key -eq 'ctrl-a') {
        if (Read-AndSaveApiKey -Rotate) { $rows = Get-CombinedTsv $View $Top }
        continue
      }
      if (-not $pick.Id) { return $false }
      $picks += $pick.Id
      break
    }
  }
  $script:OpusModel   = $picks[0]
  $script:SonnetModel = $picks[1]
  $script:HaikuModel  = $picks[2]
  return $true
}

# --- early-exit modes ---

if ($Presets) {
  Write-Host ""
  Write-Host "  claudr presets" -ForegroundColor Cyan
  Write-Host "  ──────────────────────────────────────────────────" -ForegroundColor DarkGray
  $found = $false
  if (Test-Path $TiersFile) { Print-PresetSummary ''; $found = $true }
  foreach ($name in (List-Presets)) { Print-PresetSummary $name; $found = $true }
  if (-not $found) {
    Write-Host "    no presets saved - run: claudr -Tiers -Preset <name>" -ForegroundColor DarkGray
  }
  Write-Host ""
  Write-Host "  launch with: claudr -Preset <name>" -ForegroundColor DarkGray
  Write-Host ""
  exit 0
}

if ($Tiers) {
  if (-not [Environment]::UserInteractive) {
    Write-Error "claudr -Tiers requires an interactive terminal."; exit 1
  }
  if (Run-TierWizard) {
    Save-Tiers $Preset $OpusModel $SonnetModel $HaikuModel
    $savedTo = Get-PresetPath $Preset
    Write-Host ""
    if ($Preset) {
      Write-Host "  ✓ preset '$Preset' saved to $savedTo" -ForegroundColor Green
      Write-Host "    launch with: claudr -Preset $Preset" -ForegroundColor DarkGray
    } else {
      Write-Host "  ✓ tier config saved to $savedTo" -ForegroundColor Green
    }
    Write-Host ("    opus    {0}" -f $OpusModel)   -ForegroundColor DarkGray
    Write-Host ("    sonnet  {0}" -f $SonnetModel) -ForegroundColor DarkGray
    Write-Host ("    haiku   {0}" -f $HaikuModel)  -ForegroundColor DarkGray
    Write-Host ""
    exit 0
  } else {
    Write-Error "claudr: cancelled - no changes saved."; exit 1
  }
}

if ($Doctor) {
  $fails = 0; $warns = 0
  function Doctor-Row([string]$status, [string]$label, [string]$detail) {
    Write-Host ("    {0} {1,-18} " -f $status, $label) -NoNewline
    Write-Host $detail -ForegroundColor DarkGray
  }
  $PASS = '[OK]'; $WARN = '[!]'; $FAIL = '[X]'
  Write-Host ""
  Write-Host "  claudr · doctor" -ForegroundColor Cyan
  Write-Host "  ──────────────────────────────────────────────────" -ForegroundColor DarkGray

  if (Get-Command claude -ErrorAction SilentlyContinue) {
    $cv = (& claude --version 2>$null | Select-Object -First 1)
    Doctor-Row $PASS 'claude CLI' $cv
  } else {
    Doctor-Row $FAIL 'claude CLI' 'not in PATH - npm i -g @anthropic-ai/claude-code'; $fails++
  }

  if (Get-Command fzf -ErrorAction SilentlyContinue) {
    $fv = (& fzf --version 2>$null) -split ' ' | Select-Object -First 1
    Doctor-Row $PASS 'fzf' $fv
  } else {
    Doctor-Row $FAIL 'fzf' 'missing - winget install junegunn.fzf'; $fails++
  }

  if ([string]::IsNullOrWhiteSpace($Key)) {
    Doctor-Row $FAIL 'OpenRouter key' 'not configured'; $fails++
  } else {
    $src = if ($env:OPENROUTER_API_KEY) { 'env' } else { $KeyFile }
    try {
      $resp = Invoke-WebRequestFollow308 -Uri 'https://openrouter.ai/api/v1/auth/key' `
                -Headers @{Authorization="Bearer $Key"} -TimeoutSec 8
      Doctor-Row $PASS 'OpenRouter key' "valid (from $src)"
    } catch {
      $code = 0
      try { $code = [int]$_.Exception.Response.StatusCode } catch {}
      if ($code -eq 401 -or $code -eq 403) {
        Doctor-Row $FAIL 'OpenRouter key' "rejected (HTTP $code)"; $fails++
      } else {
        Doctor-Row $WARN 'OpenRouter key' "could not verify"; $warns++
      }
    }
  }

  if ($env:TAVILY_API_KEY -or (Test-Path $TavilyKeyFile)) {
    Doctor-Row $PASS 'Tavily key' 'configured (web search enabled)'
  } else {
    Doctor-Row $WARN 'Tavily key' 'not set - web search disabled'; $warns++
  }

  $defaultTiers = Load-Tiers ''
  if ($defaultTiers) {
    Doctor-Row $PASS 'default tiers' ("opus={0} sonnet={1} haiku={2}" -f $defaultTiers['OPUS'], $defaultTiers['SONNET'], $defaultTiers['HAIKU'])
  } else {
    Doctor-Row $WARN 'default tiers' 'none - first launch will run setup wizard'; $warns++
  }

  if ((Test-Path $ModelsCache) -and $defaultTiers) {
    try {
      $catalog = (Get-Content $ModelsCache -Raw | ConvertFrom-Json).data
      $ids = @{}; foreach ($m in $catalog) { $ids[$m.id] = $true }
      $missing = @()
      foreach ($k in @('OPUS','SONNET','HAIKU')) {
        if (-not $ids[$defaultTiers[$k]]) { $missing += $defaultTiers[$k] }
      }
      if ($missing.Count -eq 0) {
        Doctor-Row $PASS 'tier slugs' 'all resolve in OpenRouter catalog'
      } else {
        Doctor-Row $WARN 'tier slugs' ("unknown: {0}" -f ($missing -join ' ')); $warns++
      }
    } catch {}
  }

  $presetList = List-Presets
  if ($presetList.Count -gt 0) {
    Doctor-Row $PASS 'presets' ("{0} saved ({1})" -f $presetList.Count, ($presetList -join ' '))
  } else {
    Doctor-Row $WARN 'presets' 'none - create with: claudr -Tiers -Preset <name>'
  }

  if (Test-Path $ModelsCache) {
    $age = [int](Get-CacheAgeHours $ModelsCache)
    if ($age -lt 6) { Doctor-Row $PASS 'models cache' "${age}h old (fresh)" }
    else { Doctor-Row $WARN 'models cache' "${age}h old (stale - run: claudr -Refresh)"; $warns++ }
  } else {
    Doctor-Row $WARN 'models cache' 'not yet fetched'
  }

  Write-Host ""
  if ($fails -gt 0) {
    Write-Host ("  {0} failed, {1} warnings" -f $fails, $warns) -ForegroundColor Red
    Write-Host ""; exit 1
  } elseif ($warns -gt 0) {
    Write-Host ("  all critical checks passed, {0} warnings" -f $warns) -ForegroundColor Yellow
  } else {
    Write-Host "  all checks passed" -ForegroundColor Green
  }
  Write-Host ""
  exit 0
}

if ($List) {
  $rows = (Get-RankedTsv $View) | Select-Object -First $Top
  Show-Table $rows
  Write-Host "(programming leaderboard, view=$View, top=$Top)" -ForegroundColor DarkGray
  exit 0
}
if ($ListAll) {
  $i = 0
  Get-Catalog | Sort-Object id | ForEach-Object {
    $i++
    $pm = 0.0
    try { if ($_.pricing.prompt) { $pm = [double]$_.pricing.prompt * 1e6 } } catch {}
    [pscustomobject]@{
      '#'           = $i
      ID            = $_.id
      CTX           = $_.context_length
      'PromptUSD/M' = ('${0:F2}' -f $pm)
      Name          = $_.name
    }
  } | Format-Table -AutoSize | Out-Host
  exit 0
}

# --- tier resolution ---
$OpusModel = ''; $SonnetModel = ''; $HaikuModel = ''
$ActivePreset = ''
if ($Preset) {
  $vals = Load-Tiers $Preset
  if (-not $vals) {
    Write-Error "claudr: preset '$Preset' not found at $(Get-PresetPath $Preset)`n  list presets: claudr -Presets`n  create one:   claudr -Tiers -Preset $Preset"
    exit 1
  }
  $OpusModel = $vals['OPUS']; $SonnetModel = $vals['SONNET']; $HaikuModel = $vals['HAIKU']
  $ActivePreset = $Preset
} else {
  $vals = Load-Tiers ''
  if ($vals) {
    $OpusModel = $vals['OPUS']; $SonnetModel = $vals['SONNET']; $HaikuModel = $vals['HAIKU']
  }
}

# Per-launch env overrides
if ($env:CLAUDR_OPUS_MODEL)   { $OpusModel   = $env:CLAUDR_OPUS_MODEL }
if ($env:CLAUDR_SONNET_MODEL) { $SonnetModel = $env:CLAUDR_SONNET_MODEL }
if ($env:CLAUDR_HAIKU_MODEL)  { $HaikuModel  = $env:CLAUDR_HAIKU_MODEL }

# Fill any missing tier from -Model fanout or run the wizard
if (-not $OpusModel -or -not $SonnetModel -or -not $HaikuModel) {
  if ($Model) {
    $fanout = Resolve-Model $Model
    if (-not $OpusModel)   { $OpusModel   = $fanout }
    if (-not $SonnetModel) { $SonnetModel = $fanout }
    if (-not $HaikuModel)  { $HaikuModel  = $fanout }
  } elseif ([Environment]::UserInteractive) {
    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
      Write-Error "claudr: 'fzf' is required for the tier picker. Install: winget install junegunn.fzf"; exit 1
    }
    Write-Host ""
    Write-Host "  claudr · first-run tier setup" -ForegroundColor Cyan
    Write-Host "  Pick three OpenRouter models. Opus becomes your main; Sonnet and Haiku" -ForegroundColor DarkGray
    Write-Host "  fill in when Claude Code dispatches subagents at those tiers." -ForegroundColor DarkGray
    Write-Host ""
    if (Run-TierWizard) { Save-Tiers '' $OpusModel $SonnetModel $HaikuModel }
    else { Write-Error "claudr: setup cancelled."; exit 1 }
  } else {
    $fallback = 'moonshotai/kimi-k2.6'
    if (-not $OpusModel)   { $OpusModel   = $fallback }
    if (-not $SonnetModel) { $SonnetModel = $fallback }
    if (-not $HaikuModel)  { $HaikuModel  = $fallback }
  }
}

$OpusModel   = Resolve-Model $OpusModel
$SonnetModel = Resolve-Model $SonnetModel
$HaikuModel  = Resolve-Model $HaikuModel

# -Model overrides the main model only; tier mapping is untouched. Default to opus.
if ($Model) { $Model = Resolve-Model $Model } else { $Model = $OpusModel }

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
  Write-Error "claudr: 'claude' CLI not found. Install: npm i -g @anthropic-ai/claude-code"
  exit 1
}

# --- env exports ---
$env:ANTHROPIC_BASE_URL            = 'https://openrouter.ai/api'
$env:ANTHROPIC_AUTH_TOKEN          = $Key
$env:ANTHROPIC_API_KEY             = ''
$env:ANTHROPIC_MODEL               = $Model
$env:ANTHROPIC_DEFAULT_OPUS_MODEL   = $OpusModel
$env:ANTHROPIC_DEFAULT_SONNET_MODEL = $SonnetModel
$env:ANTHROPIC_DEFAULT_HAIKU_MODEL  = $HaikuModel
if (-not $env:ANTHROPIC_SMALL_FAST_MODEL) { $env:ANTHROPIC_SMALL_FAST_MODEL = $HaikuModel }

# OpenRouter attribution: groups claudr usage in the activity dashboard.
$ClaudrReferer = if ($env:CLAUDR_REFERER) { $env:CLAUDR_REFERER } else { 'https://github.com/olindkri/claudr' }
$ClaudrTitle   = if ($env:CLAUDR_TITLE)   { $env:CLAUDR_TITLE }   else { 'claudr' }
$env:ANTHROPIC_CUSTOM_HEADERS = "HTTP-Referer: $ClaudrReferer`nX-Title: $ClaudrTitle"

# Context window resolution from caches
$ModelCtx = 200000
$foundCtx = 0
if (Test-Path $RankCache) {
  $row = (Get-Content $RankCache | Where-Object { $_ -match "^$([regex]::Escape($Model))`t" } | Select-Object -First 1)
  if ($row) { $foundCtx = [int]($row -split "`t")[1] }
}
if ($foundCtx -le 0 -and (Test-Path $ModelsCache)) {
  try {
    $catalog = (Get-Content $ModelsCache -Raw | ConvertFrom-Json).data
    $entry = $catalog | Where-Object { $_.id -eq $Model } | Select-Object -First 1
    if ($entry -and $entry.context_length) { $foundCtx = [int]$entry.context_length }
  } catch { }
}
if ($foundCtx -gt 0) { $ModelCtx = $foundCtx }

if ($env:CLAUDR_AUTOCOMPACT -eq '1') {
  if (-not $env:CLAUDE_AUTOCOMPACT_PCT_OVERRIDE) { $env:CLAUDE_AUTOCOMPACT_PCT_OVERRIDE = '75' }
  $CompactState = "on @ $($env:CLAUDE_AUTOCOMPACT_PCT_OVERRIDE)% (200K cap)"
} else {
  if (-not $env:DISABLE_COMPACT) { $env:DISABLE_COMPACT = '1' }
  if (-not $env:CLAUDE_CODE_MAX_CONTEXT_TOKENS) { $env:CLAUDE_CODE_MAX_CONTEXT_TOKENS = "$ModelCtx" }
  $CompactState = 'off - run /compact manually'
}

# Disable Anthropic's server-side WebSearch tool (no-op on OpenRouter).
$DisallowArgs = @()
if ($env:CLAUDR_ALLOW_WEBSEARCH -ne '1') { $DisallowArgs = @('--disallowedTools','WebSearch') }

# Inject Tavily MCP for this launch only.
$McpArgs = @()
if (Test-Path $McpConfigFile) { $McpArgs = @('--mcp-config', $McpConfigFile) }

# --- print-mode detection in $Rest (mirror bash auto-route) ---
$PrintMode = $false; $HasOutputFormat = $false; $PrintPrompt = ''
$Filtered = @(); $prev = $null
foreach ($a in @($Rest)) {
  if ($a -in @('-p','--print')) { $PrintMode = $true; $prev = $a; continue }
  if ($a -eq '--output-format') { $HasOutputFormat = $true; $prev = $null; $Filtered += $a; continue }
  if ($prev -in @('-p','--print')) { $PrintPrompt = $a; $prev = $null; continue }
  $Filtered += $a; $prev = $null
}
$AskMode = $false; $AskPrompt = ''
if ($Ask) { $AskMode = $true; $AskPrompt = $Ask }
if ($PrintMode -and -not $HasOutputFormat -and -not $AskMode -and $PrintPrompt -and $env:CLAUDR_RAW_PRINT -ne '1') {
  $AskMode = $true
  $AskPrompt = $PrintPrompt
  $Rest = $Filtered
}

# MAX_THINKING_TOKENS=0 stops Claude Code requesting extended thinking, which
# avoids the trailing redacted_thinking blocks that break `claude -p` result
# extraction on OpenRouter (claude-code#38805). Interactive sessions keep it.
if (($PrintMode -or $AskMode) -and $env:CLAUDR_THINKING -ne '1') {
  if (-not $env:MAX_THINKING_TOKENS) { $env:MAX_THINKING_TOKENS = '0' }
}

# Banner: suppress in print/ask mode and when stderr isn't a TTY-ish console.
$ShowBanner = $true
if ($env:CLAUDR_BANNER -ne '1') {
  if ($PrintMode -or $AskMode -or -not [Environment]::UserInteractive) { $ShowBanner = $false }
}

# --- statusline ---
$SettingsArgs = @()
if ($env:CLAUDR_STATUSLINE -ne '0') {
  if (-not (Test-Path $StatuslineFile) -or -not (Test-Path $SettingsFile)) {
    $statuslineContent = @'
# claudr statusline (Windows) - invoked by Claude Code, receives session JSON on stdin.
$inp = [Console]::In.ReadToEnd()
$model = if ($env:ANTHROPIC_MODEL) { $env:ANTHROPIC_MODEL } else { '?' }
$ctx   = if ($env:CLAUDR_CTX_HUMAN) { $env:CLAUDR_CTX_HUMAN } else { '?' }
$preset = $env:CLAUDR_ACTIVE_PRESET
$cwd = ''
if ($inp -match '"current_working_directory"\s*:\s*"([^"]+)"') { $cwd = $matches[1] }
if (-not $cwd) { $cwd = (Get-Location).Path }
$short = Split-Path $cwd -Leaf
if ($preset) { Write-Host "claudr | $model | ctx $ctx | [$preset] | $short" -NoNewline }
else         { Write-Host "claudr | $model | ctx $ctx | $short"           -NoNewline }
'@
    Set-Content -Path $StatuslineFile -Value $statuslineContent -Encoding ascii
    $statuslineCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$StatuslineFile`""
    $settingsJson = @{
      statusLine = @{
        type    = 'command'
        command = $statuslineCmd
        padding = 0
      }
    } | ConvertTo-Json -Compress -Depth 5
    Set-Content -Path $SettingsFile -Value $settingsJson -Encoding ascii
  }
  $SettingsArgs = @('--settings', $SettingsFile)
  $env:CLAUDR_CTX_HUMAN = Format-Ctx ([int64]$ModelCtx)
  $env:CLAUDR_ACTIVE_PRESET = $ActivePreset
}

# --- banner ---
if ($ShowBanner) {
  $mainNote = if ($Model -eq $OpusModel) { ' = opus' } else { '' }
  $perms    = if ($env:CLAUDR_SAFE -eq '1') { 'prompted' } else { 'bypassed  (CLAUDR_SAFE=1 to enable)' }
  $search   = if ($DisallowArgs.Count -gt 0) { 'Tavily MCP  (WebSearch disabled)' } elseif (Test-Path $McpConfigFile) { 'Tavily MCP + WebSearch' } else { 'none' }
  Write-Host ""
  Write-Host "  claudr" -NoNewline -ForegroundColor Cyan
  Write-Host "  - OpenRouter routing for Claude Code" -ForegroundColor DarkGray
  Write-Host "  ──────────────────────────────────────────────────" -ForegroundColor DarkGray
  Write-Host "    endpoint   https://openrouter.ai/api" -ForegroundColor Gray
  Write-Host ""
  Write-Host "    main       " -NoNewline; Write-Host $Model -NoNewline -ForegroundColor White
  if ($mainNote) { Write-Host $mainNote -ForegroundColor DarkGray } else { Write-Host '' }
  Write-Host "    sonnet     $SonnetModel" -ForegroundColor Gray
  Write-Host "    haiku      $HaikuModel" -ForegroundColor Gray
  Write-Host ""
  Write-Host "    context    $($env:CLAUDR_CTX_HUMAN) tokens  ($ModelCtx)" -ForegroundColor Gray
  Write-Host "    compact    $CompactState" -ForegroundColor Gray
  Write-Host "    search     $search" -ForegroundColor Gray
  Write-Host "    perms      $perms" -ForegroundColor Gray
  Write-Host ""
  if ($ActivePreset) {
    Write-Host "    preset " -NoNewline -ForegroundColor DarkGray
    Write-Host $ActivePreset -NoNewline -ForegroundColor Cyan
    Write-Host " - claudr -Tiers to reconfigure" -ForegroundColor DarkGray
  } else {
    Write-Host "    claudr -Tiers to reconfigure - CLAUDR_AUTOCOMPACT=1, CLAUDR_SAFE=1, CLAUDR_ALLOW_WEBSEARCH=1" -ForegroundColor DarkGray
  }
  Write-Host ""
}

# Pass --dangerously-skip-permissions by default. Opt out with $env:CLAUDR_SAFE = '1'.
$SkipPermArg = @()
if ($env:CLAUDR_SAFE -ne '1') { $SkipPermArg = @('--dangerously-skip-permissions') }

# --- ask mode (auto-routed -p or explicit -Ask) ---
# Streams claude in --output-format stream-json, extracts text blocks, emits the
# concatenated reply on stdout. Works around claude-code#38805.
if ($AskMode) {
  if ([string]::IsNullOrWhiteSpace($AskPrompt)) {
    Write-Error "claudr -Ask requires a prompt: claudr -Ask `"your prompt`""
    exit 1
  }
  $askArgs = @() + $SkipPermArg + $DisallowArgs + $McpArgs + $SettingsArgs + $Rest +
             @('-p', $AskPrompt, '--output-format', 'stream-json', '--verbose')
  $sb = New-Object System.Text.StringBuilder
  $exit = 0
  & claude @askArgs 2>$null | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($_)) { return }
    try { $obj = $_ | ConvertFrom-Json } catch { return }
    if ($obj.type -eq 'assistant') {
      foreach ($b in $obj.message.content) {
        if ($b.type -eq 'text') { [void]$sb.Append($b.text) }
      }
    } elseif ($obj.type -eq 'result' -and $obj.is_error) {
      [Console]::Error.WriteLine("claudr -Ask: " + ($(if ($obj.result) { $obj.result } else { 'error' })))
      $exit = 1
    }
  }
  Write-Output $sb.ToString()
  exit $exit
}

# --- normal launch ---
$launchArgs = @() + $SkipPermArg + $DisallowArgs + $McpArgs + $SettingsArgs + $Rest
& claude @launchArgs
exit $LASTEXITCODE
