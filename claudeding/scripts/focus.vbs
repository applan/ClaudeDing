' focus.vbs  (ClaudeDing)
' 토스트 클릭 시 등록된 claudeding:// 프로토콜이 이 파일을 wscript.exe 로 실행한다.
' powershell 을 직접 핸들러로 쓰면 콘솔 창이 한 번 깜빡이므로,
' 창 없는 wscript 가 focus.ps1 을 SW_HIDE(0)로 숨겨서 실행해 깜빡임을 없앤다.
'
' 보안: 들어온 URI 를 명령 문자열에 그대로 붙이면 인젝션 위험이 있으므로,
' pid/hwnd 를 숫자만 정규식으로 추출해 깨끗하게 재조립한 값만 넘긴다.
Option Explicit
On Error Resume Next
Dim sh, ps1, uri, re, m, pidVal, hwndVal, arg
Set sh = CreateObject("WScript.Shell")
ps1 = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\")) & "focus.ps1"
If WScript.Arguments.Count = 0 Then WScript.Quit
uri = WScript.Arguments(0)

pidVal = "0"
hwndVal = "0"
Set re = New RegExp
re.Pattern = "pid=(\d+)"
Set m = re.Execute(uri)
If m.Count > 0 Then pidVal = m(0).SubMatches(0)
re.Pattern = "hwnd=(\d+)"
Set m = re.Execute(uri)
If m.Count > 0 Then hwndVal = m(0).SubMatches(0)

' pidVal/hwndVal 은 숫자(\d+)만 추출됐으므로 인젝션 불가.
arg = "claudeding://focus?pid=" & pidVal & "&hwnd=" & hwndVal
sh.Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """ """ & arg & """", 0, False
