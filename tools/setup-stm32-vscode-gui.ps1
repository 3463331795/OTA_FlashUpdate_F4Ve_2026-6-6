param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Read-JsonConfig {
    $path = Join-Path $ProjectRoot '.vscode/stm32-openocd.json'
    if (Test-Path -LiteralPath $path) {
        try { return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    }
    return $null
}

function Get-IocValue {
    param([string]$Key, [string]$Default)
    $ioc = Get-ChildItem -LiteralPath $ProjectRoot -Filter '*.ioc' -File | Select-Object -First 1
    if (-not $ioc) { return $Default }
    $line = Get-Content -LiteralPath $ioc.FullName | Where-Object { $_ -match "^$([regex]::Escape($Key))=" } | Select-Object -First 1
    if ($line) { return ($line -split '=', 2)[1] }
    return $Default
}

function Get-TargetConfig {
    param([string]$Mcu)
    $map = [ordered]@{
        '^STM32F0'='target/stm32f0x.cfg'; '^STM32F1'='target/stm32f1x.cfg'; '^STM32F2'='target/stm32f2x.cfg'
        '^STM32F3'='target/stm32f3x.cfg'; '^STM32F4'='target/stm32f4x.cfg'; '^STM32F7'='target/stm32f7x.cfg'
        '^STM32H7'='target/stm32h7x.cfg'; '^STM32G0'='target/stm32g0x.cfg'; '^STM32G4'='target/stm32g4x.cfg'
        '^STM32L0'='target/stm32l0.cfg'; '^STM32L1'='target/stm32l1.cfg'; '^STM32L4'='target/stm32l4x.cfg'
        '^STM32L5'='target/stm32l5x.cfg'; '^STM32U5'='target/stm32u5x.cfg'; '^STM32WB'='target/stm32wbx.cfg'
        '^STM32WL'='target/stm32wlx.cfg'
    }
    foreach ($item in $map.GetEnumerator()) { if ($Mcu -match $item.Key) { return $item.Value } }
    return 'target/stm32f4x.cfg'
}

function Get-CommandPath([string]$Name) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        if ($command.Path) { return $command.Path }
        if ($command.Source) { return $command.Source }
    }
    return ''
}

function Get-FirstFile([string[]]$Candidates) {
    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return (Resolve-Path -LiteralPath $candidate).Path }
    }
    return ''
}

function Get-FirstFolder([string[]]$Candidates) {
    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Container)) { return (Resolve-Path -LiteralPath $candidate).Path }
    }
    return ''
}

function Find-NewestFolder([string]$Root, [string]$Filter) {
    if (-not $Root -or -not (Test-Path -LiteralPath $Root -PathType Container)) { return $null }
    return Get-ChildItem -LiteralPath $Root -Directory -Filter $Filter | Sort-Object Name -Descending | Select-Object -First 1
}

function Add-Row {
    param(
        [System.Windows.Forms.TableLayoutPanel]$Table,
        [string]$Label,
        [System.Windows.Forms.Control]$Control,
        [System.Windows.Forms.Control]$Button = $null
    )
    $row = $Table.RowCount
    $Table.RowCount++
    [void]$Table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $labelControl = New-Object System.Windows.Forms.Label
    $labelControl.Text = $Label
    $labelControl.AutoSize = $true
    $labelControl.Anchor = 'Left'
    $labelControl.Margin = '3,8,8,3'
    $Control.Dock = 'Fill'
    $Control.Margin = '3,4,3,4'
    [void]$Table.Controls.Add($labelControl, 0, $row)
    [void]$Table.Controls.Add($Control, 1, $row)
    if ($Button) {
        $Button.AutoSize = $true
        [void]$Table.Controls.Add($Button, 2, $row)
    }
}

function New-TextBox([string]$Text) {
    $box = New-Object System.Windows.Forms.TextBox
    $box.Text = $Text
    return $box
}

function New-BrowseFileButton([System.Windows.Forms.TextBox]$TextBox, [string]$Filter) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = '浏览...'
    $button.Add_Click({
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Filter = $Filter
        if ($TextBox.Text -and (Test-Path -LiteralPath $TextBox.Text)) { $dialog.FileName = $TextBox.Text }
        if ($dialog.ShowDialog() -eq 'OK') { $TextBox.Text = $dialog.FileName }
    }.GetNewClosure())
    return $button
}

