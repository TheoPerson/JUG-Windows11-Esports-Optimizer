# Security Policy

JUG is an administrator-level Windows optimizer. It can change system configuration, services, scheduled tasks, registry values, power settings and security-related configuration.

## Safe use

- Read the script before execution.
- Run `-AuditOnly` first.
- Keep recovery access available.
- Test changes on non-production systems first.
- Use the generated backup for rollback when required.

## Security trade-offs

The aggressive profile may disable VBS/HVCI/Memory Integrity when explicitly approved. This reduces Windows security hardening and is an intentional performance trade-off.

## Reporting

For security vulnerabilities in the project itself, use GitHub's private vulnerability reporting mechanism when available rather than publishing sensitive exploit details in a public issue.
