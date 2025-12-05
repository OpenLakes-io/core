# Alluxio Deployment for OpenLakes

OpenLakes uses the **official Alluxio Helm chart** from the Alluxio project, maintained locally in the repository.

---

## Implementation

**Chart Source**: https://github.com/Alluxio/alluxio/tree/master-2.x/integration/kubernetes/helm-chart/alluxio

**Chart Version**: 0.6.54 (Alluxio 2.9.3)

**Location**: `layers/01-infrastructure/charts/alluxio/`

### Why Local Chart?

Alluxio doesn't publish their Helm chart to a public repository. Instead:

1. ✅ **Downloaded from GitHub** - Official chart from Alluxio repo
2. ✅ **Stored locally** - Committed to OpenLakes repository
3. ✅ **Version controlled** - OpenLakes controls when to update
4. ✅ **Customizable** - Can apply patches if needed

### Dependency Configuration

**Chart.yaml**:
```yaml
dependencies:
  - name: alluxio
    version: "0.6.54"
    repository: "file://./charts/alluxio"
    condition: alluxio.enabled
```

This approach:
- Uses official, battle-tested templates from Alluxio team
- Gives OpenLakes control over versioning
- Allows sync with upstream when needed
- Enables local patches/customizations

---

## Configuration

Alluxio is configured via `values.yaml` using the official chart's structure:

### Key Configuration Sections

**Properties** (alluxio-site.properties):
```yaml
alluxio:
  properties:
    # Master
    alluxio.master.hostname: infrastructure-alluxio-master
    alluxio.master.mount.table.root.ufs: s3a://openlakes/

    # MinIO S3A understore
    alluxio.underfs.s3.endpoint: http://infrastructure-minio:9000
    s3a.access.key: admin
    s3a.secret.key: admin123

    # LRU block annotation (Alluxio 2.3.0+)
    alluxio.worker.block.annotator.class: alluxio.worker.block.annotator.LRUAnnotator

    # Caching behavior
    alluxio.user.file.readtype.default: CACHE
    alluxio.user.file.writetype.default: CACHE_THROUGH
    alluxio.user.file.passive.cache.enabled: "true"
```

**Master Deployment**:
```yaml
alluxio:
  master:
    enabled: true
    count: 1
    resources:
      requests:
        cpu: 500m
        memory: 4Gi
```

**Worker Deployment** (ETL nodes only):
```yaml
alluxio:
  worker:
    enabled: true
    nodeSelector:
      openlakes.io/etl-node: "true"  # Deploy only on labeled ETL nodes
    hostNetwork: true
    hostPID: true
    tieredstore:
      levels:
      - level: 0
        alias: MEM
        quota: 16GB
      - level: 1
        alias: SSD
        path: /mnt/openlakes-hot
        quota: 150GB  # Set by configure-storage.sh wizard
```

---

## Features

### Enabled by Default

- ✅ **LRU Block Annotation** - Least recently used eviction
- ✅ **Two-Level Tiering** - Memory (16GB) + NVMe SSD (configurable)
- ✅ **MinIO Integration** - S3A understore for warm/cold tiers
- ✅ **ETL Node Affinity** - Deploy only on selected worker nodes
- ✅ **Short-Circuit Reads** - Direct local access when co-located with Spark
- ✅ **Passive Caching** - Automatic cache on read
- ✅ **Metrics** - Prometheus integration

### Available (Optional)

The official chart provides additional features that can be enabled:

**CSI Driver** - Persistent volume claims via Alluxio:
```yaml
csi:
  enabled: true
```

**FUSE Daemon** - Mount Alluxio as POSIX filesystem:
```yaml
fuse:
  enabled: true
```

**Log Server** - Centralized logging:
```yaml
logserver:
  enabled: true
```

**Proxy** - External access layer:
```yaml
proxy:
  enabled: true
```

---

## Updating Alluxio

When Alluxio releases a new version (e.g., 2.10.0):

### Step 1: Download New Chart

