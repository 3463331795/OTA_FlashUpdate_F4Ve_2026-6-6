param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
$logPath = Join-Path $ProjectRoot '.vscode/setup-stm32-vscode-error.log'

try {
    $guiScript = Join-Path $PSScriptRoot 'setup-stm32-vscode-gui.ps1'
    $backendScript = Join-Path $PSScriptRoot 'setup-stm32-vscode.ps1'
    $uiTemplate = Join-Path $PSScriptRoot 'openocd-ui.template.ps1'

    foreach ($required in @($guiScript, $backendScript, $uiTemplate)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "缺少必要文件：$required`r`n请完整复制 setup-stm32-vscode.vbs、setup-stm32-vscode.bat 和 tools 文件夹。"
        }
    }

    if ($PSVersionTable.PSVersion.Major -lt 5) {
        throw "需要 Windows PowerShell 5.1 或更高版本，当前版本：$($PSVersionTable.PSVersion)"
    }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    & $guiScript -ProjectRoot $ProjectRoot -ValidateOnly:$ValidateOnly
} catch {
    $message = @"
STM32 VS Code 配置器启动失败。

$($_.Exception.Message)

错误日志：
$logPath
"@
    try {
        $logDir = Split-Path -Parent $logPath
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        $details = @(
            "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            "ProjectRoot: $ProjectRoot"
            "PowerShell: $($PSVersionTable.PSVersion)"
            "OS: $([Environment]::OSVersion.VersionString)"
            ""
            $_.Exception.ToString()
            ""
            $_.ScriptStackTrace
        ) -join "`r`n"
        [System.IO.File]::WriteAllText($logPath, $details, (New-Object System.Text.UTF8Encoding($true)))
    } catch { }

    try {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show($message, '启动失败', 'OK', 'Error') | Out-Null
    } catch {
        $host.UI.WriteErrorLine($message)
    }
    exit 1
}
