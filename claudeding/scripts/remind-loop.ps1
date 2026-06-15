# remind-loop.ps1  (ClaudeDing)
# Notification(입력/권한 대기) 후 백그라운드에서 실행되는 리마인드 루프.
# 설정 주기마다 다시 토스트를 띄우고, 사용자가 응답하면(잠금 삭제 또는 트랜스크립트가
# 자라면) 멈춘다. 절대 깨지지 않도록 try/catch, 항상 0 종료.

param([string]$Key)

. (Join-Path $PSScriptRoot '_common.ps1')
Initialize-State

try {
    $count = 0
    while ($true) {
        $lock = Get-ReminderLock $Key
        if (-not $lock) { break }                       # 취소됨
        $interval = [int]$lock.intervalMs
        if ($interval -le 0) { break }

        Start-Sleep -Milliseconds $interval

        $lock = Get-ReminderLock $Key
        if (-not $lock) { break }                       # 대기 중 취소됨

        # 사용자가 응답하면 Claude 가 다시 트랜스크립트에 기록한다 → 파일이 자랐으면 종료.
        try {
            if ($lock.transcript -and (Test-Path $lock.transcript)) {
                $len = (Get-Item -LiteralPath $lock.transcript).Length
                if ($len -gt [int64]$lock.transcriptLen) { Remove-LockFile $Key; break }
            }
        } catch {}

        $count++
        $max = [int]$lock.max
        if ($max -gt 0 -and $count -gt $max) {
            Write-Log "리마인드 최대 횟수($max) 도달 [$Key]"
            Remove-LockFile $Key
            break
        }

        $title = ([string]$lock.title) -replace '^🔔 ', "🔁 ($count) "
        Show-Toast -Title $title -Body ([string]$lock.body) `
            -LaunchPid ([int]$lock.winPid) -LaunchHwnd ([long]$lock.winHwnd) -Tag $Key
        Write-Log "리마인드 #$count [$Key]: $title"
    }
}
catch { Write-Log "리마인드 루프 오류: $($_.Exception.Message)" }

exit 0
