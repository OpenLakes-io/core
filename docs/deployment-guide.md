# OpenLakes Deployment Guide

## Quick Start

The `deploy-openlakes.sh` script provides an automated, idempotent way to deploy all OpenLakes layers to your Kubernetes cluster.

### Prerequisites

- `kubectl` configured and connected to your Kubernetes cluster
- `helm` (version 3.x)
- Sufficient cluster resources (recommended: 8+ CPU cores, 16+ GB RAM)
- **Networking (multi-node)**: Use a high-throughput CNI (Cilium recommended for RKE2) so inter-node bandwidth is ≥1 Gbps. The deploy script will measure throughput during preflight and warn if it detects <1 Gbps or a non-Cilium CNI.
- **Cluster flavor**: The script auto-detects single-node vs multi-node:
  - Single-node (e.g., Rancher Desktop) → skips the storage wizard, runs MinIO in standalone mode, and defaults to `local-path`.
  - Multi-node → runs the storage wizard (unless skipped), keeps distributed MinIO/Longhorn paths, and enforces NFS client tooling on all nodes.

### Basic Usage

```bash
# Deploy all layers with default settings
./deploy-openlakes.sh

# Preview what would be deployed (dry-run)
./deploy-openlakes.sh --dry-run

# Deploy to a custom namespace
./deploy-openlakes.sh --namespace production

# Set custom timeout for Helm operations
./deploy-openlakes.sh --timeout 15m

# Show help
./deploy-openlakes.sh --help
```

### Environment Variables

You can also configure the deployment using environment variables:

```bash
# Deploy to 'dev' namespace with 15-minute timeout
NAMESPACE=dev TIMEOUT=15m ./deploy-openlakes.sh

# Dry run using environment variable
DRY_RUN=true ./deploy-openlakes.sh
```

## Features

### Idempotency

The script uses `helm upgrade --install`, making it safe to run multiple times:

- **First run**: Installs all layers
- **Subsequent runs**: Upgrades existing releases or installs missing ones
- **Partial failures**: Re-running will pick up where it left off

### Cross-Platform Compatibility

The script automatically detects your operating system and adapts:

- ✅ **macOS** (Darwin) - Full support
- ✅ **Linux** - Full support
- ✅ **WSL** - Full support (detected as Linux)

### Resource Readiness Checks

The script waits for critical services to be ready before proceeding:

**Layer 01 (Infrastructure)**:
- PostgreSQL StatefulSet
- Kafka StatefulSet
- MinIO StatefulSet

**Layer 02 (Compute)**:
- Trino Deployment
- Spark Worker StatefulSet

**Layer 03 (Streaming)**:
- Flink JobManager Deployment

**Layer 05 (Analytics)**:
- Superset Deployment

### Progress Reporting

The script provides detailed, color-coded output:

- 🔵 **Info**: General information and progress updates
- ✅ **Success**: Completed operations
- ⚠️ **Warning**: Non-critical issues (continues execution)
- ❌ **Error**: Critical failures (stops execution)

### Deployment Status

After successful deployment, the script displays:

1. **Helm Releases**: All deployed releases with versions
2. **Pod Status**: Running pods with their readiness state
3. **Service Endpoints**: NodePort services with their access ports
4. **Access URLs**: Direct links to web UIs

## Deployment Layers

The script deploys 7 layers in sequence:

| Layer | Name | Components | Release Name |
|-------|------|------------|--------------|
| 01 | Infrastructure | PostgreSQL, MinIO, Kafka, OpenSearch, Redis | `01-infrastructure` |
| 02 | Compute | Trino, Spark (master/worker) | `02-compute` |
| 03 | Streaming | Flink JobManager | `03-streaming` |
| 04 | Orchestration | Airflow, Jupyter | `04-orchestration` |
| 05 | Analytics | Superset | `05-analytics` |
| 06 | Ingestion | Meltano runtime (Singer CLI), Debezium | `layer06-ingestion`* |
| 07 | Catalog | OpenMetadata server + ingestion | `layer07-catalog` |

\* Layer 06 uses `layer06-ingestion` to avoid Kubernetes DNS naming restrictions (service names cannot start with numbers).

## Access URLs

After deployment, access the following UIs:

| Service | URL | Default Credentials |
|---------|-----|---------------------|
| OpenMetadata | http://localhost:30585 | admin / admin |
| Superset | http://localhost:30088 | admin / admin |
| Trino | http://localhost:30081 | - |
| Spark Master | http://localhost:30077 | - |
| Flink | http://localhost:30083 | - |
| MinIO Console | http://localhost:32584 | minioadmin / minioadmin |
| Jupyter | http://localhost:30888 | - |

**Note**: Replace `localhost` with your cluster's IP if accessing remotely.

## Dashboard Service Routing

