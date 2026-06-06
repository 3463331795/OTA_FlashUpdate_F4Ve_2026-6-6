param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$UseDefaults
)

$ErrorActionPreference = "Stop"
Set-Location $ProjectRoot

function Read-Default {
    param([string]$Prompt, [string]$Default)
    if ($UseDefaults) { return $Default }
    $value = Read-Host "$Prompt [$Default]"
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value.Trim()
}

function Parse-Hex {
    param([string]$Value)
    $clean = $Value.Trim() -replace '^0[xX]', ''
    return [Convert]::ToInt64($clean, 16)
}

function Hex8 {
    param([long]$Value)
    return ("0x{0:X8}" -f $Value)
}

function To-ForwardSlash {
    param([string]$Path)
    return $Path.Replace('\', '/')
}

function Find-NewestDirectory {
    param([string]$Root, [string]$Filter)
    return Get-ChildItem -LiteralPath $Root -Directory -Filter $Filter |
        Sort-Object Name -Descending |
        Select-Object -First 1
}

function Get-CommandPath {
    param([string]$Name)
    $command = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        if ($command.Path) { return $command.Path }
        if ($command.Source) { return $command.Source }
    }
    return ''
}

function Get-FirstExistingFile {
    param([string[]]$Candidates)
    foreach ($candidate in $Candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return ''
}

function Get-FirstExistingDirectory {
    param([string[]]$Candidates)
    foreach ($candidate in $Candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Container)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return ''
}

function Read-ExistingFile {
    param([string]$Prompt, [string]$Default)
    while ($true) {
        $value = Read-Default $Prompt $Default
        if (-not [string]::IsNullOrWhiteSpace($value) -and (Test-Path -LiteralPath $value -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $value).Path
        }
        if ($UseDefaults) { throw "未找到文件：$value" }
        Write-Host "路径无效，请重新填写：$value" -ForegroundColor Yellow
    }
}

function Read-ExistingDirectory {
    param([string]$Prompt, [string]$Default)
    while ($true) {
        $value = Read-Default $Prompt $Default
        if (-not [string]::IsNullOrWhiteSpace($value) -and (Test-Path -LiteralPath $value -PathType Container)) {
            return (Resolve-Path -LiteralPath $value).Path
        }
        if ($UseDefaults) { throw "未找到目录：$value" }
        Write-Host "路径无效，请重新填写：$value" -ForegroundColor Yellow
    }
}

function Find-OpenOcdScripts {
    param([string]$OpenOcdPath, [string[]]$ExtraCandidates)
    $openOcdDir = if ($OpenOcdPath) { Split-Path -Parent $OpenOcdPath } else { '' }
    $candidates = @(
        $env:OPENOCD_SCRIPTS
        $env:OPENOCD_SCRIPT_DIR
        $(if ($env:OPENOCD_PATH) { Join-Path $env:OPENOCD_PATH 'share/openocd/scripts' })
        $(if ($env:OPENOCD_PATH) { Join-Path $env:OPENOCD_PATH 'scripts' })
        $(if ($env:OPENOCD_HOME) { Join-Path $env:OPENOCD_HOME 'share/openocd/scripts' })
        $(if ($env:OPENOCD_HOME) { Join-Path $env:OPENOCD_HOME 'scripts' })
        $(if ($openOcdDir) { Join-Path $openOcdDir '../share/openocd/scripts' })
        $(if ($openOcdDir) { Join-Path $openOcdDir '../scripts' })
        $(if ($openOcdDir) { Join-Path $openOcdDir '../../share/openocd/scripts' })
    ) + $ExtraCandidates

    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate) -or -not (Test-Path -LiteralPath $candidate -PathType Container)) {
            continue
        }
        $resolved = (Resolve-Path -LiteralPath $candidate).Path
        if ((Test-Path -LiteralPath (Join-Path $resolved 'interface') -PathType Container) -and
            (Test-Path -LiteralPath (Join-Path $resolved 'target') -PathType Container)) {
            return $resolved
        }
    }
    return ''
}

