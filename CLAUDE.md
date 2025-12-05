# OpenLakes Core – Deployment Notes For AI Agents

This file tracks the current state of the OpenLakes Core repository so that any
future automated assistant has the right context while working in this tree.

---

## Repository Snapshot
- The repository currently tracks a single baseline commit named `init commit`
  so future automation always starts from a deterministic state.
- `main` is the only branch and mirrors `origin/main`; no tags are defined.

## Current State Of `main`
- `deploy-openlakes.sh` contains all automation for multi-cluster deployments,
  including the runtime dashboard credential refresh, MinIO tiering logic, and
  post-deploy readiness checks.
- All Helm layers (`layers/01-…` through `layers/08-…`) are present and aligned
  with the latest validated configuration for both single-node (local-path) and
  multi-node (longhorn) clusters.
- Custom Docker build contexts live under `docker/` (dashboard, Spark runtime,
  Meltano runtime, Airflow runtime, etc.). Each image continues to target tag
  `1.0.0` unless the user decides otherwise later.
- Example notebooks/DAGs were reorganized so the repo no longer nests them under
  `notebooks/`; instead they reside directly under `examples/...` with the same
  hierarchy.
- Integration test scripts and legacy docs that were no longer relevant were
  removed before the init commit to keep the repository lean.

## Deployment Summary
- The last validated deployment happened on the multi-node `default` context
  covering all layers (01–08). After deployment, the cluster was drained on node
  `nuc` and un-cordoned to verify MinIO and other services reattach cleanly.
- MinIO hot-tier PVs are created dynamically from `core-config.yaml`. Users must
  ensure `/minio[1-4]` host paths remain consistent across redeployments to avoid
  format mismatches.
- Dashboard credential refresh now runs automatically twice per deploy: once
  immediately after Layer 04 (if Airflow is up) and once at the final summary to
  ensure runtime passwords (Airflow simple-auth) are rendered on the UI.

## Authoritative Configuration
- `core-config.yaml` is the single source of truth for runtime settings
  (credentials, networking, storage tiers, resource profiles, notebook sync
  schedules, etc.). All automation expects this file to be present at repo root.

## Instructions For Future Automations
1. **Always read `core-config.yaml` before altering anything** so overrides flow
   correctly into Helm layers and scripts.
2. **Keep the history single-commit unless directed otherwise.** If changes are
   required, consolidate them into the new baseline `init commit` only after the
   user requests a push.
3. **Coordinate any pushes** so the remote remains consistent with the expected
   single-commit structure.
4. **Keep GHCR tags at `1.0.0`** until the user decides to introduce versioning.

---
If new context must be recorded (e.g., after another sweeping change), update
this file so the next automation run starts with accurate information.