The OpenLakes Core dashboard is a simple link hub. It does not run health checks
or shared authentication. Each component handles its own login.

By default, the dashboard assumes services live at:

```
{protocol}://{subdomain}.{domain}:{port}
```

To avoid deployment assumptions, set a runtime service list via
`dashboard.env.servicesB64` (base64 JSON array). Each entry can provide a full
`url` or a `host` + `path`:

```json
[
  {
    "name": "Superset",
    "description": "BI and dashboards",
    "url": "https://superset.example.com",
    "icon": "insertChart",
    "category": "Analytics",
    "color": "#20A7C9"
  },
  {
    "name": "Airflow",
    "description": "Workflow orchestration",
    "host": "airflow.internal.local",
    "path": "/home",
    "icon": "widgets",
    "category": "Orchestration",
    "color": "#017CEE"
  }
]
```

Encode and set it:

```bash
export SERVICES_B64=$(cat services.json | base64 | tr -d '\n')
helm upgrade --install 01-infrastructure layers/01-infrastructure \
  --set dashboard.env.servicesB64="${SERVICES_B64}"
```

## Troubleshooting

### Script fails with "Cannot connect to Kubernetes cluster"

Verify your Kubernetes cluster is running and accessible:

```bash
kubectl cluster-info
```

### Script fails with "helm not found"

Install Helm:

```bash
# macOS
brew install helm

# Linux
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### Deployment hangs waiting for a service

The script will wait up to 5 minutes (300 seconds) for each critical service. If a service doesn't become ready:

1. Check pod logs: `kubectl logs -n openlakes <pod-name>`
2. Check events: `kubectl get events -n openlakes --sort-by='.lastTimestamp'`
3. The script will continue anyway after timeout

### Layer 06 (Ingestion) fails

Layer 06 deploys the headless Meltano runtime (Singer orchestration) plus Debezium:

1. Ensure the Meltano PVC is bound: `kubectl get pvc -n openlakes | grep meltano`
2. Check Meltano logs: `kubectl logs -n openlakes deployment/ingestion-meltano`
3. Verify Debezium pod is healthy: `kubectl get pods -n openlakes | grep debezium`
4. Review Debezium logs for connector errors: `kubectl logs -n openlakes deployment/ingestion-debezium`

### Re-running after partial failure

The script is idempotent. Simply re-run it:

```bash
./deploy-openlakes.sh
```

Helm will:
- Upgrade existing releases
- Install missing releases
- Skip completed deployments

## Advanced Usage

### Building pre-baked container images

OpenLakes Core now relies on registry images that already contain all Python dependencies so pods do **not** run `pip install` during startup. The repo ships Dockerfiles under `docker/` for every customized runtime:

| Image | Dockerfile | Purpose |
|-------|------------|---------|
| `ghcr.io/openlakes/core/airflow-runtime` | `docker/airflow-runtime` | Airflow 3.1.2 (Spark/ETL stack) with Papermill + Spark + generic orchestration deps |
| `ghcr.io/openlakes/core/openmetadata-ingestion-runtime` | `docker/openmetadata-ingestion-runtime` | OpenMetadata’s Airflow image with only S3 remote logging deps added |
| `ghcr.io/openlakes/core/meltano-runtime` | `docker/meltano-runtime` | Meltano 4.0.6 runner that executes `meltano install` and idles for orchestrators |

Build and push them (authenticated to GHCR) before running the deploy script:

```bash
# Log in once
echo "${GHCR_TOKEN}" | docker login ghcr.io -u "${GHCR_USER}" --password-stdin

# Airflow runtime (Layer 04 Spark/ETL)
docker build -t ghcr.io/openlakes/core/airflow-runtime:1.0.0 docker/airflow-runtime
docker tag ghcr.io/openlakes/core/airflow-runtime:1.0.0 ghcr.io/openlakes/core/airflow-runtime:1.0
docker tag ghcr.io/openlakes/core/airflow-runtime:1.0.0 ghcr.io/openlakes/core/airflow-runtime:1
docker push ghcr.io/openlakes/core/airflow-runtime:1.0.0
docker push ghcr.io/openlakes/core/airflow-runtime:1.0
docker push ghcr.io/openlakes/core/airflow-runtime:1

# OpenMetadata ingestion runtime (Layer 07)
docker build -t ghcr.io/openlakes/core/openmetadata-ingestion-runtime:1.0.0 docker/openmetadata-ingestion-runtime
docker tag ghcr.io/openlakes/core/openmetadata-ingestion-runtime:1.0.0 ghcr.io/openlakes/core/openmetadata-ingestion-runtime:1.0
docker tag ghcr.io/openlakes/core/openmetadata-ingestion-runtime:1.0.0 ghcr.io/openlakes/core/openmetadata-ingestion-runtime:1
docker push ghcr.io/openlakes/core/openmetadata-ingestion-runtime:1.0.0
docker push ghcr.io/openlakes/core/openmetadata-ingestion-runtime:1.0
docker push ghcr.io/openlakes/core/openmetadata-ingestion-runtime:1

