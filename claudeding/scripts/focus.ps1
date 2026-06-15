# focus.ps1  (ClaudeDing)
# 토스트 알림 클릭 시 프로토콜(claudeding://focus?pid=..&hwnd=..)로 실행된다.
# Claude Code 가 돌던 터미널 창을 찾아 최상단으로 복귀시킨다.
# 절대 깨지지 않도록 전부 try/catch, 항상 0 종료.

param([string]$Uri)

$ErrorActionPreference = 'Stop'
$logPath = Join-Path $env:USERPROFILE '.claude\notify-complete.log'
function Write-Log($m) { try { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  [focus] $m" | Out-File -FilePath $logPath -Append -Encoding utf8 } catch {} }

try {
    $targetPid = 0
    $hwnd = [IntPtr]::Zero
    if ($Uri -match 'pid=(\d+)')  { $targetPid = [int]$Matches[1] }
    if ($Uri -match 'hwnd=(\d+)') { $hwnd = [IntPtr][int64]$Matches[1] }

    # pid 가 아직 살아 있으면 현재 메인 창 핸들을 우선 사용(HWND 는 재생성될 수 있음).
    if ($targetPid -gt 0) {
        try {
            $p = Get-Process -Id $targetPid -ErrorAction Stop
            if ($p.MainWindowHandle -ne 0) { $hwnd = $p.MainWindowHandle }
        } catch {}
    }

    if ($hwnd -eq [IntPtr]::Zero) { Write-Log "창을 찾지 못함: $Uri"; exit 0 }

    Add-Type -Namespace CD -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
[DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
[DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
'@

    # 최소화돼 있으면 복원(SW_RESTORE=9), 아니면 표시(SW_SHOW=5)
    if ([CD.Win]::IsIconic($hwnd)) { [void][CD.Win]::ShowWindow($hwnd, 9) }
    else { [void][CD.Win]::ShowWindow($hwnd, 5) }

    # 다른 창이 포그라운드일 때 SetForegroundWindow 가 막히는 제약을, 입력 스레드를
    # 잠시 붙여(AttachThreadInput) 우회한다.
    $fg = [CD.Win]::GetForegroundWindow()
    $dummy = 0
    $fgThread  = [CD.Win]::GetWindowThreadProcessId($fg, [ref]$dummy)
    $thisThread = [CD.Win]::GetCurrentThreadId()
    $attached = $false
    try {
        if ($fgThread -ne $thisThread) { $attached = [CD.Win]::AttachThreadInput($fgThread, $thisThread, $true) }
        [void][CD.Win]::BringWindowToTop($hwnd)
        [void][CD.Win]::SetForegroundWindow($hwnd)
    } finally {
        if ($attached) { [void][CD.Win]::AttachThreadInput($fgThread, $thisThread, $false) }
    }

    Write-Log "포커스 복귀 hwnd=$hwnd pid=$targetPid"
}
catch { Write-Log "오류: $($_.Exception.Message)" }

exit 0
