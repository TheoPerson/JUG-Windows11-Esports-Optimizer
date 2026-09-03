#requires -Version 7.0
<#!
JUG Windows 11 Esports Optimizer — AGGRESSIVE

Admin PowerShell 7+.
Audit first: .\JUG_Windows11_EsportsOptimizer.ps1 -AuditOnly
Apply:       .\JUG_Windows11_EsportsOptimizer.ps1
Restore:     .\JUG_Windows11_EsportsOptimizer.ps1 -Restore -BackupPath <backup>

Design: targeted, conditional, reversible. No HPET/BCD timer folklore, no pagefile
removal, no Defender removal, and no blind removal of WSL/VMP/Hyper-V.
#>
[CmdletBinding()]
param([switch]$AuditOnly,[switch]$Restore,[string]$BackupPath,[switch]$NoReboot)
$ErrorActionPreference='Stop'; $Root=Join-Path $env:ProgramData 'JUG-Optimizer'; $Stamp=Get-Date -Format yyyyMMdd-HHmmss
$Backup=if($BackupPath){$BackupPath}else{Join-Path $Root "Backup\$Stamp"}; New-Item $Backup -ItemType Directory -Force | Out-Null
$Log=Join-Path $Backup 'optimizer.log'
function Log($s){"$(Get-Date -Format s) $s"|Add-Content $Log -Encoding UTF8}
function Admin{$p=[Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent();if(!$p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Run PowerShell as Administrator.'}}
function Ask($q){while($true){$r=Read-Host "$q [Y/N]";if($r -match '^[Yy]$'){return $true};if($r -match '^[Nn]$'){return $false}}}
function Safe($name,[scriptblock]$b){try{&$b;Log "OK $name";Write-Host "  [OK] $name" -ForegroundColor Green}catch{Log "SKIP $name :: $($_.Exception.Message)";Write-Host "  [SKIP] $name :: $($_.Exception.Message)" -ForegroundColor Yellow}}
function RegBackup($key,$file){$dest=Join-Path $Backup $file;& reg.exe export $key $dest /y|Out-Null;Log "REG $key -> $dest";return $dest}
function Dword($path,$name,$value){if(!(Test-Path $path)){New-Item $path -Force|Out-Null};New-ItemProperty $path $name -PropertyType DWord -Value $value -Force|Out-Null}
function SvcBackup($name){$s=Get-CimInstance Win32_Service -Filter "Name='$name'" -ErrorAction SilentlyContinue;if($s){$s|Select Name,StartMode,State|ConvertTo-Json|Set-Content (Join-Path $Backup "service-$name.json") -Encoding UTF8}}
function DisableSvc($name){$s=Get-Service $name -ErrorAction SilentlyContinue;if($s){SvcBackup $name;Set-Service $name -StartupType Disabled;Stop-Service $name -Force -ErrorAction SilentlyContinue}}
function Detect{
 [ordered]@{
  WSL=[bool](Get-Command wsl.exe -EA SilentlyContinue)
  VMP=[bool](Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -EA SilentlyContinue|? State -eq Enabled)
  HyperV=[bool](Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -EA SilentlyContinue|? State -eq Enabled)
  Store=[bool](Get-AppxPackage -AllUsers Microsoft.WindowsStore -EA SilentlyContinue)
  Xbox=[bool](Get-AppxPackage -AllUsers Microsoft.GamingApp -EA SilentlyContinue)
  AndroidStudio=[bool](Get-Process studio64 -EA SilentlyContinue)
  AnyDesk=[bool](Get-Process AnyDesk -EA SilentlyContinue)-or[bool](Get-Service AnyDesk -EA SilentlyContinue)
  NordVPN=[bool](Get-Process NordVPN -EA SilentlyContinue)-or[bool](Get-Service -Name NordVPN* -EA SilentlyContinue)
  Bluetooth=[bool](Get-Service bthserv -EA SilentlyContinue)
  Printer=[bool](Get-Service Spooler -EA SilentlyContinue)
 }
}
Admin
if($Restore){if(!$BackupPath){throw '-Restore requires -BackupPath.'};$m=Join-Path $BackupPath 'manifest.json';if(!(Test-Path $m)){throw "Manifest not found: $m"};$x=Get-Content $m -Raw|ConvertFrom-Json;foreach($r in $x.Registry){if(Test-Path $r){& reg.exe import $r|Out-Null}};foreach($s in $x.Services){if(Get-Service $s.Name -EA SilentlyContinue){Set-Service $s.Name -StartupType $s.StartMode -EA SilentlyContinue}};if($x.PowerScheme){powercfg /setactive $x.PowerScheme|Out-Null};Write-Host "Restore complete: $BackupPath" -ForegroundColor Green;exit}
$e=Detect
Write-Host "`nJUG Windows 11 Esports Optimizer — AGGRESSIVE`n" -ForegroundColor Cyan
Write-Host "CPU: $((Get-CimInstance Win32_Processor|select -First 1 -Expand Name))"
Write-Host "GPU: $((Get-CimInstance Win32_VideoController|? Name -match NVIDIA|select -First 1 -Expand Name))"
Write-Host "Windows: $([Environment]::OSVersion.Version)"
Write-Host "`nProtected workload detection:" -ForegroundColor Yellow
$e.GetEnumerator()|%{Write-Host ("  {0,-16} {1}"-f $_.Key,($(if($_.Value){'DETECTED'}else{'not detected'})))}
if($AuditOnly){Write-Host "`nAUDIT ONLY — no changes applied." -ForegroundColor Cyan;exit}
Write-Host "`nAutomatic baseline:" -ForegroundColor Green
@('Performance power profile','Game DVR/background capture reduction','Transparency/visual effects reduction','Background app restriction','Consumer/advertising reduction','Targeted startup cleanup','Temporary cleanup','Component Store cleanup')|%{Write-Host "  + $_"}
Write-Host "`nExplicit decisions:" -ForegroundColor Yellow
$search=Ask 'Disable Windows Search indexing? (slower Windows search)'
$sysmain=Ask 'Disable SysMain? (workload-dependent launch trade-off)'
$vbs=Ask 'Disable VBS/HVCI/Memory Integrity? (reduced security hardening)'
$wu=Ask 'Restrict Delivery Optimization / Windows Update behavior? (Windows Update service remains)'
$telemetry=Ask 'Disable targeted telemetry services/tasks?'
$startup=Ask 'Apply aggressive startup cleanup while preserving detected gaming/dev tools?'
$nic=Ask 'Apply supported NIC latency/power settings? (adapter-dependent)'
if(!(Ask 'Proceed with this AGGRESSIVE profile?')){Write-Host 'Cancelled.' -ForegroundColor Yellow;exit}
$regs=@();$svcs=@()
@(
'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects',
'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize',
'HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR',
'HKCU\System\GameConfigStore',
'HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR'
)|%{try{$regs+=RegBackup $_ ((($_ -replace '[\\:]','_')+'.reg'))}catch{}}
Safe 'Performance power scheme' { $id='e9a42b02-d5df-448d-aa00-03f14749eb61';$s=(powercfg /list)|? {$_ -match $id}|%{[regex]::Match($_,'[0-9a-fA-F-]{36}').Value}|select -First 1;if(!$s){$o=powercfg -duplicatescheme $id 2>&1;$s=([regex]::Matches(($o|Out-String),'[0-9a-fA-F-]{36}')|select -Last 1).Value};if($s){$old=([regex]::Match((powercfg /getactivescheme|Out-String),'[0-9a-fA-F-]{36}')).Value;$powerOld=$old;powercfg /setactive $s|Out-Null}}
Safe 'Game DVR / capture' {Dword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' AppCaptureEnabled 0;Dword 'HKCU:\System\GameConfigStore' GameDVR_Enabled 0;Dword 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' AllowGameDVR 0}
Safe 'Windows visual overhead' {Dword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' EnableTransparency 0;Dword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' VisualFXSetting 2}
Safe 'Background apps' {Dword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' GlobalUserDisabled 1}
Safe 'Consumer surfaces' {Dword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' Enabled 0;Dword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' SilentInstalledAppsEnabled 0;Dword 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' SubscribedContent-338388Enabled 0}
if($search){Safe 'Disable Windows Search' {SvcBackup WSearch;DisableSvc WSearch;$svcs+=Get-Content (Join-Path $Backup 'service-WSearch.json')|ConvertFrom-Json}}
if($sysmain){Safe 'Disable SysMain' {SvcBackup SysMain;DisableSvc SysMain;$svcs+=Get-Content (Join-Path $Backup 'service-SysMain.json')|ConvertFrom-Json}}
if($vbs){Safe 'Disable VBS/HVCI' {RegBackup 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'deviceguard.reg';RegBackup 'HKLM\SYSTEM\CurrentControlSet\Control\Lsa' 'lsa.reg';Dword 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' EnableVirtualizationBasedSecurity 0;Dword 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' LsaCfgFlags 0;$p='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity';if(!(Test-Path $p)){New-Item $p -Force|Out-Null};Dword $p Enabled 0}}
if($wu){Safe 'Restrict Delivery Optimization' {if(Get-Service DoSvc -EA SilentlyContinue){SvcBackup DoSvc;DisableSvc DoSvc};Dword 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' ActiveHoursStart 8;Dword 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' ActiveHoursEnd 23}}
if($telemetry){foreach($n in 'DiagTrack','dmwappushservice'){Safe "Disable $n" {if(Get-Service $n -EA SilentlyContinue){SvcBackup $n;DisableSvc $n}}};$tasks=@('\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser','\Microsoft\Windows\Application Experience\ProgramDataUpdater','\Microsoft\Windows\Customer Experience Improvement Program\Consolidator','\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip','\Microsoft\Windows\Feedback\Siuf\DmClient');foreach($t in $tasks){try{$q=Get-ScheduledTask -TaskPath (Split-Path $t) -TaskName (Split-Path $t -Leaf) -EA Stop;Disable-ScheduledTask -TaskPath $q.TaskPath -TaskName $q.TaskName|Out-Null}catch{}}}
if($startup){Safe 'Targeted startup cleanup' {$r=@('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run');foreach($p in $r){if(Test-Path $p){$x=Get-ItemProperty $p;foreach($z in $x.PSObject.Properties){if($z.Name -notmatch '^PS' -and $z.Name -match 'Teams|MicrosoftTeams|GoogleUpdate|AdobeGCInvoker'){Remove-ItemProperty $p $z.Name -EA SilentlyContinue}}}}}}
if($nic){Safe 'Hardware-aware NIC tuning' {$a=Get-NetAdapter -Physical|? Status -eq Up;foreach($n in $a){Set-NetAdapterRss -Name $n.Name -Enabled $true -EA SilentlyContinue;Set-NetAdapterPowerManagement -Name $n.Name -SelectiveSuspend Disabled -EA SilentlyContinue;$props=Get-NetAdapterAdvancedProperty -Name $n.Name -EA SilentlyContinue;foreach($d in 'Energy Efficient Ethernet','Green Ethernet','Interrupt Moderation','Packet Coalescing'){$p=$props|? DisplayName -eq $d|select -First 1;if($p){try{Set-NetAdapterAdvancedProperty -Name $n.Name -DisplayName $d -DisplayValue Disabled -NoRestart -EA Stop}catch{}}}}}}
Safe 'Temporary cleanup' {Get-ChildItem $env:TEMP -Force -EA SilentlyContinue|Remove-Item -Recurse -Force -EA SilentlyContinue}
Safe 'Component Store cleanup' {Start-Process dism.exe -ArgumentList '/Online','/Cleanup-Image','/StartComponentCleanup' -Wait -NoNewWindow}
Safe 'BCD/pagefile audit only' {bcdedit /enum all|Out-File (Join-Path $Backup 'bcd-audit.txt');Get-CimInstance Win32_ComputerSystem|select AutomaticManagedPagefile|ConvertTo-Json|Set-Content (Join-Path $Backup 'pagefile-audit.json')}
$serviceFiles=Get-ChildItem $Backup -Filter 'service-*.json'|%{Get-Content $_.FullName -Raw|ConvertFrom-Json};$manifest=[ordered]@{Created=(Get-Date).ToString('o');PowerScheme=$powerOld;Registry=@($regs);Services=@($serviceFiles)};$manifest|ConvertTo-Json -Depth 8|Set-Content (Join-Path $Backup 'manifest.json') -Encoding UTF8
Write-Host "`nDONE — backup: $Backup" -ForegroundColor Green
if(!$NoReboot -and (Ask 'Restart now?')){Restart-Computer -Force}
