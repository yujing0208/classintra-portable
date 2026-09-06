' ClassIntra 开机自启隐藏启动器（无窗口运行同目录 classintra-autostart.bat）
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
sh.Run """" & dir & "\classintra-autostart.bat""", 0, False
