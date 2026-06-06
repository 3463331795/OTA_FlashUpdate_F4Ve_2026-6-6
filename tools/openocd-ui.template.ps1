param(
    [ValidateSet("Flash", "Probe")]
    [string]$Action = "Flash",
    [string]$Config = ".vscode/stm32-openocd.json"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Config)) {
    Write-Host "错误：未找到配置文件：$Config" -ForegroundColor Red
    Write-Host "请运行项目根目录下的 setup-stm32-vscode.bat。" -ForegroundColor Yellow
    exit 1
}

$settings = Get-Content -LiteralPath $Config -Raw -Encoding UTF8 | ConvertFrom-Json
$OpenOcd = $settings.tools.openocd
$Scripts = $settings.tools.scripts
$SizeTool = $settings.tools.size
$Image = $settings.image.path
$ImageFormat = $settings.image.format.ToLowerInvariant()
$DownloadAddress = $settings.image.downloadAddress
$FlashTotal = [long]$settings.memory.flashBytes
$AppBase = [Convert]::ToInt64($settings.memory.appBase, 16)
$AppSize = [long]$settings.memory.appBytes
$RamTotal = [long]$settings.memory.ramBytes
$CcmRamTotal = [long]$settings.memory.ccmRamBytes
$Mcu = $settings.mcu.partNumber
$Programmer = if ($settings.openocd.programmer) { $settings.openocd.programmer } else { $settings.openocd.interface }
$TargetConfig = $settings.openocd.target
$InterfaceConfig = $settings.openocd.interface
$script:ProgressText = ""
$script:ProgressColor = [ConsoleColor]::Cyan

function Write-Stage {
    param(
        [int]$Percent,
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Cyan
    )

    $width = 30
    $filled = [Math]::Floor($Percent * $width / 100)
    $bar = ("#" * $filled).PadRight($width, "-")
    $script:ProgressText = ("[{0}] {1,3}%  {2}" -f $bar, $Percent, $Message).PadRight(78)
    $script:ProgressColor = $Color
    Write-Host ("`r" + $script:ProgressText) -ForegroundColor $script:ProgressColor -NoNewline
}

function Complete-StageLine {
    Write-Host ""
}

function Write-LogAboveProgress {
    param(
        [string]$Text,
        [ConsoleColor]$Color
    )

    Write-Host ("`r" + (" " * 100) + "`r") -NoNewline
    Write-Host $Text -ForegroundColor $Color
    if ($script:ProgressText) {
        Write-Host $script:ProgressText -ForegroundColor $script:ProgressColor -NoNewline
    }
}

function Write-MemoryBar {
    param(
        [string]$Name,
        [long]$Used,
        [long]$Total
    )

    $percent = if ($Total -gt 0) { ($Used * 100.0) / $Total } else { 0 }
    $width = 30
    $filled = [Math]::Min($width, [Math]::Floor($percent * $width / 100))
    $bar = ("#" * $filled).PadRight($width, "-")
    $color = if ($percent -ge 90) {
        [ConsoleColor]::Red
    } elseif ($percent -ge 75) {
        [ConsoleColor]::Yellow
    } else {
        [ConsoleColor]::Green
    }

    Write-Host (" {0,-5} [{1}] {2,7:N1} / {3,7:N1} KiB  ({4,6:N2}%)" -f $Name, $bar, ($Used / 1KB), ($Total / 1KB), $percent) -ForegroundColor $color
}

function Write-MemoryUsage {
    if (-not (Test-Path -LiteralPath $SizeTool)) {
        Write-Host " 警告：未找到 arm-none-eabi-size，无法统计存储占用。" -ForegroundColor Yellow
        return
    }

    if ($ImageFormat -ne "elf") {
        Write-Host " 提示：BIN/HEX 固件不包含完整段信息，跳过 RAM 占用统计。" -ForegroundColor Yellow
        return
    }

    $sizeOutput = & $SizeTool $Image 2>&1
    $dataLine = $sizeOutput | Where-Object { $_.ToString() -match "^\s*(\d+)\s+(\d+)\s+(\d+)\s+\d+\s+[0-9a-fA-F]+\s+" } | Select-Object -Last 1
    if (-not $dataLine -or $dataLine.ToString() -notmatch "^\s*(\d+)\s+(\d+)\s+(\d+)") {
        Write-Host " 警告：无法解析 ELF 存储占用。" -ForegroundColor Yellow
        return
    }

    $textBytes = [long]$Matches[1]
    $dataBytes = [long]$Matches[2]
    $bssBytes = [long]$Matches[3]
    $flashUsed = $textBytes + $dataBytes
    $totalRamUsed = $dataBytes + $bssBytes

    $sectionOutput = & $SizeTool -A $Image 2>&1
    $ccmLine = $sectionOutput | Where-Object { $_.ToString() -match "^\s*\.ccmram\s+(\d+)\s+" } | Select-Object -First 1
    $ccmRamUsed = 0
    if ($ccmLine -and $ccmLine.ToString() -match "^\s*\.ccmram\s+(\d+)\s+") {
        $ccmRamUsed = [long]$Matches[1]
    }
    $ramUsed = [Math]::Max(0, $totalRamUsed - $ccmRamUsed)

    Write-Host ""
    Write-Host " 存储占用：" -ForegroundColor Cyan
    Write-MemoryBar "应用区" $flashUsed $AppSize
    Write-MemoryBar "总FLASH" $flashUsed $FlashTotal
    Write-MemoryBar "RAM" $ramUsed $RamTotal
    Write-MemoryBar "CCMRAM" $ccmRamUsed $CcmRamTotal
    Write-MemoryBar "总RAM" $totalRamUsed ($RamTotal + $CcmRamTotal)
}

