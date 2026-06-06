Option Explicit
Dim shell, fso, root, launcher, powershell, command, exitCode
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
root = fso.GetParentFolderName(WScript.ScriptFullName)
launcher = root & "\tools\launch-stm32-vscode-gui.ps1"
powershell = shell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")
If Not fso.FileExists(launcher) Then
    MsgBox "Missing file:" & vbCrLf & launcher & vbCrLf & vbCrLf & "Copy the complete tools folder.", 16, "STM32 VS Code Configurator"
    WScript.Quit 1
End If
If Not fso.FileExists(powershell) Then
    MsgBox "Windows PowerShell 5.1 was not found:" & vbCrLf & powershell, 16, "STM32 VS Code Configurator"
    WScript.Quit 1
End If
command = """" & powershell & """ -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & launcher & """ -ProjectRoot """ & root & """"
exitCode = shell.Run(command, 0, True)
If exitCode <> 0 Then
    MsgBox "The configurator failed to start." & vbCrLf & "See .vscode\setup-stm32-vscode-error.log for details.", 16, "STM32 VS Code Configurator"
End If
WScript.Quit exitCode