function Get-TargetConfig {
    param([string]$PartNumber)
    $mappings = [ordered]@{
        '^STM32F0' = 'target/stm32f0x.cfg'
        '^STM32F1' = 'target/stm32f1x.cfg'
        '^STM32F2' = 'target/stm32f2x.cfg'
        '^STM32F3' = 'target/stm32f3x.cfg'
        '^STM32F4' = 'target/stm32f4x.cfg'
        '^STM32F7' = 'target/stm32f7x.cfg'
        '^STM32H7' = 'target/stm32h7x.cfg'
        '^STM32G0' = 'target/stm32g0x.cfg'
        '^STM32G4' = 'target/stm32g4x.cfg'
        '^STM32L0' = 'target/stm32l0.cfg'
        '^STM32L1' = 'target/stm32l1.cfg'
        '^STM32L4' = 'target/stm32l4x.cfg'
        '^STM32L5' = 'target/stm32l5x.cfg'
        '^STM32U5' = 'target/stm32u5x.cfg'
        '^STM32WB' = 'target/stm32wbx.cfg'
        '^STM32WL' = 'target/stm32wlx.cfg'
    }
    foreach ($entry in $mappings.GetEnumerator()) {
        if ($PartNumber -match $entry.Key) { return $entry.Value }
    }
    return 'target/stm32f4x.cfg'
}

function Get-ProgrammerName {
    param([string]$InterfaceConfig)
    switch -Regex ($InterfaceConfig) {
        'cmsis-dap' { return 'CMSIS-DAP' }
        'stlink-dap' { return 'ST-Link DAP' }
        'stlink' { return 'ST-Link' }
        'jlink' { return 'J-Link' }
        default { return '自定义烧写器' }
    }
}

Write-Host ""
Write-Host " STM32 VS Code 配置生成器 " -ForegroundColor Black -BackgroundColor Cyan
Write-Host " 将生成 launch.json、tasks.json、openocd-ui.ps1 和 stm32-openocd.json。" -ForegroundColor White
Write-Host ""

$vscodeDir = Join-Path $ProjectRoot '.vscode'
$toolsDir = Join-Path $ProjectRoot 'tools'
$template = Join-Path $toolsDir 'openocd-ui.template.ps1'
New-Item -ItemType Directory -Path $vscodeDir -Force | Out-Null

if (-not (Test-Path -LiteralPath $template)) {
    throw "缺少模板文件：$template"
}

$ioc = Get-ChildItem -LiteralPath $ProjectRoot -Filter '*.ioc' -File | Select-Object -First 1
$detectedMcu = 'STM32F407VET6'
$detectedProject = Split-Path $ProjectRoot -Leaf
if ($ioc) {
    $iocText = Get-Content -LiteralPath $ioc.FullName
    $mcuLine = $iocText | Where-Object { $_ -match '^Mcu\.CPN=' } | Select-Object -First 1
    $projectLine = $iocText | Where-Object { $_ -match '^ProjectManager\.ProjectName=' } | Select-Object -First 1
    if ($mcuLine) { $detectedMcu = ($mcuLine -split '=', 2)[1] }
    if ($projectLine) { $detectedProject = ($projectLine -split '=', 2)[1] }
}

$mcu = Read-Default '单片机型号' $detectedMcu
$projectName = Read-Default '工程名称' $detectedProject
$targetConfig = Read-Default 'OpenOCD target 配置' (Get-TargetConfig $mcu)
$interfaceConfig = Read-Default 'OpenOCD interface 配置' 'interface/cmsis-dap.cfg'

$linker = Get-ChildItem -LiteralPath $ProjectRoot -Filter '*_FLASH.ld' -File | Select-Object -First 1
if (-not $linker) { throw '未找到 *_FLASH.ld 链接脚本。' }
$linkerText = Get-Content -LiteralPath $linker.FullName -Raw
$flashMatch = [regex]::Match($linkerText, '(?m)^\s*FLASH\s*\([^)]*\)\s*:\s*ORIGIN\s*=\s*(0x[0-9A-Fa-f]+)\s*,\s*LENGTH\s*=\s*(\d+)\s*([KkMm]?)')
$ramMatch = [regex]::Match($linkerText, '(?m)^\s*RAM\s*\([^)]*\)\s*:\s*ORIGIN\s*=\s*(0x[0-9A-Fa-f]+)\s*,\s*LENGTH\s*=\s*(\d+)\s*([KkMm]?)')
$ccmMatch = [regex]::Match($linkerText, '(?m)^\s*CCMRAM\s*\([^)]*\)\s*:\s*ORIGIN\s*=\s*(0x[0-9A-Fa-f]+)\s*,\s*LENGTH\s*=\s*(\d+)\s*([KkMm]?)')
if (-not $flashMatch.Success) { throw "无法解析链接脚本中的 FLASH 区域：$($linker.Name)" }

