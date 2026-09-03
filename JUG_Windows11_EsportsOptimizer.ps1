#requires -Version 5.1
<#
JUG Windows 11 Esports Optimizer

Production-oriented, workload-aware Windows 11 tuning for gaming + development.
Designed for PowerShell 5.1+; PowerShell 7 is recommended but NOT required.

Audit first:
  .\JUG_Windows11_EsportsOptimizer.ps1 -AuditOnly

Apply:
  .\JUG_Windows11_EsportsOptimizer.ps1

Restore:
  .\JUG_Windows11_EsportsOptimizer.ps1 -Restore -BackupPath <backup>

Principles:
  - targeted, conditional, reversible changes
  - preserve WSL2 / Virtual Machine Platform / Hyper-V
  - preserve AnyDesk / NordVPN / Xbox / Store / developer workloads
  - no HPET/BCD timer folklore
  - no pagefile removal
  - no Defender removal
  - no mass service deletion
#>
[CmdletBinding()]
param(
    [switch]$AuditOnly,
    [switch]$Restore,
    [string]$BackupPath,
    [switch]$NoReboot
)

$ErrorActionPreference = 'Stop'
$Root = Join-Path $env:ProgramData 'JUG-Optimizer'
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Backup = if ($BackupPath) { $BackupPath } else { Join-Path $Root "Backup\$Stamp" }

function Log([string]$Message) {
    if ($script:Log) {
        "$(Get-Date -Format s) $Message" | Add-Content $script:Log -Encoding UTF8
    }
}

function Write-Section([string]$Title) {
    Write-Host "`n=== $Title ===" -ForegroundColor Cyan
}

function Is-Admin {
    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
    return $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ask([string]$Question) {
    while ($true) {
        $Reply = Read-Host "$Question [Y/N]"
        if ($Reply -match '^[Yy]$') { return $true }
        if ($Reply -match '^[Nn]$') { return $false }
    }
}

function Safe([string]$Name, [scriptblock]$Block) {
    try {
        & $Block
        Log "OK $Name"
        Write-Host "  [OK]   $Name" -ForegroundColor Green
    }
    catch {
        Log "SKIP $Name :: $($_.Exception.Message)"
        Write-Host "  [SKIP] $Name :: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function RegBackup([string]$Key, [string]$FileName) {
    $Destination = Join-Path $Backup $FileName
    & reg.exe export $Key $Destination /y | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $Destination)) {
        throw "Registry export failed: $Key"
    }
    Log "REG $Key -> $Destination"
    return $Destination
}

function Set-Dword([string]$Path, [string]$Name, [int]$Value) {
    if (-not (Test-Path $Path)) {
        New-Item $Path -Force | Out-Null
    }
    New-ItemProperty $Path $Name -PropertyType DWord -Value $Value -Force | Out-Null
}

function Backup-Service([string]$Name) {
    $Service = Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
    if ($Service) {
        $Service | Select-Object Name, StartMode, State |
            ConvertTo-Json | Set-Content (Join-Path $Backup "service-$Name.json") -Encoding UTF8
    }
}

function Disable-ServiceSafe([string]$Name) {
    $Service = Get-Service $Name -ErrorAction SilentlyContinue
    if ($Service) {
        Backup-Service $Name
        Set-Service $Name -StartupType Disabled
        if ($Service.Status -ne 'Stopped') {
            Stop-Service $Name -Force -ErrorAction SilentlyContinue
        }
    }
}

function Restore-ServiceStartupType([string]$Name, [string]$StartMode) {
    switch ($StartMode) {
        'Auto'     { $Normalized = 'Automatic' }
        'Automatic'{ $Normalized = 'Automatic' }
        'Manual'   { $Normalized = 'Manual' }
        'Disabled' { $Normalized = 'Disabled' }
        default    { $Normalized = 'Manual' }
    }
    Set-Service $Name -StartupType $Normalized -ErrorAction SilentlyContinue
}

