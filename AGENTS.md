# Project guidelines

This repository maintains the patches and overlays for the Mastodon fork used on wxw.moe.

## Layout

- `build.sh`: pins the upstream version, recreates `src/`, applies the ordered module list, then builds Docker images. `--check` stops before image builds.
- `patches/<name>.sh`: module entry point; validates prerequisites, patches upstream files, and installs overlays.
- `patches/<name>.patch`: optional unified diff for upstream integration.
- `overlay/<name>/`: added implementation, assets, migrations, and tests. Feature overlays generally mirror the upstream tree; each installer defines its copy destinations.

## Integration

- Keep each module's script, patch, and overlay names aligned. Register its script basename in the `build.sh` module list with a short description.
- Keep shell runners small. Validate anchors and overlay destinations before modifying files; reject unexpected context or file collisions. Use patch dry-runs and `--fuzz=0`.
- Minimize changes to upstream code, whether applied through shell scripts or patch files. Put feature logic in `overlay/`; prefer imports, includes, hooks, and calls to overlay helpers over rewriting existing methods or copying entire upstream files.
- When a method must change, retain its upstream flow and delegate the added behavior to an overlay method wherever practical.

## Replay and validation

- Default to independent replay on clean source from the pinned upstream version, using only the module's own overlay. Avoid relying on patch context introduced by other modules.
- Introduce cross-module dependencies only when necessary, and explicitly declare and validate prerequisites and application order.
- Check changed shell syntax, exact-version replay, and `git diff --check`; verify rerun, context-drift, and overlay-collision rejection where relevant. Keep agent-only checks and temporary artifacts outside the repository.
- Preserve unrelated working changes. Use `git mv` for renames and keep commits scoped to the requested work.
