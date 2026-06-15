' focus.vbs  (ClaudeDing)
' 토스트 클릭 시 등록된 claudeding:// 프로토콜이 이 파일을 wscript.exe 로 실행한다.
' powershell 을 직접 핸들러로 쓰면 콘솔 창이 한 번 깜빡이므로,
' 창 없는 wscript 가 focus.ps1 을 SW_HIDE(0)로 숨겨서 실행해 깜빡임을 없앤다.
Option Explicit
On Error Resume Next
Dim sh, ps1
Set sh = CreateObject("WScript.Shell")
ps1 = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\")) & "focus.ps1"
If WScript.Arguments.Count > 0 Then
  sh.Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """ """ & WScript.Arguments(0) & """", 0, False
End If