function New-BrowseFolderButton([System.Windows.Forms.TextBox]$TextBox) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = '浏览...'
    $button.Add_Click({
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        if ($TextBox.Text -and (Test-Path -LiteralPath $TextBox.Text)) { $dialog.SelectedPath = $TextBox.Text }
        if ($dialog.ShowDialog() -eq 'OK') { $TextBox.Text = $dialog.SelectedPath }
    }.GetNewClosure())
    return $button
}

$config = Read-JsonConfig
$mcuDefault = Get-IocValue 'Mcu.CPN' 'STM32F407VET6'
$projectDefault = Get-IocValue 'ProjectManager.ProjectName' (Split-Path $ProjectRoot -Leaf)
$targetDefault = if ($config) { $config.openocd.target } else { Get-TargetConfig $mcuDefault }
$interfaceDefault = if ($config) { $config.openocd.interface } else { 'interface/cmsis-dap.cfg' }
$programmerDefault = if ($config -and $config.openocd.programmer) {
    if ($config.openocd.programmer -eq 'CMSIS-DAP') { 'CMSIS-DAP / DAPLink' }
    elseif ($config.openocd.programmer -eq '自定义烧写器') { '自定义 OpenOCD Interface' }
    else { $config.openocd.programmer }
} else { 'CMSIS-DAP / DAPLink' }
$flashBaseDefault = if ($config) { '0x' + $config.memory.flashBase } else { '0x08000000' }
$flashKbDefault = if ($config) { [string]([long]$config.memory.flashBytes / 1KB) } else { '512' }
$appBaseDefault = if ($config) { '0x' + $config.memory.appBase } else { $flashBaseDefault }
$appEndDefault = if ($config) { '0x{0:X8}' -f ([Convert]::ToInt64($config.memory.appBase,16) + [long]$config.memory.appBytes - 1) } else { '0x0807FFFF' }
$debugElfDefault = if ($config -and $config.image.debugElf) {
    $config.image.debugElf
} elseif ($config -and $config.image.format -eq 'elf') {
    $config.image.path
} else {
    "build/Debug/$projectDefault.elf"
}
$imageDefault = if ($config) { $config.image.path } else { $debugElfDefault }
$formatDefault = if ($config) { $config.image.format.ToUpperInvariant() } else { 'ELF' }
$cubeOpenOcd = ''
$cubeGdb = ''
$cubeSize = ''
$cubeScripts = ''
$cubeRootCandidates = @($env:STM32CUBEIDE_PATH, $env:STM32CUBEIDE_HOME)
foreach ($cubeRoot in $cubeRootCandidates) {
    $plugins = if ($cubeRoot) { Join-Path $cubeRoot 'plugins' } else { '' }
    if (-not $plugins -or -not (Test-Path -LiteralPath $plugins -PathType Container)) { continue }
    $openocdPlugin = Find-NewestFolder $plugins 'com.st.stm32cube.ide.mcu.externaltools.openocd.win32_*'
    $gdbPlugin = Find-NewestFolder $plugins 'com.st.stm32cube.ide.mcu.externaltools.gnu-tools-for-stm32.*'
    $scriptsPlugin = Find-NewestFolder $plugins 'com.st.stm32cube.ide.mcu.debug.openocd_*'
    if ($openocdPlugin) { $cubeOpenOcd = Join-Path $openocdPlugin.FullName 'tools/bin/openocd.exe' }
    if ($gdbPlugin) {
        $cubeGdb = Join-Path $gdbPlugin.FullName 'tools/bin/arm-none-eabi-gdb.exe'
        $cubeSize = Join-Path $gdbPlugin.FullName 'tools/bin/arm-none-eabi-size.exe'
    }
    if ($scriptsPlugin) { $cubeScripts = Join-Path $scriptsPlugin.FullName 'resources/openocd/st_scripts' }
    break
}
$openocdDefault = Get-FirstFile @(
    (Get-CommandPath 'openocd'), $env:OPENOCD_EXE, $env:OPENOCD_PATH,
    $(if ($env:OPENOCD_PATH) { Join-Path $env:OPENOCD_PATH 'bin/openocd.exe' }),
    $(if ($config) { $config.tools.openocd }), $cubeOpenOcd
)
$gdbDefault = Get-FirstFile @(
    (Get-CommandPath 'arm-none-eabi-gdb'), $env:ARM_GDB_PATH,
    $(if ($env:GNU_ARM_EMBEDDED_TOOLCHAIN_PATH) { Join-Path $env:GNU_ARM_EMBEDDED_TOOLCHAIN_PATH 'bin/arm-none-eabi-gdb.exe' }),
    $(if ($env:ARM_GCC_PATH) { Join-Path $env:ARM_GCC_PATH 'arm-none-eabi-gdb.exe' }),
    $(if ($env:ARM_GCC_PATH) { Join-Path $env:ARM_GCC_PATH 'bin/arm-none-eabi-gdb.exe' }),
    $(if ($config) { $config.tools.gdb }), $cubeGdb
)
$sizeDefault = Get-FirstFile @(
    (Get-CommandPath 'arm-none-eabi-size'), $env:ARM_SIZE_PATH,
    $(if ($env:GNU_ARM_EMBEDDED_TOOLCHAIN_PATH) { Join-Path $env:GNU_ARM_EMBEDDED_TOOLCHAIN_PATH 'bin/arm-none-eabi-size.exe' }),
    $(if ($env:ARM_GCC_PATH) { Join-Path $env:ARM_GCC_PATH 'arm-none-eabi-size.exe' }),
    $(if ($env:ARM_GCC_PATH) { Join-Path $env:ARM_GCC_PATH 'bin/arm-none-eabi-size.exe' }),
    $(if ($config) { $config.tools.size }), $cubeSize
)
$openocdDir = if ($openocdDefault) { Split-Path -Parent $openocdDefault } else { '' }
$scriptsDefault = Get-FirstFolder @(
    $env:OPENOCD_SCRIPTS, $env:OPENOCD_SCRIPT_DIR,
    $(if ($openocdDir) { Join-Path $openocdDir '../share/openocd/scripts' }),
    $(if ($openocdDir) { Join-Path $openocdDir '../scripts' }),
    $(if ($config) { $config.tools.scripts }), $cubeScripts
)