function Length-ToBytes {
    param([string]$Number, [string]$Unit)
    $value = [long]$Number
    if ($Unit -match '[Kk]') { return $value * 1KB }
    if ($Unit -match '[Mm]') { return $value * 1MB }
    return $value
}

$detectedFlashBase = Parse-Hex $flashMatch.Groups[1].Value
$detectedFlashBytes = Length-ToBytes $flashMatch.Groups[2].Value $flashMatch.Groups[3].Value
$existingConfigPath = Join-Path $vscodeDir 'stm32-openocd.json'
$existingConfig = $null
if (Test-Path -LiteralPath $existingConfigPath) {
    try {
        $existingConfig = Get-Content -LiteralPath $existingConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $detectedFlashBase = Parse-Hex $existingConfig.memory.flashBase
        $detectedFlashBytes = [long]$existingConfig.memory.flashBytes
    } catch {
        Write-Host '警告：现有 stm32-openocd.json 无法解析，将使用链接脚本容量。' -ForegroundColor Yellow
    }
}
$flashBase = Parse-Hex (Read-Default '芯片内部 Flash 起始地址' (Hex8 $detectedFlashBase))
$flashKB = [long](Read-Default '芯片内部 Flash 总容量（KiB）' ([string]($detectedFlashBytes / 1KB)))
$flashBytes = $flashKB * 1KB
$flashEnd = $flashBase + $flashBytes - 1

Write-Host ""
Write-Host "下载区域：" -ForegroundColor Cyan
Write-Host "  D = 默认完整 Flash 区域" -ForegroundColor White
Write-Host "  C = 自定义 OTA/应用区域" -ForegroundColor White
$regionMode = (Read-Default '请选择' 'D').ToUpperInvariant()

$appBase = $flashBase
$appEnd = $flashEnd
if ($regionMode -eq 'C') {
    $appBase = Parse-Hex (Read-Default '应用区域起始地址' (Hex8 $flashBase))
    $appEnd = Parse-Hex (Read-Default '应用区域结束地址（包含）' (Hex8 $flashEnd))
}
if ($appBase -lt $flashBase -or $appEnd -gt $flashEnd -or $appEnd -lt $appBase) {
    throw "应用区域超出芯片 Flash 范围：$(Hex8 $flashBase) - $(Hex8 $flashEnd)"
}
$appBytes = $appEnd - $appBase + 1

$debugElf = Read-Default '调试 ELF 路径' "build/Debug/$projectName.elf"
Write-Host ""
Write-Host "烧写格式：E = ELF（推荐），B = BIN" -ForegroundColor Cyan
$formatChoice = (Read-Default '请选择' 'E').ToUpperInvariant()
$imageFormat = if ($formatChoice -eq 'B') { 'bin' } else { 'elf' }
$defaultImage = if ($imageFormat -eq 'bin') { "build/Debug/$projectName.bin" } else { $debugElf }
$imagePath = Read-Default '烧写固件路径' $defaultImage