```bash
cd layers/01-infrastructure/charts

# Backup current version
mv alluxio alluxio-backup-$(date +%Y%m%d)

# Download new version
ALLUXIO_VERSION="2.10.0"
curl -sL https://github.com/Alluxio/alluxio/archive/refs/tags/v${ALLUXIO_VERSION}.tar.gz | \
  tar -xz --strip-components=4 -C . \
  alluxio-${ALLUXIO_VERSION}/integration/kubernetes/helm-chart/alluxio
```

### Step 2: Update Chart Dependency

Check the new chart version:
```bash
cat alluxio/Chart.yaml | grep "^version:"
```

Update `Chart.yaml`:
```yaml
dependencies:
  - name: alluxio
    version: "0.6.XX"  # New version
    repository: "file://./charts/alluxio"
```

### Step 3: Review Breaking Changes

```bash
# Check changelog
cat alluxio/CHANGELOG.md

# Compare values.yaml structure
diff alluxio-backup-*/values.yaml alluxio/values.yaml
```

### Step 4: Update Dependencies and Test

```bash
cd layers/01-infrastructure
helm dependency update

# Test with dry-run
helm upgrade --install 01-infrastructure . \
  --namespace openlakes \
  --dry-run --debug
```

### Step 5: Commit Changes

```bash
git add charts/alluxio/ Chart.yaml Chart.lock
git commit -m "chore: Update Alluxio chart to v${NEW_VERSION}"
```

---

## Integration with Storage Wizard

The `configure-storage.sh` wizard automatically configures Alluxio:

1. **Single-Node**: Alluxio disabled (not beneficial)
2. **Multi-Node**:
   - Select ETL worker nodes
   - Calculate cache size (25% of smallest ETL node)
   - Configure LRU annotation policy
   - Generate values for `layers/01-infrastructure/values.yaml`

The wizard updates:
- `storage.etlNodes` - List of selected ETL nodes
- `alluxio.enabled` - Enable/disable based on cluster type
- `alluxio.worker.tieredstore.levels[1].quota` - Dynamic cache size

---

## Deployment

Alluxio is deployed as part of the infrastructure layer:

```bash
# Deploy infrastructure (includes Alluxio)
./deploy-openlakes.sh --layer 01-infrastructure

# Or deploy all layers
./deploy-openlakes.sh
```

### Verify Deployment

```bash
# Check master
kubectl get statefulset -n openlakes -l app=alluxio,role=alluxio-master

# Check workers (on ETL nodes only)
kubectl get daemonset -n openlakes -l app=alluxio,role=alluxio-worker

# Check pods
kubectl get pods -n openlakes -l app=alluxio

# Access Alluxio web UI
kubectl port-forward -n openlakes svc/alluxio-master-0 19999:19999
# Open: http://localhost:19999
```

---

## Troubleshooting

### Workers Not Starting

**Check node labels**:
```bash
kubectl get nodes -L openlakes.io/etl-node
```

**Label nodes manually** if needed:
```bash
kubectl label nodes <node-name> openlakes.io/etl-node=true
```

### MinIO Connection Issues

**Check S3A configuration**:
```bash
kubectl logs -n openlakes alluxio-master-0 | grep -i s3
```

**Verify MinIO is running**:
```bash
kubectl get svc -n openlakes infrastructure-minio
```

### Cache Not Working

**Check passive caching enabled**:
```bash
kubectl exec -n openlakes alluxio-master-0 -- alluxio info get alluxio.user.file.passive.cache.enabled
```

**Check tier quotas**:
```bash
kubectl exec -n openlakes alluxio-master-0 -- alluxio info report
```

---

## References

- [Alluxio Kubernetes Guide](https://docs.alluxio.io/os/user/stable/en/kubernetes/Install-Alluxio-On-Kubernetes.html)
- [Official Helm Chart (GitHub)](https://github.com/Alluxio/alluxio/tree/master-2.x/integration/kubernetes/helm-chart/alluxio)
- [Configuration Properties](https://docs.alluxio.io/os/user/stable/en/reference/Properties-List.html)
- [Block Annotation Policies](https://docs.alluxio.io/os/user/stable/en/core-services/Caching.html#block-annotation-policies)