$form = New-Object System.Windows.Forms.Form
$form.Text = 'STM32 VS Code 配置生成器'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(940, 850)
$form.MinimumSize = New-Object System.Drawing.Size(820, 650)
$form.Font = [System.Windows.Forms.SystemInformation]::MenuFont

$rootPanel = New-Object System.Windows.Forms.TableLayoutPanel
$rootPanel.Dock = 'Fill'
$rootPanel.ColumnCount = 1
$rootPanel.RowCount = 3
[void]$rootPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$rootPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$rootPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$form.Controls.Add($rootPanel)

$header = New-Object System.Windows.Forms.Label
$header.Text = "项目：$ProjectRoot`r`n自动识别项目、选择烧写器并生成 VS Code 调试/下载配置"
$header.AutoSize = $true
$header.Padding = '12,12,12,8'
$header.Font = New-Object System.Drawing.Font($form.Font.FontFamily, 11, [System.Drawing.FontStyle]::Bold)
[void]$rootPanel.Controls.Add($header, 0, 0)

$scroll = New-Object System.Windows.Forms.Panel
$scroll.Dock = 'Fill'
$scroll.AutoScroll = $true
[void]$rootPanel.Controls.Add($scroll, 0, 1)

$table = New-Object System.Windows.Forms.TableLayoutPanel
$table.Dock = 'Top'
$table.AutoSize = $true
$table.ColumnCount = 3
[void]$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 170)))
[void]$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
$table.Padding = '12,4,12,8'
[void]$scroll.Controls.Add($table)

$mcuBox = New-TextBox $mcuDefault
$projectBox = New-TextBox $projectDefault
$targetBox = New-TextBox $targetDefault
$programmerBox = New-Object System.Windows.Forms.ComboBox
$programmerBox.DropDownStyle = 'DropDownList'
[void]$programmerBox.Items.AddRange(@('CMSIS-DAP / DAPLink','ST-Link','ST-Link DAP','J-Link','自定义 OpenOCD Interface'))
$programmerBox.SelectedItem = $programmerDefault
if ($programmerBox.SelectedIndex -lt 0) { $programmerBox.SelectedIndex = 0 }
$interfaceBox = New-TextBox $interfaceDefault
$flashBaseBox = New-TextBox $flashBaseDefault
$flashKbBox = New-TextBox $flashKbDefault
$regionBox = New-Object System.Windows.Forms.ComboBox
$regionBox.DropDownStyle = 'DropDownList'
[void]$regionBox.Items.AddRange(@('默认完整 Flash 区域','自定义 OTA / 应用区域'))
$regionBox.SelectedIndex = if ($appBaseDefault -eq $flashBaseDefault) { 0 } else { 1 }
$appBaseBox = New-TextBox $appBaseDefault
$appEndBox = New-TextBox $appEndDefault
$debugElfBox = New-TextBox $debugElfDefault
$formatBox = New-Object System.Windows.Forms.ComboBox
$formatBox.DropDownStyle = 'DropDownList'
[void]$formatBox.Items.AddRange(@('ELF','BIN'))
$formatBox.SelectedItem = $formatDefault
$imageBox = New-TextBox $imageDefault
$updateLinkerCheck = New-Object System.Windows.Forms.CheckBox
$updateLinkerCheck.Text = '自定义 ELF 区域时更新链接脚本'
$updateLinkerCheck.Checked = $true
$updateVectorCheck = New-Object System.Windows.Forms.CheckBox
$updateVectorCheck.Text = '同步更新应用向量表偏移'
$updateVectorCheck.Checked = $true
$openocdBox = New-TextBox $openocdDefault
$scriptsBox = New-TextBox $scriptsDefault
$gdbBox = New-TextBox $gdbDefault
$sizeBox = New-TextBox $sizeDefault

