' Starts Build Studio without flashing a console window.
Set fso = CreateObject("Scripting.FileSystemObject")
app = fso.GetParentFolderName(WScript.ScriptFullName)
ps = CreateObject("WScript.Shell").ExpandEnvironmentStrings("%WINDIR%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
CreateObject("WScript.Shell").Run Chr(34) & ps & Chr(34) & " -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File " & Chr(34) & app & "\BuildStudio.ps1" & Chr(34), 0, False