function Write-OpenOcdLine {
    param([string]$Line)

    if ($Line -eq "System.Management.Automation.RemoteException") {
        return
    }

    if ($Line -match "unable to find a matching CMSIS-DAP device") {
        Write-LogAboveProgress "错误：未找到可用的 CMSIS-DAP 调试探针。" Red
        Write-LogAboveProgress "提示：请检查 USB 连接，并关闭其他正在占用探针的调试会话。" Yellow
        return
    }

    if ($Line -match "Error:|Programming Failed|failed|unable|couldn't") {
        Write-LogAboveProgress ("错误：" + $Line) Red
        return
    }

    if ($Line -match "Warn :|warning") {
        Write-LogAboveProgress ("警告：" + $Line) Yellow
        return
    }

    if ($Line -match "CMSIS-DAP: Interface ready") {
        Write-LogAboveProgress "成功：CMSIS-DAP 调试探针接口已就绪。" Green
        return
    }

    if ($Line -match "STLINK|ST-Link") {
        Write-LogAboveProgress "成功：ST-Link 烧写器接口已就绪。" Green
        return
    }

    if ($Line -match "J-Link|JLINK") {
        Write-LogAboveProgress "成功：J-Link 烧写器接口已就绪。" Green
        return
    }

    if ($Line -match "(Cortex-M\d)") {
        Write-LogAboveProgress ("成功：已识别处理器：" + $Matches[1]) Green
        return
    }

    if ($Line -match "Examination succeed") {
        Write-LogAboveProgress "成功：目标芯片检查通过。" Green
        return
    }

    if ($Line -match "flash size = ([^\r\n]+)") {
        Write-LogAboveProgress ("成功：已识别 Flash 容量：" + $Matches[1]) Green
        return
    }

    if ($Line -match "Programming Started") {
        Write-LogAboveProgress "进行中：开始写入固件。" Cyan
        return
    }

    if ($Line -match "Programming Finished") {
        Write-LogAboveProgress "成功：固件写入完成。" Green
        return
    }

    if ($Line -match "Verify Started") {
        Write-LogAboveProgress "进行中：开始校验固件。" Cyan
        return
    }

    if ($Line -match "Verified OK") {
        Write-LogAboveProgress "成功：固件校验通过。" Green
        return
    }

    if ($Line -match "Resetting Target") {
        Write-LogAboveProgress "成功：正在复位目标芯片。" Green
        return
    }
}

if (-not (Test-Path -LiteralPath $OpenOcd)) {
    Write-Host "错误：未找到 OpenOCD 可执行文件：" -ForegroundColor Red
    Write-Host $OpenOcd -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $Scripts)) {
    Write-Host "错误：未找到 OpenOCD 脚本目录：" -ForegroundColor Red
    Write-Host $Scripts -ForegroundColor Red
    exit 1
}

if ($Action -eq "Flash" -and -not (Test-Path -LiteralPath $Image)) {
    Write-Host "错误：未找到固件文件：$Image" -ForegroundColor Red
    Write-Host "请先编译 Debug 配置，再执行下载。" -ForegroundColor Yellow
    exit 1
}

if ($Action -eq "Flash" -and $ImageFormat -eq "bin" -and (Get-Item -LiteralPath $Image).Length -gt $AppSize) {
    Write-Host "错误：BIN 固件大小超过所选应用区域。" -ForegroundColor Red
    Write-Host ("固件：{0:N1} KiB，应用区域：{1:N1} KiB" -f ((Get-Item -LiteralPath $Image).Length / 1KB), ($AppSize / 1KB)) -ForegroundColor Yellow
    exit 1
}

