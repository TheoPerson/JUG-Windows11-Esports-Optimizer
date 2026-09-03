# JUG Windows 11 Esports Optimizer

**Aggressive, hardware-aware Windows 11 tuning for competitive gaming and development — with explicit risk boundaries, detection and rollback.**

[![PowerShell 7+](https://img.shields.io/badge/PowerShell-7%2B-5391FE?logo=powershell&logoColor=white)](https://learn.microsoft.com/powershell/)
[![Windows 11](https://img.shields.io/badge/Windows-11-0078D4?logo=windows11&logoColor=white)](https://www.microsoft.com/windows/windows-11)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Status](https://img.shields.io/badge/Status-Experimental-orange)](#status)

> **Less unnecessary work. More consistent frame delivery. No tweak folklore.**

JUG is a PowerShell 7+ Windows 11 optimizer built for a high-refresh competitive PC that is also used as a serious development workstation.

---

## What it is

JUG does not attempt to win by disabling everything. It identifies the parts of Windows that create unnecessary background activity, applies targeted configuration, and keeps critical gaming/development dependencies intact.

The design target is a machine used for:

**Competitive FPS · COD / Game Pass · NVIDIA · high-refresh displays · VS Code · Claude Code · Antigravity · Node/Bun · WSL2 · Android Studio · AnyDesk · NordVPN**

## Core principles

| Principle | JUG behavior |
|---|---|
| Detect first | Hardware, Windows features and common workloads are inspected before changes |
| Aggressive, not reckless | High-impact categories require explicit confirmation |
| Reversible | Touched registry/service/power state is backed up where supported |
| Hardware-aware | NIC and system changes are conditional on what Windows exposes |
| No placebo | No blind HPET/platform-clock/`disabledynamictick` folklore |
| Preserve development | WSL/VMP/Hyper-V/Android tooling are not blindly removed |
| Preserve daily use | Browsers, taskbar, password managers, bookmarks and session data are left alone |

## Main optimization areas

- Performance-oriented Windows power configuration
- Game DVR / background capture reduction
- Shell visual-overhead reduction
- Background application restriction
- Consumer/advertising surface reduction
- Optional Windows Search reduction
- Optional SysMain reduction
- Optional VBS/HVCI/Memory Integrity reduction
- Targeted telemetry service/task reduction
- Targeted startup cleanup
- Hardware-aware NIC power/latency configuration
- Temporary-file and component-store cleanup
- BCD and pagefile **audit**, not blind modification

## Explicitly protected

JUG is designed not to casually break the workloads you actually use.

- WSL2 / Virtual Machine Platform / Hyper-V
- Android Studio and emulator infrastructure
- Microsoft Store
- Xbox / Game Pass / COD-related infrastructure
- AnyDesk
- NordVPN
- Bluetooth
- Printing
- Browser profiles and bookmarks
- Password-manager data
- Taskbar and interactive shell state
- User login/session data

Detection is preferred to assumptions, and potentially disruptive categories are exposed before application.

## What it deliberately does not do

JUG intentionally avoids generic “FPS pack” tricks such as:

```text
bcdedit /set useplatformclock true
bcdedit /set disabledynamictick yes
forcing HPET
removing the pagefile
removing Defender blindly
removing Windows Update completely
disabling WSL/VMP blindly
mass-disabling every Windows service
```

A setting is not included merely because it changes a registry value or makes Task Manager show fewer processes.

## Requirements

- Windows 11 desktop
- PowerShell 7+
- Administrator privileges
- Reboot recommended after an apply run

## Usage

### Audit first

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\JUG_Windows11_EsportsOptimizer.ps1 -AuditOnly
```

### Apply

```powershell
.\JUG_Windows11_EsportsOptimizer.ps1
```

The optimizer shows the planned changes and requests confirmation before applying the aggressive categories.

### Restore

Backups are stored under:

```text
C:\ProgramData\JUG-Optimizer\Backup\<timestamp>\
```

Restore supported state with:

```powershell
.\JUG_Windows11_EsportsOptimizer.ps1 -Restore -BackupPath "C:\ProgramData\JUG-Optimizer\Backup\<timestamp>"
```

## Important performance note

Process count is not a benchmark.

The useful question is whether background work, CPU wakeups, driver behavior, frametime variance and input-to-photon latency improve for the workload being tested. Results depend on Windows build, firmware, chipset, GPU driver, network adapter and installed software.

Run repeatable before/after tests rather than relying only on subjective “it feels smoother” results.

## Status

**Experimental.**

The project is currently a personal, aggressive profile being shaped into a broader Windows optimization toolkit. It has not been validated across every Windows 11 build or hardware family.

Never run an administrator-level system optimizer blindly on a production machine. Read the code and keep recovery access available.

## Roadmap

- Pre/post benchmark capture
- DPC and ISR diagnostics
- Driver and background-process attribution
- Per-vendor CPU/GPU profiles
- Recommendation-only mode
- Stronger rollback verification
- Signed release artifacts
- Versioned Windows-build compatibility matrix

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Security

See [SECURITY.md](SECURITY.md).

## License

MIT — see [LICENSE](LICENSE).

---

**JUG / TheoPerson**
