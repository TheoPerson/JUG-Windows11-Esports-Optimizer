# Rollback

Every apply run should create a timestamped backup under:

```text
C:\ProgramData\JUG-Optimizer\Backup\<timestamp>\
```

Use audit mode before making changes:

```powershell
.\JUG_Windows11_EsportsOptimizer.ps1 -AuditOnly
```

Restore a supported backup with:

```powershell
.\JUG_Windows11_EsportsOptimizer.ps1 -Restore -BackupPath "C:\ProgramData\JUG-Optimizer\Backup\<timestamp>"
```

Rollback is designed to restore settings explicitly captured by the optimizer. It is not a substitute for a full Windows system image. Keep normal Windows recovery options available before aggressive system tuning.