if ($Action -eq "Flash" -and $ImageFormat -eq "elf" -and (Test-Path -LiteralPath $SizeTool)) {
    $preflightSize = & $SizeTool $Image 2>&1
    $preflightLine = $preflightSize | Where-Object { $_.ToString() -match "^\s*(\d+)\s+(\d+)\s+(\d+)\s+\d+\s+[0-9a-fA-F]+\s+" } | Select-Object -Last 1
    if ($preflightLine -and $preflightLine.ToString() -match "^\s*(\d+)\s+(\d+)\s+(\d+)") {
        $preflightFlashUsed = [long]$Matches[1] + [long]$Matches[2]
        if ($preflightFlashUsed -gt $AppSize) {
            Write-Host "错误：ELF 固件占用超过所选应用区域。" -ForegroundColor Red
            Write-Host ("固件：{0:N1} KiB，应用区域：{1:N1} KiB" -f ($preflightFlashUsed / 1KB), ($AppSize / 1KB)) -ForegroundColor Yellow
            exit 1
        }
    }
}

$command = if ($Action -eq "Flash") {
    if ($ImageFormat -eq "bin") {
        "program {$Image} $DownloadAddress verify reset exit"
    } else {
        "program {$Image} verify reset exit"
    }
} else {
    "init; shutdown"
}

Write-Host ""
Write-Host $(if ($Action -eq "Flash") { " STM32 固件下载 " } else { " STM32 调试探针检查 " }) -ForegroundColor Black -BackgroundColor Cyan
Write-Host (" 目标芯片：{0}，烧写器：{1}" -f $Mcu, $Programmer) -ForegroundColor White
if ($Action -eq "Flash") {
    Write-Host (" 固件路径：{0}" -f $Image) -ForegroundColor White
    Write-Host (" 应用区域：0x{0:X8} - 0x{1:X8} ({2:N1} KiB)" -f $AppBase, ($AppBase + $AppSize - 1), ($AppSize / 1KB)) -ForegroundColor White
    Write-Host (" 固件文件大小：{0:N1} KiB" -f ((Get-Item -LiteralPath $Image).Length / 1KB)) -ForegroundColor White
}
Write-Host ""

Write-Stage 5 "正在检查工具"
Write-Stage 15 "正在启动 OpenOCD"
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

$lines = New-Object System.Collections.Generic.List[string]
$shownProbe = $false
$shownTarget = $false
$shownProgramming = $false
$shownVerification = $false

$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
& $OpenOcd `
    -s $Scripts `
    -f $InterfaceConfig `
    -f $TargetConfig `
    -c $command 2>&1 | ForEach-Object {
        $line = $_.ToString()
        $lines.Add($line)

        if (-not $shownProbe -and $line -match "CMSIS-DAP: Interface ready|STLINK|ST-Link|J-Link|JLINK") {
            Write-Stage 30 "烧写器已连接"
            $shownProbe = $true
        }

        if (-not $shownTarget -and $line -match "Cortex-M\d") {
            Write-Stage 45 "已识别目标芯片"
            $shownTarget = $true
        }

        if ($Action -eq "Flash" -and -not $shownProgramming -and $line -match "Programming Finished") {
            Write-Stage 70 "固件写入完成"
            $shownProgramming = $true
        }

        if ($Action -eq "Flash" -and -not $shownVerification -and $line -match "Verified OK") {
            Write-Stage 90 "固件校验通过"
            $shownVerification = $true
        }

        Write-OpenOcdLine $line
    }
$exitCode = $LASTEXITCODE
$ErrorActionPreference = $previousErrorActionPreference
$stopwatch.Stop()

$joinedOutput = $lines -join "`n"

$success = $exitCode -eq 0 -and $joinedOutput -notmatch "Error:|Programming Failed|failed|unable|couldn't"
if ($Action -eq "Flash") {
    $success = $success -and $joinedOutput -match "Verified OK"
}

if (-not $success) {
    Write-Stage 100 $(if ($Action -eq "Flash") { "固件下载失败" } else { "调试探针检查失败" }) Red
    Complete-StageLine
    Write-Host (" 用时：{0:N2} 秒" -f $stopwatch.Elapsed.TotalSeconds) -ForegroundColor Yellow
    exit 1
}

$finalMessage = if ($Action -eq "Flash") { "固件下载并校验成功" } else { "调试目标已准备就绪" }
Write-Stage 100 $finalMessage Green
Complete-StageLine
if ($Action -eq "Flash") {
    Write-MemoryUsage
}
Write-Host (" 用时：{0:N2} 秒" -f $stopwatch.Elapsed.TotalSeconds) -ForegroundColor Green
exit 0