# Meltano runtime
docker build -t ghcr.io/openlakes/core/meltano-runtime:1.0.0 docker/meltano-runtime
docker tag ghcr.io/openlakes/core/meltano-runtime:1.0.0 ghcr.io/openlakes/core/meltano-runtime:1.0
docker tag ghcr.io/openlakes/core/meltano-runtime:1.0.0 ghcr.io/openlakes/core/meltano-runtime:1
docker push ghcr.io/openlakes/core/meltano-runtime:1.0.0
docker push ghcr.io/openlakes/core/meltano-runtime:1.0
docker push ghcr.io/openlakes/core/meltano-runtime:1
```

> Need additional Python packages? Build a derivative image (e.g., `FROM ghcr.io/openlakes/core/airflow-runtime:1.0.0`) instead of re-introducing runtime installs in the Helm charts.

### Remote logging buckets

Both Airflow stacks stream task logs into MinIO so troubleshooting stays centralized:

- **Layer 04 orchestration Airflow** → `orchestration-airflow-logs`
- **Layer 07 catalog Airflow** → `airflow-catalog-logs`

Buckets are created automatically by the respective Helm charts (`airflow.logging.bucket` and `ingestion.logging.bucket`), but you can override the names in the values files if your MinIO deployment uses a different naming convention.

### Custom Values Files

To customize a layer's configuration:

1. Edit the layer's `values.yaml`:
   ```bash
   vim layers/01-infrastructure/values.yaml
   ```

2. Re-run the deployment:
   ```bash
   ./deploy-openlakes.sh
   ```

Helm will apply your changes as an upgrade.

### Deploying Individual Layers

To deploy a single layer manually:

```bash
# Example: Deploy only the catalog layer
helm upgrade --install layer07-catalog ./layers/07-catalog \
  --namespace openlakes \
  --create-namespace \
  --timeout 10m \
  --wait
```

### Uninstalling

To remove all OpenLakes components:

```bash
# Uninstall all releases
helm uninstall -n openlakes \
  01-infrastructure \
  02-compute \
  03-streaming \
  04-orchestration \
  05-analytics \
  layer06-ingestion \
  layer07-catalog

# Delete the namespace
kubectl delete namespace openlakes
```

## Performance Tuning

### Resource Limits

Each layer's `values.yaml` defines resource limits. Adjust based on your cluster capacity:

```yaml
resources:
  limits:
    cpu: "2"
    memory: "4Gi"
```

### Parallel Deployments

While the script deploys layers sequentially, some layers can be deployed in parallel if dependencies allow. Advanced users can modify the script or deploy manually.

### Timeout Adjustment

For slower clusters, increase the timeout:

```bash
./deploy-openlakes.sh --timeout 20m
```

## Known Issues

### OpenMetadata Bot Setup (Disabled by Default)

The automated bot setup has a known JWT authentication issue where the bot token fails to authenticate after creation (HTTP 401 errors). This appears to be a timing/synchronization issue in OpenMetadata's JWT validation.

**Current Status**: The automated bot setup job is **disabled by default** in `layers/07-catalog/values.yaml`:

```yaml
openmetadata:
  automation:
    enabled: false  # Disabled due to known JWT issue
```

**Recommended Approach**: Manually register data sources through the OpenMetadata UI after deployment:

1. Access OpenMetadata UI at `http://localhost:30585`
2. Login with default credentials: `admin` / `admin`
3. Navigate to **Settings** → **Services** → **Add Service**
4. Select service type (Database, Messaging, Pipeline, etc.)
5. Configure connection details using credentials from `layers/07-catalog/values.yaml`

**Experimental**: To enable automated bot setup (may fail):

```bash
# Edit values.yaml
vim layers/07-catalog/values.yaml

# Change automation.enabled to true
# Then redeploy
helm upgrade layer07-catalog ./layers/07-catalog \
  --namespace openlakes \
  --timeout 10m \
  --wait
```

### Meltano First-Boot Install

The Meltano pod runs `meltano install` the first time it starts so all Singer extractors/loaders are available. During this phase the pod may restart if installation takes longer than the default timeout. If that happens:

1. Wait for the PVC to finish populating dependencies.
2. Check logs for progress: `kubectl logs -n openlakes deployment/ingestion-meltano -f`.
3. Once the virtualenv is cached on the PVC, subsequent restarts complete quickly.

## Support

For issues or questions:

1. Check pod logs: `kubectl logs -n openlakes <pod-name>`
2. Check events: `kubectl get events -n openlakes`
3. Review Helm release status: `helm list -n openlakes`
4. Open an issue at: https://github.com/OpenLakes-io/openlakes-core/issues