if ($imageFormat -eq 'elf' -and $regionMode -eq 'C') {
    $vectorOffset = $appBase - $flashBase
    if (($vectorOffset % 0x200) -ne 0) {
        throw "应用起始地址偏移必须按 0x200 对齐，当前偏移：$(Hex8 $vectorOffset)"
    }

    Write-Host ""
    Write-Host "警告：ELF 的目标区域与当前链接脚本不同，必须同步修改 FLASH ORIGIN/LENGTH。" -ForegroundColor Yellow
    $updateLinker = (Read-Default '是否更新链接脚本并创建备份？Y/N' 'Y').ToUpperInvariant()
    if ($updateLinker -eq 'Y') {
        $backup = "$($linker.FullName).bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -LiteralPath $linker.FullName -Destination $backup
        $newFlashLine = "FLASH (rx)      : ORIGIN = $(Hex8 $appBase), LENGTH = $appBytes"
        $updated = [regex]::Replace($linkerText, '(?m)^\s*FLASH\s*\([^)]*\)\s*:\s*ORIGIN\s*=\s*0x[0-9A-Fa-f]+\s*,\s*LENGTH\s*=\s*\d+\s*[KkMm]?', $newFlashLine, 1)
        [System.IO.File]::WriteAllText($linker.FullName, $updated, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "已更新链接脚本，备份：$backup" -ForegroundColor Green

        $systemFile = Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'Core/Src') -Filter 'system_stm32*.c' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($systemFile) {
            $updateVector = (Read-Default '是否同步更新应用向量表偏移？Y/N' 'Y').ToUpperInvariant()
            if ($updateVector -eq 'Y') {
                $systemBackup = "$($systemFile.FullName).bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                Copy-Item -LiteralPath $systemFile.FullName -Destination $systemBackup
                $systemText = Get-Content -LiteralPath $systemFile.FullName -Raw
                $systemText = $systemText -replace '/\*\s*#define USER_VECT_TAB_ADDRESS\s*\*/', '#define USER_VECT_TAB_ADDRESS'
                $systemText = [regex]::Replace($systemText, '(?m)^#define VECT_TAB_OFFSET\s+0x[0-9A-Fa-f]+U', ('#define VECT_TAB_OFFSET         0x{0:X8}U' -f $vectorOffset), 1)
                [System.IO.File]::WriteAllText($systemFile.FullName, $systemText, (New-Object System.Text.UTF8Encoding($false)))
                Write-Host "已更新向量表偏移，备份：$systemBackup" -ForegroundColor Green
            }
        } else {
            Write-Host '警告：未找到 system_stm32f4xx.c，请手动配置 VTOR/向量表偏移。' -ForegroundColor Yellow
        }
    }
}

Write-Host ""
Write-Host "正在自动查找 OpenOCD 和 Arm GNU Toolchain..." -ForegroundColor Cyan

$cubeOpenOcd = ''
$cubeGdb = ''
$cubeSize = ''
$cubeScripts = ''
$cubeRoots = @(
    $env:STM32CUBEIDE_PATH
    $env:STM32CUBEIDE_HOME
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_ -PathType Container) }

foreach ($cubeRoot in $cubeRoots) {
    $plugins = Join-Path $cubeRoot 'plugins'
    if (-not (Test-Path -LiteralPath $plugins -PathType Container)) { continue }
    $openocdPlugin = Find-NewestDirectory $plugins 'com.st.stm32cube.ide.mcu.externaltools.openocd.win32_*'
    $gdbPlugin = Find-NewestDirectory $plugins 'com.st.stm32cube.ide.mcu.externaltools.gnu-tools-for-stm32.*'
    $scriptsPlugin = Find-NewestDirectory $plugins 'com.st.stm32cube.ide.mcu.debug.openocd_*'
    if ($openocdPlugin) { $cubeOpenOcd = Join-Path $openocdPlugin.FullName 'tools/bin/openocd.exe' }
    if ($gdbPlugin) {
        $cubeGdb = Join-Path $gdbPlugin.FullName 'tools/bin/arm-none-eabi-gdb.exe'
        $cubeSize = Join-Path $gdbPlugin.FullName 'tools/bin/arm-none-eabi-size.exe'
    }
    if ($scriptsPlugin) { $cubeScripts = Join-Path $scriptsPlugin.FullName 'resources/openocd/st_scripts' }
    if ($cubeOpenOcd -or $cubeGdb -or $cubeScripts) { break }
}

