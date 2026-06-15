# notify-complete.ps1  (ClaudeDing) — hook 진입점
# Claude Code 의 hook 에서 호출된다. stdin 으로 hook JSON 을 받아 Windows 토스트 알림을 띄운다.
#   - Stop 이벤트             : 작업 완료 → 마지막 응답 요약을 알림 + 대기 리마인드 해제
#   - Notification 이벤트      : 입력/권한 선택 대기 → 한국어로 알림 + 리마인드 시작
#   - UserPromptSubmit 이벤트  : 사용자가 응답함 → 대기 리마인드 해제(토스트 없음)
# 알림 클릭 시 claudeding:// 프로토콜로 해당 터미널 창을 최상단 복귀시킨다.
# hook 이 절대 깨지지 않도록 모든 동작을 try/catch 로 감싸고 항상 0 으로 종료한다.

$scriptStart = Get-Date
. (Join-Path $PSScriptRoot '_common.ps1')
Initialize-State

# Notification 대기 시 일정 주기로 다시 알려주는 백그라운드 리마인드 루프를 띄운다.
function Start-Reminder($hook, $key, $title, $body, $win) {
    $cfg = Get-Config
    if ($cfg.IntervalMs -le 0) { return }   # 설정으로 비활성

    $transcript = [string]$hook.transcript_path
    $tlen = 0
    try { if ($transcript -and (Test-Path $transcript)) { $tlen = (Get-Item -LiteralPath $transcript).Length } } catch {}

    $lock = [pscustomobject]@{
        title         = $title
        body          = $body
        transcript    = $transcript
        transcriptLen = $tlen
        intervalMs    = $cfg.IntervalMs
        max           = $cfg.Max
        winPid        = if ($win) { [int]$win.pid } else { 0 }
        winHwnd       = if ($win) { [long]$win.hwnd } else { 0 }
        started       = (Get-Date).ToString('o')
        reminderPid   = 0
    }

    # 이미 살아있는 리마인드 루프가 있으면 잠금만 갱신(중복 루프 방지).
    $alive = $false
    $existing = Get-ReminderLock $key
    if ($existing -and $existing.reminderPid) {
        try {
            $p = Get-Process -Id ([int]$existing.reminderPid) -ErrorAction Stop
            if ($p.ProcessName -like 'powershell*') { $alive = $true; $lock.reminderPid = $existing.reminderPid }
        } catch {}
    }
    Set-ReminderLock $key $lock

    if (-not $alive) {
        try {
            $loop = Join-Path $PSScriptRoot 'remind-loop.ps1'
            $p = Start-Process -FilePath 'powershell' -WindowStyle Hidden -PassThru -ArgumentList @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $loop, $key
            )
            $lock.reminderPid = $p.Id
            Set-ReminderLock $key $lock
        } catch { Write-Log "리마인드 시작 실패: $($_.Exception.Message)" }
    }
}

try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { Write-Log 'stdin 비어있음'; return }

    $hook = $raw | ConvertFrom-Json
    $event = $hook.hook_event_name
    $key = Get-SessionKey $hook
    $cwd = $hook.cwd
    $project = if ($cwd) { Split-Path $cwd -Leaf } else { 'Claude Code' }
    $time = Get-Date -Format 'HH:mm'

    # 사용자가 응답한 신호 → 대기 리마인드만 해제하고 종료(토스트 없음).
    if ($event -eq 'UserPromptSubmit') {
        Remove-ReminderLock $key
        Write-Log "리마인드 해제(입력 제출) [$key]"
        return
    }

    # 클릭 복귀 대상 창: 토스트 전에는 캐시만 빠르게 읽는다(WMI 호출은 토스트 뒤로 미룸).
    $win = Get-CachedWindow $key
    $winPid  = if ($win) { [int]$win.pid }  else { 0 }
    $winHwnd = if ($win) { [long]$win.hwnd } else { 0 }

    $parseMs = 0
    if ($event -eq 'Notification') {
        $title = "🔔 입력 대기 · $project ($time)"
        $body  = Format-Notice $hook.message
        Show-Toast -Title $title -Body $body -LaunchPid $winPid -LaunchHwnd $winHwnd -Tag $key
        # 토스트를 띄운 뒤 창을 확정·캐시한다(체감 지연에 영향 없음). 리마인드/다음 알림부터 클릭 복귀 동작.
        if (-not $win) { $win = Get-TerminalWindow $key }
        Start-Reminder $hook $key $title $body $win
    }
    else {
        # Stop(작업 완료) 및 기타 — 대기 중이었다면 해제.
        Remove-ReminderLock $key
        $pw = [Diagnostics.Stopwatch]::StartNew()
        $summary = Get-Summary $hook.transcript_path
        $pw.Stop(); $parseMs = $pw.ElapsedMilliseconds
        $title = "✅ 작업 완료 · $project ($time)"
        $body  = Format-Summary $summary
        Show-Toast -Title $title -Body $body -LaunchPid $winPid -LaunchHwnd $winHwnd
        # 다음 알림의 클릭 복귀를 위해 창을 캐시(토스트 뒤라 지연 없음).
        if (-not $win) { $null = Get-TerminalWindow $key }
    }

    Write-Log "알림 표시 [$event]: $title | $body"

    # ── 지연 구간 측정 ──
    try { $startupMs = [int]((New-TimeSpan -Start (Get-Process -Id $PID).StartTime -End $scriptStart).TotalMilliseconds) }
    catch { $startupMs = -1 }
    $showAt = if ($script:LastShowAt) { $script:LastShowAt } else { Get-Date }
    $totalMs = [int]((New-TimeSpan -Start $scriptStart -End $showAt).TotalMilliseconds)
    $toasts = '?'
    try {
        $v = Get-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings' -Name 'NOC_GLOBAL_SETTING_TOASTS_ENABLED' -ErrorAction Stop
        $toasts = $v.NOC_GLOBAL_SETTING_TOASTS_ENABLED
    } catch { $toasts = '?' }
    Write-Perf $event $startupMs $script:LastWinrtMs $parseMs $totalMs $toasts
}
catch {
    Write-Log "오류: $($_.Exception.Message)"
}

# hook 이 멈추지 않도록 항상 정상 종료
exit 0
