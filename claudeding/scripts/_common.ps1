# _common.ps1  (ClaudeDing) — 공용 함수 모듈
# notify-complete.ps1 / remind-loop.ps1 에서 dot-source 한다.
# 외부 모듈 없이 Windows 내장 API 만 사용한다.

$ErrorActionPreference = 'Stop'

$ClaudeDir  = Join-Path $env:USERPROFILE '.claude'
$StateDir   = Join-Path $ClaudeDir 'claudeding'
$ConfigPath = Join-Path $ClaudeDir 'claudeding.config.json'
$LogPath    = Join-Path $ClaudeDir 'notify-complete.log'
$PerfPath   = Join-Path $ClaudeDir 'notify-perf.log'

function Initialize-State {
    if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }
}

function Write-Log($msg) {
    try { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg" | Out-File -FilePath $LogPath -Append -Encoding utf8 } catch {}
}

function Write-Perf($event, $startupMs, $winrtMs, $parseMs, $totalMs, $toasts) {
    try {
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  [$event] startup=${startupMs}ms winrt=${winrtMs}ms parse=${parseMs}ms total=${totalMs}ms toasts_enabled=$toasts" |
            Out-File -FilePath $PerfPath -Append -Encoding utf8
    } catch {}
}

# ── 설정 ────────────────────────────────────────────────────────────────
# "30s" / "1m" / "2h" / "90"(단위 없으면 분) → 밀리초. "off"/"0" → 0(비활성)
function ConvertTo-Ms([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return 60000 }
    $s = $s.Trim().ToLower()
    if ($s -in @('off', 'none', 'false', 'disabled', '0')) { return 0 }
    if ($s -match '^(\d+)\s*(ms|s|m|h)?$') {
        $n = [int]$Matches[1]; $u = $Matches[2]
        switch ($u) {
            'ms' { return $n }
            's'  { return $n * 1000 }
            'h'  { return $n * 3600000 }
            'm'  { return $n * 60000 }
            default { return $n * 60000 }   # 단위 없으면 분
        }
    }
    return 60000
}

function Get-Config {
    $interval = '1m'; $max = 10
    try {
        if (Test-Path $ConfigPath) {
            $c = Get-Content -LiteralPath $ConfigPath -Raw -Encoding utf8 | ConvertFrom-Json
            if ($c.remindInterval) { $interval = [string]$c.remindInterval }
            if ($null -ne $c.remindMax) { $max = [int]$c.remindMax }
        }
    } catch {}
    $ms = ConvertTo-Ms $interval
    if ($ms -gt 0 -and $ms -lt 5000) { $ms = 5000 }   # 최소 5초(스팸 방지)
    [pscustomobject]@{ IntervalMs = $ms; Max = $max; Raw = $interval }
}

# ── 세션 / 리마인드 잠금 ─────────────────────────────────────────────────
function Get-SessionKey($hook) {
    $id = if ($hook.session_id) { [string]$hook.session_id } else { [string]$hook.cwd }
    if ([string]::IsNullOrWhiteSpace($id)) { $id = 'default' }
    ($id -replace '[^A-Za-z0-9_\-]', '_')
}

function Get-LockPath($key) { Join-Path $StateDir "remind-$key.json" }

function Set-ReminderLock($key, $obj) {
    try { $obj | ConvertTo-Json -Compress | Out-File -FilePath (Get-LockPath $key) -Encoding utf8 -Force } catch {}
}

function Get-ReminderLock($key) {
    $p = Get-LockPath $key
    if (-not (Test-Path $p)) { return $null }
    try { return (Get-Content -LiteralPath $p -Raw -Encoding utf8 | ConvertFrom-Json) } catch { return $null }
}

# 잠금 파일만 삭제(리마인드 루프 자신이 종료할 때 사용 — 자기 자신을 kill 하지 않음)
function Remove-LockFile($key) {
    $p = Get-LockPath $key
    try { if (Test-Path $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue } } catch {}
}

# 리마인드 취소: 살아있는 루프 프로세스를 종료하고 잠금 삭제(훅에서 사용)
function Remove-ReminderLock($key) {
    try {
        $lock = Get-ReminderLock $key
        if ($lock -and $lock.reminderPid) {
            try { Stop-Process -Id ([int]$lock.reminderPid) -Force -ErrorAction Stop } catch {}
        }
    } catch {}
    Remove-LockFile $key
}

# 캐시에 저장된 창 정보만 빠르게 읽는다(WMI 호출 없음). 토스트 표시 전 경로에서 사용.
function Get-CachedWindow($sessionKey) {
    $cachePath = Join-Path $StateDir "win-$sessionKey.json"
    if (Test-Path $cachePath) {
        try {
            $c = Get-Content -LiteralPath $cachePath -Raw -Encoding utf8 | ConvertFrom-Json
            if ($c.pid -gt 0) {
                try { $null = Get-Process -Id ([int]$c.pid) -ErrorAction Stop; return $c } catch {}
            }
        } catch {}
    }
    return $null
}

# ── 클릭 시 복귀할 터미널 창 찾기(세션당 1회 계산 후 캐싱) ────────────────
# WMI 열거가 들어가므로(~300ms) 토스트를 띄운 뒤에 호출해 체감 지연을 막는다.
function Get-TerminalWindow($sessionKey) {
    $cached = Get-CachedWindow $sessionKey
    if ($cached) { return $cached }
    $cachePath = Join-Path $StateDir "win-$sessionKey.json"
    # 훅 프로세스의 조상을 따라 올라가며 '보이는 최상위 창'을 가진 첫 프로세스(=터미널)를 찾는다.
    # 부모 관계는 WMI 를 한 번만 열거해 메모리에서 조회한다(조상마다 쿼리하면 매우 느림).
    $found = $null
    try {
        $parent = @{}
        foreach ($p in Get-CimInstance Win32_Process -ErrorAction SilentlyContinue) {
            $parent[[int]$p.ProcessId] = [int]$p.ParentProcessId
        }
        $cur = $PID
        for ($i = 0; $i -lt 12 -and $cur -gt 0; $i++) {
            try {
                $proc = Get-Process -Id $cur -ErrorAction Stop
                if ($proc.MainWindowHandle -ne 0) {
                    $found = [pscustomobject]@{ pid = $cur; hwnd = [int64]$proc.MainWindowHandle }
                    break
                }
            } catch {}
            if (-not $parent.ContainsKey($cur)) { break }
            $cur = $parent[$cur]
        }
    } catch {}
    if ($found) { try { $found | ConvertTo-Json -Compress | Out-File -LiteralPath $cachePath -Encoding utf8 -Force } catch {} }
    return $found
}

# ── 토스트 표시 ──────────────────────────────────────────────────────────
$script:LastWinrtMs = 0
$script:LastShowAt  = $null

function Register-FocusProtocol {
    # 토스트 클릭 → claudeding://focus?... → (창 없는)wscript → focus.ps1 로 연결(멱등).
    # powershell 을 직접 핸들러로 쓰면 콘솔이 깜빡이므로 wscript 런처를 거친다.
    try {
        $vbs = Join-Path $PSScriptRoot 'focus.vbs'
        $cmd = "wscript.exe `"$vbs`" `"%1`""
        $base = 'HKCU:\Software\Classes\claudeding'
        if (-not (Test-Path $base)) { New-Item -Path $base -Force | Out-Null }
        Set-Item -Path $base -Value 'URL:ClaudeDing Protocol'
        New-ItemProperty -Path $base -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null
        $cmdKey = Join-Path $base 'shell\open\command'
        if (-not (Test-Path $cmdKey)) { New-Item -Path $cmdKey -Force | Out-Null }
        Set-Item -Path $cmdKey -Value $cmd
    } catch { Write-Log "프로토콜 등록 실패: $($_.Exception.Message)" }
}

function Show-Toast {
    param(
        [string]$Title,
        [string]$Body,
        [int]$LaunchPid = 0,
        [long]$LaunchHwnd = 0,
        [string]$Tag = ''
    )

    $w = [Diagnostics.Stopwatch]::StartNew()
    [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    [void][Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType = WindowsRuntime]
    [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
    $w.Stop(); $script:LastWinrtMs = $w.ElapsedMilliseconds

    # 알림이 "ClaudeDing" 이름으로 뜨도록 전용 AppUserModelID 를 등록한다(없으면 생성).
    $appId = 'ClaudeDing'
    $key = "HKCU:\Software\Classes\AppUserModelId\$appId"
    if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
    New-ItemProperty -Path $key -Name 'DisplayName' -Value 'ClaudeDing' -PropertyType String -Force | Out-Null
    Register-FocusProtocol

    # 클릭 시 해당 창으로 복귀시키기 위한 프로토콜 링크(XML 속성이므로 & 는 &amp;).
    $launch = ''
    if ($LaunchPid -gt 0 -or $LaunchHwnd -gt 0) {
        $launch = "claudeding://focus?pid=$LaunchPid&amp;hwnd=$LaunchHwnd"
    }

    $tEsc = [System.Security.SecurityElement]::Escape($Title)
    $bEsc = [System.Security.SecurityElement]::Escape($Body)

    $xmlText = @"
<toast activationType="protocol" launch="$launch">
  <visual>
    <binding template="ToastGeneric">
      <text>$tEsc</text>
      <text>$bEsc</text>
    </binding>
  </visual>
  <audio src="ms-winsoundevent:Notification.Default"/>
</toast>
"@

    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml($xmlText)
    $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
    # 같은 세션의 리마인드는 이전 토스트를 교체(쌓이지 않게)하도록 Tag/Group 지정.
    if ($Tag) {
        try { $toast.Tag = ($Tag.Substring(0, [Math]::Min(16, $Tag.Length))); $toast.Group = 'ClaudeDing' } catch {}
    }
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
    $script:LastShowAt = Get-Date   # 사용자 체감 지연 끝(아래 Sleep 제외)

    # 토스트 전달은 비동기다. 바로 프로세스가 죽으면 전달 전에 사라질 수 있어 잠깐 대기.
    Start-Sleep -Milliseconds 1200
}

# ── 문구 정리 ────────────────────────────────────────────────────────────
# 마크다운/여러 줄 → 한 줄 + 길이 제한 (그 외 메시지의 폴백)
function Format-Body($text) {
    $t = $text -replace '`{1,3}', '' -replace '(?m)^\s*#{1,6}\s*', '' -replace '\*\*', ''
    $t = ($t -split "`n" | Where-Object { $_.Trim() -ne '' }) -join ' / '
    if ($t.Length -gt 250) { $t = $t.Substring(0, 250) + '…' }
    return $t
}

# Notification 메시지(영어)를 상황별 자연스러운 한국어로 변환.
function Format-Notice($msg) {
    $m = ([string]$msg).Trim()
    if ([string]::IsNullOrWhiteSpace($m)) { return '입력 또는 선택을 기다리고 있어요.' }
    if ($m -match '(?i)permission to use (.+)$') {
        $tool = ($Matches[1].Trim().TrimEnd('.')) -replace '(?i)\s*tool$', ''
        return "$tool 사용을 허용할지 기다리고 있어요."
    }
    if ($m -match '(?i)needs your permission') { return '권한 승인을 기다리고 있어요.' }
    if ($m -match '(?i)waiting for your input') { return '입력을 기다리고 있어요.' }
    return (Format-Body $m)
}

# Stop(작업 완료) 요약: 마지막 응답에서 URL·불릿·마크다운을 걷어내고 핵심 한 줄만.
function Format-Summary($text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return '작업이 완료되었습니다.' }
    $t = $text
    $t = $t -replace '(?s)```.*?```', ' '
    $t = $t -replace '`{1,3}', ''
    $t = $t -replace '(?m)^\s*#{1,6}\s*', ''
    $t = $t -replace '\*\*', ''
    $t = $t -replace '\[([^\]]+)\]\(https?://[^\)]+\)', '$1'
    $t = $t -replace 'https?://\S+', ''

    $first = $null
    foreach ($ln in ($t -split "`n")) {
        $s = $ln.Trim()
        if ($s -eq '') { continue }
        $s = $s -replace '^\s*([-*•]|\d+[.)])\s+', ''
        $s = ($s -replace '^[\p{So}\p{Sk}\s:>\-]+', '').Trim()
        if ($s -ne '') { $first = $s; break }
    }
    if ([string]::IsNullOrWhiteSpace($first)) { return '작업이 완료되었습니다.' }

    # 문장 경계(부호+공백/끝)까지만 — "v1.0.0" 같은 숫자 사이 점은 경계가 아님.
    $bounds = [regex]::Matches($first, '[.!?。](\s|$)')
    if ($bounds.Count -gt 0) {
        $end = $bounds[$bounds.Count - 1].Index + 1
        if ($end -lt $first.Length) { $first = $first.Substring(0, $end) }
    }
    $first = $first.TrimEnd(@(' ', ':', '/', '-', '·')).Trim()
    if ($first.Length -gt 140) { $first = $first.Substring(0, 140).Trim() + '…' }
    return $first
}

# 트랜스크립트(JSONL)에서 마지막 assistant 텍스트 응답을 뽑는다.
function Get-Summary($transcript) {
    if (-not ($transcript -and (Test-Path $transcript))) {
        Write-Log "트랜스크립트 없음: $transcript"
        return '작업이 완료되었습니다.'
    }
    $summary = $null
    # Get-Content -Tail 은 큰 파일에서 매우 느리다(7MB 에 ~700ms). .NET 으로 전체를
    # 읽으면 같은 파일이 ~30ms 라 훨씬 빠르다.
    try { $lines = [System.IO.File]::ReadAllLines($transcript, [System.Text.Encoding]::UTF8) }
    catch { $lines = @(Get-Content -LiteralPath $transcript -Tail 600 -Encoding utf8) }
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $line = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        # assistant 줄만 JSON 파싱한다. tool_result 등 거대한 줄을 ConvertFrom-Json 하면
        # 매우 느려지므로(파싱이 2초 넘게 걸리는 원인), 마커가 없는 줄은 건너뛴다.
        if ($line -notmatch '"type"\s*:\s*"assistant"') { continue }
        try { $obj = $line | ConvertFrom-Json } catch { continue }
        if ($obj.type -ne 'assistant') { continue }
        $texts = @()
        foreach ($block in $obj.message.content) {
            if ($block.type -eq 'text' -and $block.text) { $texts += $block.text }
        }
        if ($texts.Count -gt 0) { $summary = ($texts -join "`n").Trim(); break }
    }
    if ([string]::IsNullOrWhiteSpace($summary)) { return '작업이 완료되었습니다.' }
    return $summary
}