$openOcdEnvCandidates = @(
    $env:OPENOCD_PATH
    $env:OPENOCD_EXE
    $(if ($env:OPENOCD_PATH) { Join-Path $env:OPENOCD_PATH 'openocd.exe' })
    $(if ($env:OPENOCD_PATH) { Join-Path $env:OPENOCD_PATH 'bin/openocd.exe' })
    $(if ($env:OPENOCD_HOME) { Join-Path $env:OPENOCD_HOME 'bin/openocd.exe' })
    $(if ($env:OPENOCD_HOME) { Join-Path $env:OPENOCD_HOME 'openocd.exe' })
)
$gdbEnvCandidates = @(
    $env:ARM_GDB_PATH
    $env:ARM_NONE_EABI_GDB
    $(if ($env:GNU_ARM_EMBEDDED_TOOLCHAIN_PATH) { Join-Path $env:GNU_ARM_EMBEDDED_TOOLCHAIN_PATH 'arm-none-eabi-gdb.exe' })
    $(if ($env:GNU_ARM_EMBEDDED_TOOLCHAIN_PATH) { Join-Path $env:GNU_ARM_EMBEDDED_TOOLCHAIN_PATH 'bin/arm-none-eabi-gdb.exe' })
    $(if ($env:ARM_GCC_PATH) { Join-Path $env:ARM_GCC_PATH 'arm-none-eabi-gdb.exe' })
    $(if ($env:ARM_GCC_PATH) { Join-Path $env:ARM_GCC_PATH 'bin/arm-none-eabi-gdb.exe' })
)
$sizeEnvCandidates = @(
    $env:ARM_SIZE_PATH
    $env:ARM_NONE_EABI_SIZE
    $(if ($env:GNU_ARM_EMBEDDED_TOOLCHAIN_PATH) { Join-Path $env:GNU_ARM_EMBEDDED_TOOLCHAIN_PATH 'arm-none-eabi-size.exe' })
    $(if ($env:GNU_ARM_EMBEDDED_TOOLCHAIN_PATH) { Join-Path $env:GNU_ARM_EMBEDDED_TOOLCHAIN_PATH 'bin/arm-none-eabi-size.exe' })
    $(if ($env:ARM_GCC_PATH) { Join-Path $env:ARM_GCC_PATH 'arm-none-eabi-size.exe' })
    $(if ($env:ARM_GCC_PATH) { Join-Path $env:ARM_GCC_PATH 'bin/arm-none-eabi-size.exe' })
)

$openocdDefault = Get-FirstExistingFile (@(
    (Get-CommandPath 'openocd')
) + $openOcdEnvCandidates + @(
    $(if ($existingConfig) { $existingConfig.tools.openocd })
    $cubeOpenOcd
))
$gdbDefault = Get-FirstExistingFile (@(
    (Get-CommandPath 'arm-none-eabi-gdb')
) + $gdbEnvCandidates + @(
    $(if ($existingConfig) { $existingConfig.tools.gdb })
    $cubeGdb
))
$sizeDefault = Get-FirstExistingFile (@(
    (Get-CommandPath 'arm-none-eabi-size')
) + $sizeEnvCandidates + @(
    $(if ($existingConfig) { $existingConfig.tools.size })
    $cubeSize
))

$openocd = Read-ExistingFile 'OpenOCD 可执行文件路径' $openocdDefault
$scriptsDefault = Find-OpenOcdScripts $openocd @(
    $(if ($existingConfig) { $existingConfig.tools.scripts })
    $cubeScripts
)
$scripts = Read-ExistingDirectory 'OpenOCD scripts 目录' $scriptsDefault
$gdb = Read-ExistingFile 'arm-none-eabi-gdb 路径' $gdbDefault
$size = Read-ExistingFile 'arm-none-eabi-size 路径' $sizeDefault

$openocd = To-ForwardSlash $openocd
$scripts = To-ForwardSlash $scripts
$gdb = To-ForwardSlash $gdb
$size = To-ForwardSlash $size
if (-not (Test-Path -LiteralPath (Join-Path $scripts $interfaceConfig))) { throw "未找到 interface 配置：$interfaceConfig" }
if (-not (Test-Path -LiteralPath (Join-Path $scripts $targetConfig))) { throw "未找到 target 配置：$targetConfig" }

$ramBytes = if ($ramMatch.Success) { Length-ToBytes $ramMatch.Groups[2].Value $ramMatch.Groups[3].Value } else { 0 }
$ccmBytes = if ($ccmMatch.Success) { Length-ToBytes $ccmMatch.Groups[2].Value $ccmMatch.Groups[3].Value } else { 0 }

