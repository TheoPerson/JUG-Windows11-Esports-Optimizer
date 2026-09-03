#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$AuditOnly,
    [switch]$NoReboot,
    [switch]$Restore,
    [string]$BackupPath
)

$ErrorActionPreference = 'Stop'
$Root = Join-Path $env:ProgramData 'JUG-Optimizer'
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Backup = if ($BackupPath) { $BackupPath } else { Join-Path $Root ('Backup\' + $Stamp) }

function Section([string]$Title) { Write-Host "`n=== $Title ===" -ForegroundColor Cyan }
function Ok([string]$Text) { Write-Host ('[OK]   ' + $Text) -ForegroundColor Green }
function Skip([string]$Text) { Write-Host ('[SKIP] ' + $Text) -ForegroundColor Yellow }
function IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Ask([string]$Question) {
    while ($true) {
        $r = Read-Host ($Question + ' [Y/N]')
        if ($r -match '^[Yy]$') { return $true }
        if ($r -match '^[Nn]$') { return $false }
    }
}
function Safe([string]$Name,[scriptblock]$Action) {
    try { & $Action; Ok $Name }
    catch { Skip ($Name + ' :: ' + $_.Exception.Message) }
}
function RegBackup([string]$Key,[string]$Name) {
    $dest = Join-Path $Backup $Name
    & reg.exe export $Key $dest /y | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $dest)) { throw ('Registry export failed: ' + $Key) }
    return $dest
}
function SetDword([string]$Path,[string]$Name,[int]$Value) {
    if (-not (Test-Path $Path)) { New-Item $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
}
function FeatureEnabled([string]$Name) {
    try { return ((Get-WindowsOptionalFeature -Online -FeatureName $Name -ErrorAction Stop).State -eq 'Enabled') }
    catch { return $false }
}
function DetectWorkloads {
    [ordered]@{
        WSL = [bool](Get-Command wsl.exe -ErrorAction SilentlyContinue)
        VMP = FeatureEnabled 'VirtualMachinePlatform'
        HyperV = FeatureEnabled 'Microsoft-Hyper-V-All'
        Xbox = [bool](Get-AppxPackage -AllUsers Microsoft.GamingApp -ErrorAction SilentlyContinue)
        Store = [bool](Get-AppxPackage -AllUsers Microsoft.WindowsStore -ErrorAction SilentlyContinue)
        AndroidStudio = [bool](Get-Process studio64 -ErrorAction SilentlyContinue)
        AnyDesk = [bool](Get-Service AnyDesk -ErrorAction SilentlyContinue)
        NordVPN = [bool](Get-Service -Name 'NordVPN*' -ErrorAction SilentlyContinue)
        Bluetooth = [bool](Get-Service bthserv -ErrorAction SilentlyContinue)
    }
}
function BackupService([string]$Name) {
    $s = Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f $Name) -ErrorAction SilentlyContinue
    if ($s) {
        $s | Select-Object Name,StartMode,State | ConvertTo-Json | Set-Content (Join-Path $Backup ('service-' + $Name + '.json')) -Encoding UTF8
    }
}
function DisableServiceSafe([string]$Name) {
    $s = Get-Service $Name -ErrorAction SilentlyContinue
    if ($s) {
        BackupService $Name
        Set-Service -Name $Name -StartupType Disabled
        Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
    }
}
function RestoreService([object]$Entry) {
    if (-not $Entry) { return }
    $mode = switch ([string]$Entry.StartMode) {
        'Auto' { 'Automatic'; break }
        'Automatic' { 'Automatic'; break }
        'Manual' { 'Manual'; break }
        'Disabled' { 'Disabled'; break }
        default { 'Manual' }
    }
    if (Get-Service $Entry.Name -ErrorAction SilentlyContinue) {
        Set-Service -Name $Entry.Name -StartupType $mode -ErrorAction SilentlyContinue
    }
}

