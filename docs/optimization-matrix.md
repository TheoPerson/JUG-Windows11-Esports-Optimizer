# Optimization matrix

The project separates changes by risk rather than by how impressive a tweak list looks.

| Category | Profile | Reversible | Main trade-off |
|---|---|---:|---|
| Performance power plan | Automatic | Yes | Higher power/heat |
| Game DVR / capture | Automatic | Yes | Windows capture features |
| Visual effects | Automatic | Yes | Reduced UI effects |
| Background UWP execution | Automatic | Yes | Background app refresh |
| Consumer/advertising surfaces | Automatic | Yes | Fewer Windows suggestions |
| Search indexing | Confirm | Yes | Slower Windows search |
| SysMain | Confirm | Yes | Possible application-launch trade-off |
| VBS / HVCI | Confirm | Yes | Reduced security hardening |
| Telemetry services | Confirm | Yes | Diagnostic functionality |
| Scheduled tasks | Confirm | Yes | Reduced diagnostics/consumer maintenance |
| Startup entries | Confirm | Yes | Some apps may no longer auto-start |
| NIC tuning | Confirm | Yes | Adapter-specific behavior |
| Windows Update delivery | Confirm | Yes | Update delivery convenience |
| BCD / HPET timer hacks | Never | N/A | Excluded as non-universal/unsupported optimization |
| Pagefile removal | Never | N/A | Excluded |
| Defender removal | Never | N/A | Excluded |
| WSL/VMP/Hyper-V removal | Never | N/A | Conflicts with development workloads |

## Validation rule

A change should remain in the project only when its purpose is technically defensible and its behavior can be observed or rolled back. Process count alone is not considered a performance metric.