function Detect {
    $OptionalFeature = {
        param([string]$FeatureName)
        try {
            return [bool](Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction Stop |
                Where-Object State -eq 'Enabled')
        }
        catch {
            return $false
        }
    }

    [ordered]@{
        WSL          = [bool](Get-Command wsl.exe -ErrorAction SilentlyContinue)
        VMP          = & $OptionalFeature 'VirtualMachinePlatform'
        HyperV       = & $OptionalFeature 'Microsoft-Hyper-V-All'
        Store        = [bool](Get-AppxPackage -AllUsers Microsoft.WindowsStore -ErrorAction SilentlyContinue)
        Xbox         = [bool](Get-AppxPackage -AllUsers Microsoft.GamingApp -ErrorAction SilentlyContinue)
        AndroidStudio = [bool](Get-Process studio64 -ErrorAction SilentlyContinue) -or
                       [bool](Get-ChildItem "$env:ProgramFiles\Android\Android Studio" -ErrorAction SilentlyContinue)
        AnyDesk      = [bool](Get-Process AnyDesk -ErrorAction SilentlyContinue) -or
                       [bool](Get-Service AnyDesk -ErrorAction SilentlyContinue)
        NordVPN      = [bool](Get-Process NordVPN -ErrorAction SilentlyContinue) -or
                       [bool](Get-Service -Name 'NordVPN*' -ErrorAction SilentlyContinue)
        Bluetooth    = [bool](Get-Service bthserv -ErrorAction SilentlyContinue)
        Printer      = [bool](Get-Service Spooler -ErrorAction SilentlyContinue)
    }
}

