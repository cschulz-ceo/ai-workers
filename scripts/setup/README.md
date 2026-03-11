# Setup Scripts

Idempotent first-run scripts for provisioning the ai-workers environment.
Scripts are ordered by the dependency build order defined in `docs/architecture.md`.

## Conventions
- All scripts must be idempotent (safe to run multiple times)
- Scripts check for existing state before taking action
- No script should require interactive input
- Each script logs to stdout with clear section headers