$config = [ordered]@{
    mcu = [ordered]@{ partNumber = $mcu }
    openocd = [ordered]@{ programmer = (Get-ProgrammerName $interfaceConfig); interface = $interfaceConfig; target = $targetConfig }
    tools = [ordered]@{ openocd = $openocd; scripts = $scripts; gdb = $gdb; size = $size }
    image = [ordered]@{ path = $imagePath; format = $imageFormat; debugElf = $debugElf; downloadAddress = (Hex8 $appBase) }
    memory = [ordered]@{
        flashBase = ('{0:X8}' -f $flashBase)
        flashBytes = $flashBytes
        appBase = ('{0:X8}' -f $appBase)
        appBytes = $appBytes
        ramBytes = $ramBytes
        ccmRamBytes = $ccmBytes
    }
}

$backupDir = Join-Path $vscodeDir ('backup/' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$existingFiles = @('launch.json', 'tasks.json', 'openocd-ui.ps1', 'stm32-openocd.json') |
    ForEach-Object { Join-Path $vscodeDir $_ } |
    Where-Object { Test-Path -LiteralPath $_ }
if ($existingFiles) {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    $existingFiles | ForEach-Object { Copy-Item -LiteralPath $_ -Destination $backupDir }
}

$config | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $vscodeDir 'stm32-openocd.json') -Encoding UTF8

$tasks = @'
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "Flash Target",
            "type": "shell",
            "command": "powershell.exe",
            "args": ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "${workspaceFolder}/.vscode/openocd-ui.ps1", "-Action", "Flash"],
            "options": { "cwd": "${workspaceFolder}" },
            "problemMatcher": [],
            "group": { "kind": "build", "isDefault": true },
            "presentation": { "echo": false, "reveal": "always", "focus": true, "panel": "dedicated", "clear": true, "showReuseMessage": false }
        },
        {
            "label": "Check Debug Target",
            "type": "shell",
            "command": "powershell.exe",
            "args": ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "${workspaceFolder}/.vscode/openocd-ui.ps1", "-Action", "Probe"],
            "options": { "cwd": "${workspaceFolder}" },
            "problemMatcher": [],
            "presentation": { "echo": false, "reveal": "always", "focus": false, "panel": "dedicated", "clear": true, "showReuseMessage": false }
        }
    ]
}
'@
[System.IO.File]::WriteAllText((Join-Path $vscodeDir 'tasks.json'), $tasks, (New-Object System.Text.UTF8Encoding($false)))

$launchObject = [ordered]@{
    version = '0.2.0'
    configurations = @(
        [ordered]@{
            name = '调试'
            cwd = '${workspaceFolder}'
            executable = '${workspaceFolder}/' + $debugElf
            request = 'launch'
            type = 'cortex-debug'
            preLaunchTask = 'Check Debug Target'
            servertype = 'openocd'
            configFiles = @($interfaceConfig, $targetConfig)
            serverpath = $openocd
            searchDir = @($scripts)
            runToEntryPoint = 'main'
            showDevDebugOutput = 'none'
            gdbPath = $gdb
            liveWatch = [ordered]@{ enabled = $true; samplesPerSecond = 4 }
        }
    )
}
$launchObject | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $vscodeDir 'launch.json') -Encoding UTF8
Copy-Item -LiteralPath $template -Destination (Join-Path $vscodeDir 'openocd-ui.ps1') -Force

Write-Host ""
Write-Host "生成完成：" -ForegroundColor Green
Write-Host " MCU      : $mcu"
Write-Host " Target   : $targetConfig"
Write-Host " Image    : $imagePath ($imageFormat)"
Write-Host " App range: $(Hex8 $appBase) - $(Hex8 $appEnd) ($([Math]::Round($appBytes / 1KB, 1)) KiB)"
Write-Host " OpenOCD  : $openocd"
Write-Host " Scripts  : $scripts"
Write-Host " GDB      : $gdb"
Write-Host ""
if ($regionMode -eq 'C') {
    Write-Host "OTA 提醒：还需要由 Bootloader 跳转到应用入口，并确保 VTOR 指向应用向量表。" -ForegroundColor Yellow
}
if ($imageFormat -eq 'bin') {
    Write-Host "BIN 提醒：下载地址只控制原始数据写入位置，生成 BIN 的工程仍必须按应用地址正确链接。" -ForegroundColor Yellow
}
