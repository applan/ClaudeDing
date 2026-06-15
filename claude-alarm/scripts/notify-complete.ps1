# notify-complete.ps1
# Claude Code 의 Stop hook 에서 호출된다.
# stdin 으로 hook JSON 을 받아서, 트랜스크립트의 마지막 assistant 응답(작업 요약)을
# Windows 토스트 알림으로 띄운다. 외부 모듈 없이 Windows 내장 API 만 사용.
#
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

    # PowerShell 이 미리 등록되어 있는 AppUserModelID (토스트가 안정적으로 표시됨)
    $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'

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
}

try {
    # 1) stdin 에서 hook JSON 읽기
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { Write-Log 'stdin 비어있음'; return }

    $hook = $raw | ConvertFrom-Json
    $transcript = $hook.transcript_path
    $cwd = $hook.cwd

    $project = if ($cwd) { Split-Path $cwd -Leaf } else { 'Claude Code' }

    # 2) 트랜스크립트(JSONL)에서 마지막 assistant 텍스트 응답 추출
    $summary = $null
    if ($transcript -and (Test-Path $transcript)) {
        # 최근 줄만 읽어서 뒤에서부터 텍스트가 있는 assistant 메시지를 찾는다
        $lines = Get-Content -LiteralPath $transcript -Tail 600 -Encoding utf8
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            $line = $lines[$i]
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try { $obj = $line | ConvertFrom-Json } catch { continue }
            if ($obj.type -ne 'assistant') { continue }

            $content = $obj.message.content
            $texts = @()
            foreach ($block in $content) {
                if ($block.type -eq 'text' -and $block.text) { $texts += $block.text }
            }
            if ($texts.Count -gt 0) {
                $summary = ($texts -join "`n").Trim()
                break
            }
        }
    } else {
        Write-Log "트랜스크립트 없음: $transcript"
    }

    if ([string]::IsNullOrWhiteSpace($summary)) {
        $summary = '작업이 완료되었습니다.'
    }

    # 3) 본문 정리: 마크다운 헤더/기호 약간 정리하고 길이 제한
    $summary = $summary -replace '`{1,3}', '' -replace '^\s*#{1,6}\s*', '' -replace '\*\*', ''
    $summary = ($summary -split "`n" | Where-Object { $_.Trim() -ne '' }) -join ' / '
    $maxLen = 250
    if ($summary.Length -gt $maxLen) {
        $summary = $summary.Substring(0, $maxLen) + '…'
    }

    $time = Get-Date -Format 'HH:mm'
    $title = "✅ Claude 작업 완료 · $project ($time)"

    Show-Toast -Title $title -Body $summary
    Write-Log "알림 표시: $title | $summary"
}
catch {
    Write-Log "오류: $($_.Exception.Message)"
}

# hook 이 멈추지 않도록 항상 정상 종료
exit 0