try {
    New-Item -Path $Backup -ItemType Directory -Force | Out-Null
    $Log = Join-Path $Backup 'optimizer.log'
    function Log([string]$Text) { ((Get-Date -Format s) + ' ' + $Text) | Add-Content $Log -Encoding UTF8 }

    if (-not (IsAdmin)) { throw 'Administrator privileges are required. Launch PowerShell as Administrator.' }

    if ($Restore) {
        if (-not $BackupPath) { throw '-Restore requires -BackupPath.' }
        $manifestPath = Join-Path $BackupPath 'manifest.json'
        if (-not (Test-Path $manifestPath)) { throw ('Manifest not found: ' + $manifestPath) }
        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
        foreach ($reg in @($manifest.Registry)) {
            if ($reg -and (Test-Path $reg)) { & reg.exe import $reg | Out-Null }
        }
        foreach ($svc in @($manifest.Services)) { RestoreService $svc }
        if ($manifest.OriginalPowerScheme) { powercfg /setactive $manifest.OriginalPowerScheme | Out-Null }
        Write-Host ('Restore complete: ' + $BackupPath) -ForegroundColor Green
        exit 0
    }

    Section 'JUG Windows 11 Esports Optimizer'
    Write-Host ('PowerShell: ' + $PSVersionTable.PSVersion)
    Write-Host ('CPU: ' + (Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Name))
    $gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA|AMD|Intel' } | Select-Object -First 1 -ExpandProperty Name
    Write-Host ('GPU: ' + $gpu)
    Write-Host ('Windows: ' + [Environment]::OSVersion.Version)

    $workloads = DetectWorkloads
    Section 'Protected workload detection'
    foreach ($item in $workloads.GetEnumerator()) {
        $state = if ($item.Value) { 'DETECTED' } else { 'not detected' }
        Write-Host ('{0,-18} {1}' -f $item.Key,$state)
    }

    if ($AuditOnly) {
        Write-Host "`nAUDIT ONLY - no changes applied." -ForegroundColor Cyan
        exit 0
    }

    Section 'Profile decisions'
    $search = Ask 'Disable Windows Search indexing?'
    $sysmain = Ask 'Disable SysMain?'
    $vbs = Ask 'Disable VBS/HVCI/Memory Integrity? (reduced security hardening)'
    $delivery = Ask 'Disable Delivery Optimization peer-to-peer?'
    $telemetry = Ask 'Disable selected telemetry services/tasks?'
    $startup = Ask 'Apply targeted startup cleanup?'
    $nic = Ask 'Apply supported NIC latency/power settings?'
    if (-not (Ask 'Apply selected changes now?')) { Write-Host 'Cancelled.' -ForegroundColor Yellow; exit 0 }

    $registry = @()
    $services = @()
    $originalPower = ([regex]::Match((powercfg /getactivescheme | Out-String),'[0-9a-fA-F-]{36}')).Value
    $appliedPower = $null

    Section 'Backup'
    $keys = @(
        'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects',
        'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize',
        'HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR',
        'HKCU\System\GameConfigStore',
        'HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR'
    )
    foreach ($key in $keys) {
        try { $registry += RegBackup $key ((($key -replace '[\\:]','_') + '.reg')) } catch { Log ('Registry backup skipped: ' + $key) }
    }

    Safe 'Performance power scheme' {
        $ultimate = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
        if ((powercfg /list | Out-String) -match $ultimate) {
            $appliedPower = $ultimate
        } else {
            $created = powercfg -duplicatescheme $ultimate 2>&1 | Out-String
            $appliedPower = ([regex]::Matches($created,'[0-9a-fA-F-]{36}') | Select-Object -Last 1).Value
        }
        if (-not $appliedPower) { throw 'Unable to create or locate Ultimate Performance.' }
        powercfg /setactive $appliedPower | Out-Null
    }

    Safe 'Game DVR background capture reduction' {
        SetDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
        SetDword 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
        SetDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0
    }

    Safe 'Visual overhead reduction' {
        SetDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0
        SetDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 2
    }

    Safe 'Background application restriction' {
        SetDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1
    }

    Safe 'Consumer surface reduction' {
        SetDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
        SetDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SilentInstalledAppsEnabled' 0
        SetDword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338388Enabled' 0
    }

    if ($search) { Safe 'Disable Windows Search' { DisableServiceSafe 'WSearch' } }
    if ($sysmain) { Safe 'Disable SysMain' { DisableServiceSafe 'SysMain' } }

    if ($vbs) {
        Safe 'Disable VBS/HVCI' {
            $registry += RegBackup 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'deviceguard.reg'
            $registry += RegBackup 'HKLM\SYSTEM\CurrentControlSet\Control\Lsa' 'lsa.reg'
            SetDword 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' 0
            SetDword 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'LsaCfgFlags' 0
            SetDword 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 0
        }
    }

    if ($delivery) {
        Safe 'Delivery Optimization HTTP-only mode' {
            SetDword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0
        }
    }

    if ($telemetry) {
        foreach ($name in @('DiagTrack','dmwappushservice')) {
            Safe ('Disable ' + $name) { DisableServiceSafe $name }
        }
        $tasks = @(
            '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
            '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
            '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
            '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
            '\Microsoft\Windows\Feedback\Siuf\DmClient'
        )
        foreach ($fullName in $tasks) {
            try {
                $path = Split-Path $fullName
                $name = Split-Path $fullName -Leaf
                Disable-ScheduledTask -TaskPath $path -TaskName $name -ErrorAction Stop | Out-Null
            } catch { Log ('Task skipped: ' + $fullName) }
        }
    }

    if ($startup) {
        Safe 'Targeted startup cleanup' {
            $runKeys = @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run')
            foreach ($runKey in $runKeys) {
                if (-not (Test-Path $runKey)) { continue }
                $props = Get-ItemProperty $runKey
                foreach ($prop in $props.PSObject.Properties) {
                    if ($prop.Name -match '^PS') { continue }
                    if ($prop.Name -match 'Teams|MicrosoftTeams|GoogleUpdate|AdobeGCInvoker') {
                        Remove-ItemProperty -Path $runKey -Name $prop.Name -ErrorAction SilentlyContinue
                    }
                }
            }
        }
    }

    if ($nic) {
        Safe 'Hardware-aware NIC tuning' {
            $adapters = Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' }
            foreach ($adapter in $adapters) {
                try { Set-NetAdapterRss -Name $adapter.Name -Enabled $true -ErrorAction SilentlyContinue } catch {}
                try { Set-NetAdapterPowerManagement -Name $adapter.Name -SelectiveSuspend Disabled -ErrorAction SilentlyContinue } catch {}
                $props = Get-NetAdapterAdvancedProperty -Name $adapter.Name -ErrorAction SilentlyContinue
                foreach ($displayName in @('Energy Efficient Ethernet','Green Ethernet','Interrupt Moderation','Packet Coalescing')) {
                    $prop = $props | Where-Object { $_.DisplayName -eq $displayName } | Select-Object -First 1
                    if ($prop) { try { Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName $displayName -DisplayValue Disabled -NoRestart -ErrorAction Stop } catch { Log ('NIC property skipped: ' + $displayName) } }
                }
            }
        }
    }

    Safe 'BCD and pagefile audit' {
        bcdedit /enum all | Out-File (Join-Path $Backup 'bcd-audit.txt') -Encoding UTF8
        Get-CimInstance Win32_ComputerSystem | Select-Object AutomaticManagedPagefile | ConvertTo-Json | Set-Content (Join-Path $Backup 'pagefile-audit.json') -Encoding UTF8
    }

    $serviceFiles = Get-ChildItem $Backup -Filter 'service-*.json' -ErrorAction SilentlyContinue
    foreach ($file in $serviceFiles) { $services += Get-Content $file.FullName -Raw | ConvertFrom-Json }
    [ordered]@{ Created=(Get-Date).ToString('o'); OriginalPowerScheme=$originalPower; AppliedPowerScheme=$appliedPower; Registry=@($registry); Services=@($services) } |
        ConvertTo-Json -Depth 8 | Set-Content (Join-Path $Backup 'manifest.json') -Encoding UTF8
    Log 'Completed successfully.'

    Write-Host "`nDONE" -ForegroundColor Green
    Write-Host ('Backup: ' + $Backup) -ForegroundColor Cyan
    if (-not $NoReboot) { if (Ask 'Restart now?') { Restart-Computer -Force } }
}
catch {
    Write-Host "`nFATAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
    if ($Log) { Log ('FATAL: ' + $_.Exception.ToString()) }
    Write-Host ('Backup/log: ' + $Backup) -ForegroundColor Yellow
    Read-Host 'Press Enter to close'
    exit 1
}
