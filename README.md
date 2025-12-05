# OpenLakes Core

OpenLakes Core provides an on-prem, open-source lakehouse stack built from battle-tested projects like Apache Iceberg, Spark, Trino, Airflow, Superset, MinIO, Grafana, and more. The deployer script (`deploy-openlakes.sh`) wires together storage tiers, credentials, and ingress to deliver a full multi-tenant analytics environment on Kubernetes.

## Architecture Highlights

- **Storage + Lakehouse**: MinIO for object storage, Apache Iceberg tables, optional tiered (hot/cold/cache) hostPath mounts.
- **Compute + Orchestration**: Spark, Trino, Airflow, Meltano, and JupyterHub notebooks with automatic synchronization.
- **Observability & Control Plane**: Prometheus, Grafana, Loki, integrated auth, and lifecycle automation.

## Quickstart

1. **Prerequisites**
   - Kubernetes cluster (single node or multi-node) with `kubectl` context set.
   - Helm 3, `yq`, GNU `bash` 4+, and access to persistent storage paths for MinIO tiers.
   - Optional: Longhorn or CSI storage class for block volumes.

2. **Clone and configure**
   ```bash
   git clone https://github.com/OpenLakes/core.git
   cd core
   cp core-config.example.yaml core-config.yaml
   # edit core-config.yaml to match your domains, passwords, and storage paths
   ```
   > ⚠️ **Security**: All passwords and hostnames in `core-config.example.yaml` are placeholders. Change *every* credential and hostPath before using outside a throwaway lab cluster.

3. **Deploy**
   ```bash
   ./deploy-openlakes.sh
   ```
   The script validates prerequisites, applies the Helm layers, and waits for critical services before exiting.

## Configuration Notes

- `core-config.example.yaml` documents every tunable option. Treat it as a template and keep your real `core-config.yaml` out of version control (see `.gitignore`).
- For advanced tweaks (custom storage classes, additional components), edit the relevant sections under `storage`, `components`, and `observability`.

## License

Copyright (c) OpenLakes.

Licensed under the [Apache License 2.0](./LICENSE).
