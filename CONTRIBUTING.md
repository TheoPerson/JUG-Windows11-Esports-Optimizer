# Contributing

## Principles

1. No tweak without a clear technical reason.
2. Prefer documented Windows behavior over folklore.
3. Avoid destructive defaults.
4. Add rollback coverage for configuration changes.
5. Preserve common gaming and developer workloads.
6. Benchmark before claiming a performance improvement.

## PowerShell

Target PowerShell 7+ and keep functions defensive and readable. Avoid external dependencies unless there is a strong reason.

## Pull requests

Include:

- Windows build tested
- Hardware tested
- Expected performance/functionality impact
- Rollback behavior
- Whether the change is safe, trade-off, or potentially breaking