Add-Row $table '单片机型号' $mcuBox
Add-Row $table '工程名称' $projectBox
Add-Row $table '烧写器' $programmerBox
Add-Row $table 'OpenOCD interface' $interfaceBox
Add-Row $table 'OpenOCD target' $targetBox
Add-Row $table '芯片 Flash 起始地址' $flashBaseBox
Add-Row $table '芯片 Flash 总容量（KiB）' $flashKbBox
Add-Row $table '下载区域' $regionBox
Add-Row $table '应用区域起始地址' $appBaseBox
Add-Row $table '应用区域结束地址（包含）' $appEndBox
Add-Row $table '调试 ELF 路径' $debugElfBox
Add-Row $table '烧写格式' $formatBox
Add-Row $table '烧写固件路径' $imageBox
Add-Row $table '链接脚本' $updateLinkerCheck
Add-Row $table '向量表' $updateVectorCheck
Add-Row $table 'OpenOCD 可执行文件' $openocdBox (New-BrowseFileButton $openocdBox 'OpenOCD|openocd.exe;openocd.cmd|所有文件|*.*')
Add-Row $table 'OpenOCD scripts 目录' $scriptsBox (New-BrowseFolderButton $scriptsBox)
Add-Row $table 'arm-none-eabi-gdb' $gdbBox (New-BrowseFileButton $gdbBox 'GDB|arm-none-eabi-gdb.exe;arm-none-eabi-gdb.cmd|所有文件|*.*')
Add-Row $table 'arm-none-eabi-size' $sizeBox (New-BrowseFileButton $sizeBox 'Size|arm-none-eabi-size.exe;arm-none-eabi-size.cmd|所有文件|*.*')

$programmerMap = @{
    'CMSIS-DAP / DAPLink' = 'interface/cmsis-dap.cfg'
    'ST-Link' = 'interface/stlink.cfg'
    'ST-Link DAP' = 'interface/stlink-dap.cfg'
    'J-Link' = 'interface/jlink.cfg'
}
$programmerBox.Add_SelectedIndexChanged({
    if ($programmerMap.ContainsKey($programmerBox.SelectedItem)) {
        $interfaceBox.Text = $programmerMap[$programmerBox.SelectedItem]
        $interfaceBox.ReadOnly = $true
    } else {
        $interfaceBox.ReadOnly = $false
    }
})
$mcuBox.Add_Leave({ $targetBox.Text = Get-TargetConfig $mcuBox.Text })
$regionBox.Add_SelectedIndexChanged({
    $custom = $regionBox.SelectedIndex -eq 1
    $appBaseBox.Enabled = $custom
    $appEndBox.Enabled = $custom
    $updateLinkerCheck.Enabled = $custom -and $formatBox.SelectedItem -eq 'ELF'
    $updateVectorCheck.Enabled = $updateLinkerCheck.Enabled
})
$formatBox.Add_SelectedIndexChanged({
    if ($formatBox.SelectedItem -eq 'ELF') {
        $imageBox.Text = $debugElfBox.Text
    } elseif ($imageBox.Text -match '\.elf$') {
        $imageBox.Text = $imageBox.Text -replace '\.elf$', '.bin'
    }
    $updateLinkerCheck.Enabled = $regionBox.SelectedIndex -eq 1 -and $formatBox.SelectedItem -eq 'ELF'
    $updateVectorCheck.Enabled = $updateLinkerCheck.Enabled
})
if ($programmerMap.ContainsKey($programmerBox.SelectedItem)) {
    $interfaceBox.Text = $programmerMap[$programmerBox.SelectedItem]
    $interfaceBox.ReadOnly = $true
}
$customRegion = $regionBox.SelectedIndex -eq 1
$appBaseBox.Enabled = $customRegion
$appEndBox.Enabled = $customRegion
$updateLinkerCheck.Enabled = $customRegion -and $formatBox.SelectedItem -eq 'ELF'
$updateVectorCheck.Enabled = $updateLinkerCheck.Enabled