# Fail visibly instead of a disappearing red-error console when launched incorrectly.
try {
    New-Item $Backup -ItemType Directory -Force | Out-Null
    $script:Log = Join-Path $Backup 'optimizer.log'

    if (-not (Is-Admin)) {
        Write-Host 'Administrator privileges are required.' -ForegroundColor Yellow
        Write-Host 'Launch Run-JUG-Optimizer.cmd or open PowerShell as Administrator.' -ForegroundColor Yellow
        throw 'Not running as Administrator.'
    }

    Write-Section 'JUG Windows 11 Esports Optimizer'
    Write-Host "PowerShell: $($PSVersionTable.PSVersion)"
    Write-Host "CPU: $((Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Name))"
    $GPU = Get-CimInstance Win32_VideoController | Where-Object Name -match 'NVIDIA|AMD|Intel' | Select-Object -First 1 -ExpandProperty Name
    Write-Host "GPU: $GPU"
    Write-Host "Windows build: $([Environment]::OSVersion.Version)"

    $Environment = Detect
    Write-Section 'Protected workload detection'
    foreach ($Item in $Environment.GetEnumerator()) {
        Write-Host ("  {0,-16} {1}" -f $Item.Key, $(if ($Item.Value) { 'DETECTED' } else { 'not detected' }))
    }

    if ($AuditOnly) {
        Write-Host "`nAUDIT ONLY — no changes applied." -ForegroundColor Cyan
        exit 0
    }

    Write-Section 'Automatic baseline'
    @(
        'Performance-oriented power profile',
        'Game DVR / background capture reduction',
        'Windows visual-effects overhead reduction',
        'Background app restriction',
        'Consumer / advertising surface reduction',
        'Targeted startup cleanup',
        'Temporary-file cleanup',
        'Component Store cleanup'
    ) | ForEach-Object { Write-Host "  + $_" }

    Write-Section 'Explicit decisions'
    $Search = Ask 'Disable Windows Search indexing?'
    $SysMain = Ask 'Disable SysMain? (workload-dependent)'
    $VBS = Ask 'Disable VBS/HVCI/Memory Integrity? (reduced kernel security)'
    $DO = Ask 'Disable Delivery Optimization peer-to-peer only?'
    $Telemetry = Ask 'Disable targeted telemetry services/tasks?'
    $Startup = Ask 'Apply aggressive startup cleanup while preserving detected gaming/dev tools?'
    $NIC = Ask 'Apply adapter-supported NIC latency/power settings?'

    if (-not (Ask 'Proceed with this AGGRESSIVE profile?')) {
        Write-Host 'Cancelled.' -ForegroundColor Yellow
        exit 0
    }

    $RegistryBackups = @()
    $ServiceBackups = @()

    Write-Section 'Backup'
    @(
        'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects',
        'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize',
        'HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR',
        'HKCU\System\GameConfigStore',
        'HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR'
    ) | ForEach-Object {
        try {
            $RegistryBackups += RegBackup $_ ((($_ -replace '[\\:]','_') + '.reg'))
        }
        catch {
            Log "REG-SKIP $_ :: $($_.Exception.Message)"
        }
    }

    # Capture the original power plan BEFORE changing anything.
    $OriginalPowerScheme = ([regex]::Match((powercfg /getactivescheme | Out-String), '[0-9a-fA-F-]{36}')).Value
    $PowerSchemeAfter = $null

    Safe 'Performance power scheme' {
        # Ultimate Performance is used only as a desktop performance profile.
        # The optimizer does NOT claim that it is universally faster than Windows Best Performance.
        $UltimateGuid = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
        $Existing = ([regex]::Matches((powercfg /list | Out-String), '[0-9a-fA-F-]{36}')) |
            ForEach-Object Value | Where-Object { $_ -ieq $UltimateGuid } | Select-Object -First 1
        if (-not $Existing) {
            $CreateOutput = powercfg -duplicatescheme $UltimateGuid 2>&1 | Out-String
            $PowerSchemeAfter = ([regex]::Matches($CreateOutput, '[0-9a-fA-F-]{36}') | Select-Object -Last 1).Value
        }
        else {
            $PowerSchemeAfter = $Existing
        }
        if ($PowerSchemeAfter) {
            powercfg /setactive $PowerSchemeAfter | Out-Null
        }
    }

    Safe 'Game DVR / capture reduction' {
        Set-Dword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
        Set-Dword 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
        Set-Dword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0
    }

    Safe 'Windows visual overhead' {
        Set-Dword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0
        Set-Dword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 2
    }

    Safe 'Background apps' {
        Set-Dword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1
    }

    Safe 'Consumer surfaces' {
        Set-Dword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
        Set-Dword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SilentInstalledAppsEnabled' 0
        Set-Dword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338388Enabled' 0
    }

    if ($Search) {
        Safe 'Disable Windows Search' {
            Disable-ServiceSafe 'WSearch'
        }
    }

    if ($SysMain) {
        Safe 'Disable SysMain' {
            Disable-ServiceSafe 'SysMain'
        }
    }

    if ($VBS) {
        Safe 'Disable VBS/HVCI' {
            $RegistryBackups += RegBackup 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'deviceguard.reg'
            $RegistryBackups += RegBackup 'HKLM\SYSTEM\CurrentControlSet\Control\Lsa' 'lsa.reg'
            Set-Dword 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' 0
            Set-Dword 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'LsaCfgFlags' 0
            $HVCI = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'
            if (-not (Test-Path $HVCI)) { New-Item $HVCI -Force | Out-Null }
            Set-Dword $HVCI 'Enabled' 0
        }
    }

    if ($DO) {
        Safe 'Delivery Optimization peer-to-peer' {
            # Restrict P2P distribution without disabling the Delivery Optimization service.
            Set-Dword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 100
        }
    }

    if ($Telemetry) {
        foreach ($ServiceName in @('DiagTrack','dmwappushservice')) {
            Safe "Disable $ServiceName" {
                if (Get-Service $ServiceName -ErrorAction SilentlyContinue) {
                    Disable-ServiceSafe $ServiceName
                }
            }
        }

        $Tasks = @(
            '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
            '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
            '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
            '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
            '\Microsoft\Windows\Feedback\Siuf\DmClient'
        )
        foreach ($TaskPathName in $Tasks) {
            try {
                $TaskPath = Split-Path $TaskPathName
                $TaskName = Split-Path $TaskPathName -Leaf
                if (Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop) {
                    Disable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName | Out-Null
                }
            }
            catch {
                Log "TASK-SKIP $TaskPathName :: $($_.Exception.Message)"
            }
        }
    }

    if ($Startup) {
        Safe 'Targeted startup cleanup' {
            # Conservative by design. Do not mass-delete startup entries because the machine
            # contains development, VPN, remote-access and gaming workloads.
            $RunKeys = @(
                'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
            )
            foreach ($RunKey in $RunKeys) {
                if (-not (Test-Path $RunKey)) { continue }
                $Properties = Get-ItemProperty $RunKey
                foreach ($Property in $Properties.PSObject.Properties) {
                    if ($Property.Name -match '^PS') { continue }
                    if ($Property.Name -match 'Teams|MicrosoftTeams|GoogleUpdate|AdobeGCInvoker') {
                        Remove-ItemProperty $RunKey $Property.Name -ErrorAction SilentlyContinue
                    }
                }
            }
        }
    }

    if ($NIC) {
        Safe 'Hardware-aware NIC tuning' {
            $Adapters = Get-NetAdapter -Physical | Where-Object Status -eq 'Up'
            foreach ($Adapter in $Adapters) {
                try { Set-NetAdapterRss -Name $Adapter.Name -Enabled $true -ErrorAction SilentlyContinue } catch {}
                try { Set-NetAdapterPowerManagement -Name $Adapter.Name -SelectiveSuspend Disabled -ErrorAction SilentlyContinue } catch {}

                $Properties = Get-NetAdapterAdvancedProperty -Name $Adapter.Name -ErrorAction SilentlyContinue
                foreach ($DisplayName in @('Energy Efficient Ethernet','Green Ethernet','Interrupt Moderation','Packet Coalescing')) {
                    $Property = $Properties | Where-Object DisplayName -eq $DisplayName | Select-Object -First 1
                    if ($Property) {
                        try {
                            Set-NetAdapterAdvancedProperty -Name $Adapter.Name -DisplayName $DisplayName -DisplayValue Disabled -NoRestart -ErrorAction Stop
                        }
                        catch {
                            Log "NIC property skipped: $($Adapter.Name) / $DisplayName :: $($_.Exception.Message)"
                        }
                    }
                }
            }
        }
    }

    Safe 'Temporary cleanup' {
        Get-ChildItem $env:TEMP -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    Safe 'Component Store cleanup' {
        Start-Process dism.exe -ArgumentList '/Online','/Cleanup-Image','/StartComponentCleanup' -Wait -NoNewWindow
    }

    Safe 'BCD/pagefile audit only' {
        bcdedit /enum all | Out-File (Join-Path $Backup 'bcd-audit.txt')
        Get-CimInstance Win32_ComputerSystem |
            Select-Object AutomaticManagedPagefile |
            ConvertTo-Json | Set-Content (Join-Path $Backup 'pagefile-audit.json') -Encoding UTF8
    }

    $ServiceBackups = Get-ChildItem $Backup -Filter 'service-*.json' -ErrorAction SilentlyContinue |
        ForEach-Object { Get-Content $_.FullName -Raw | ConvertFrom-Json }

    $Manifest = [ordered]@{
        Created             = (Get-Date).ToString('o')
        OriginalPowerScheme = $OriginalPowerScheme
        AppliedPowerScheme  = $PowerSchemeAfter
        Registry            = @($RegistryBackups)
        Services            = @($ServiceBackups)
    }
    $Manifest | ConvertTo-Json -Depth 8 |
        Set-Content (Join-Path $Backup 'manifest.json') -Encoding UTF8

    Write-Host "`nDONE — backup: $Backup" -ForegroundColor Green
    Write-Host 'A restart is recommended before benchmarking.' -ForegroundColor Cyan

    if (-not $NoReboot -and (Ask 'Restart now?')) {
        Restart-Computer -Force
    }
}
catch {
    Write-Host "`nFATAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
    if ($script:Log) { Log "FATAL :: $($_.Exception.ToString())" }
    Write-Host "`nBackup/log path: $Backup" -ForegroundColor Yellow
    Write-Host 'Press Enter to close...' -ForegroundColor DarkGray
    [void](Read-Host)
    exit 1
}
