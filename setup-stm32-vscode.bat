@echo off
setlocal
cd /d "%~dp0"
start "" "%SystemRoot%\System32\wscript.exe" "%~dp0setup-stm32-vscode.vbs"
exit /b 0