$buttons = New-Object System.Windows.Forms.FlowLayoutPanel
$buttons.Dock = 'Fill'
$buttons.FlowDirection = 'RightToLeft'
$buttons.AutoSize = $true
$buttons.Padding = New-Object System.Windows.Forms.Padding(8)
[void]$rootPanel.Controls.Add($buttons, 0, 2)

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = '取消'
$cancelButton.AutoSize = $true
$cancelButton.Add_Click({ $form.Close() })
[void]$buttons.Controls.Add($cancelButton)

$generateButton = New-Object System.Windows.Forms.Button
$generateButton.Text = '生成配置'
$generateButton.AutoSize = $true
$generateButton.BackColor = [System.Drawing.Color]::FromArgb(0, 122, 204)
$generateButton.ForeColor = [System.Drawing.Color]::White
[void]$buttons.Controls.Add($generateButton)

$generateButton.Add_Click({
    try {
        $required = @($mcuBox,$projectBox,$interfaceBox,$targetBox,$flashBaseBox,$flashKbBox,$debugElfBox,$imageBox,$openocdBox,$scriptsBox,$gdbBox,$sizeBox)
        if ($required | Where-Object { [string]::IsNullOrWhiteSpace($_.Text) }) { throw '请填写所有必填字段。' }
        if (-not (Test-Path -LiteralPath $openocdBox.Text -PathType Leaf)) { throw 'OpenOCD 可执行文件路径无效。' }
        if (-not (Test-Path -LiteralPath $scriptsBox.Text -PathType Container)) { throw 'OpenOCD scripts 目录无效。' }
        if (-not (Test-Path -LiteralPath $gdbBox.Text -PathType Leaf)) { throw 'GDB 路径无效。' }
        if (-not (Test-Path -LiteralPath $sizeBox.Text -PathType Leaf)) { throw 'Size 工具路径无效。' }

        $regionChoice = if ($regionBox.SelectedIndex -eq 1) { 'C' } else { 'D' }
        $formatChoice = if ($formatBox.SelectedItem -eq 'BIN') { 'B' } else { 'E' }
        $global:GuiAnswerQueue = [System.Collections.Generic.Queue[string]]::new()
        @($mcuBox.Text,$projectBox.Text,$targetBox.Text,$interfaceBox.Text,$flashBaseBox.Text,$flashKbBox.Text,$regionChoice) | ForEach-Object { $global:GuiAnswerQueue.Enqueue($_) }
        if ($regionChoice -eq 'C') { $global:GuiAnswerQueue.Enqueue($appBaseBox.Text); $global:GuiAnswerQueue.Enqueue($appEndBox.Text) }
        @($debugElfBox.Text,$formatChoice,$imageBox.Text) | ForEach-Object { $global:GuiAnswerQueue.Enqueue($_) }
        if ($regionChoice -eq 'C' -and $formatChoice -eq 'E') {
            $global:GuiAnswerQueue.Enqueue($(if ($updateLinkerCheck.Checked) { 'Y' } else { 'N' }))
            if ($updateLinkerCheck.Checked) { $global:GuiAnswerQueue.Enqueue($(if ($updateVectorCheck.Checked) { 'Y' } else { 'N' })) }
        }
        @($openocdBox.Text,$scriptsBox.Text,$gdbBox.Text,$sizeBox.Text) | ForEach-Object { $global:GuiAnswerQueue.Enqueue($_) }

        function global:Read-Host {
            param([string]$Prompt)
            if ($global:GuiAnswerQueue.Count -eq 0) { throw "图形界面缺少后端参数：$Prompt" }
            return $global:GuiAnswerQueue.Dequeue()
        }
        $oldLocation = Get-Location
        try {
            & (Join-Path $PSScriptRoot 'setup-stm32-vscode.ps1') -ProjectRoot $ProjectRoot *>&1 | Out-Null
        } finally {
            Set-Location $oldLocation
            Remove-Item function:\Read-Host -ErrorAction SilentlyContinue
            Remove-Variable GuiAnswerQueue -Scope Global -ErrorAction SilentlyContinue
        }
        [System.Windows.Forms.MessageBox]::Show('VS Code 调试和烧写配置已生成。', '生成成功', 'OK', 'Information') | Out-Null
        $form.Close()
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '生成失败', 'OK', 'Error') | Out-Null
    }
})

if ($ValidateOnly) {
    Write-Output 'GUI validation OK'
    exit 0
}
[void]$form.ShowDialog()
