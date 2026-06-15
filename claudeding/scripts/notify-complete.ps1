# notify-complete.ps1  (ClaudeDing)
# Claude Code 의 hook 에서 호출된다. stdin 으로 hook JSON 을 받아 Windows 토스트 알림을 띄운다.
#   - Stop 이벤트        : 작업 완료 → 트랜스크립트의 마지막 assistant 응답(요약)을 알림
#   - Notification 이벤트 : 입력/권한 선택 대기 → 그 메시지를 알림
# 외부 모듈 없이 Windows 내장 API 만 사용한다.
# hook 이 절대 깨지지 않도록 모든 동작을 try/catch 로 감싸고 항상 0 으로 종료한다.

$ErrorActionPreference = 'Stop'
$logPath = Join-Path $env:USERPROFILE '.claude\notify-complete.log'

function Write-Log($msg) {
    try { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg" | Out-File -FilePath $logPath -Append -Encoding utf8 } catch {}
}

function Show-Toast {
    param([string]$Title, [string]$Body)

    [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    [void][Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType = WindowsRuntime]
    [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]

    # 알림이 "ClaudeDing" 이름으로 뜨도록 전용 AppUserModelID 를 등록한다(없으면 생성).
    # HKCU 라 관리자 권한 불필요, 멱등이라 매번 실행해도 안전하다.
    $appId = 'ClaudeDing'
    $key = "HKCU:\Software\Classes\AppUserModelId\$appId"
    if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
    New-ItemProperty -Path $key -Name 'DisplayName' -Value 'ClaudeDing' -PropertyType String -Force | Out-Null

    $tEsc = [System.Security.SecurityElement]::Escape($Title)
    $bEsc = [System.Security.SecurityElement]::Escape($Body)

    $xmlText = @"
<toast activationType="protocol" launch="">
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
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)

    # 토스트 전달은 비동기다. 여기서 바로 프로세스가 종료되면 토스트가 플랫폼에
    # 전달되기 전에 죽어 알림이 안 보일 수 있으므로 잠깐 대기한다.
    Start-Sleep -Milliseconds 1200
}

# 트랜스크립트(JSONL)에서 마지막 assistant 텍스트 응답을 뽑아 한 줄 요약으로 만든다.
function Get-Summary($transcript) {
    if (-not ($transcript -and (Test-Path $transcript))) {
        Write-Log "트랜스크립트 없음: $transcript"
        return '작업이 완료되었습니다.'
    }
    $summary = $null
    $lines = @(Get-Content -LiteralPath $transcript -Tail 600 -Encoding utf8)
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $line = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
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

# 알림 본문 정리: 마크다운 기호 제거 + 한 줄로 + 길이 제한
function Format-Body($text) {
    $t = $text -replace '`{1,3}', '' -replace '(?m)^\s*#{1,6}\s*', '' -replace '\*\*', ''
    $t = ($t -split "`n" | Where-Object { $_.Trim() -ne '' }) -join ' / '
    if ($t.Length -gt 250) { $t = $t.Substring(0, 250) + '…' }
    return $t
}

try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { Write-Log 'stdin 비어있음'; return }

    $hook = $raw | ConvertFrom-Json
    $event = $hook.hook_event_name
    $cwd = $hook.cwd
    $project = if ($cwd) { Split-Path $cwd -Leaf } else { 'Claude Code' }
    $time = Get-Date -Format 'HH:mm'

    if ($event -eq 'Notification') {
        # 입력/권한 선택 대기
        $msg = if ($hook.message) { [string]$hook.message } else { '입력 또는 선택을 기다리고 있어요.' }
        $title = "🔔 Claude 입력 대기 · $project ($time)"
        $body  = Format-Body $msg
    }
    else {
        # Stop (작업 완료) 및 기타
        $title = "✅ Claude 작업 완료 · $project ($time)"
        $body  = Format-Body (Get-Summary $hook.transcript_path)
    }

    Show-Toast -Title $title -Body $body
    Write-Log "알림 표시 [$event]: $title | $body"
}
catch {
    Write-Log "오류: $($_.Exception.Message)"
}

# hook 이 멈추지 않도록 항상 정상 종료
exit 0
