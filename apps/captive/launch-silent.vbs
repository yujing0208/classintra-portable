' launch-silent.vbs
' Launches the self-restarting watchdog in hidden mode (no console window)
' Called by the Windows scheduled task at system startup
'
' SW_HIDE (0) = hidden window
' False       = do not wait for the spawned process to exit

Dim WshShell, FSO, strDir, strLauncher, strCmd, strStopFlag, isRecovery

Set WshShell = CreateObject("Wscript.Shell")
Set FSO = CreateObject("Scripting.FileSystemObject")

' Script directory (same folder as this .vbs file)
strDir = FSO.GetParentFolderName(WScript.ScriptFullName)
strLauncher = strDir & "\watchdog-loop.bat"
strStopFlag = strDir & "\watchdog.stop"
isRecovery = False
If WScript.Arguments.Count > 0 Then
    isRecovery = (LCase(WScript.Arguments(0)) = "--recovery")
End If

' Do not defeat an intentional stop when this is the periodic recovery task.
If isRecovery And FSO.FileExists(strStopFlag) Then WScript.Quit 0

' Build command: start the self-restarting watchdog loop in hidden mode
strCmd = "cmd.exe /d /c " & Chr(34) & Chr(34) & strLauncher & Chr(34) & Chr(34)

' Set working directory and launch hidden
WshShell.CurrentDirectory = strDir
WshShell.Run strCmd, 0, False
