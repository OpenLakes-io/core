# OpenLakes Three-Tier Storage Architecture

## Overview

OpenLakes implements a three-tier storage architecture optimized for maximum object storage performance across both single-node and multi-node deployments:

```
┌─────────────────────────────────────────────────────────────┐
│                    🔥 HOT TIER (NVMe)                       │
│  Sub-millisecond latency • Local node storage • Alluxio    │
│  Use case: Active workloads, frequent access, checkpoints  │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│            ♨️  WARM TIER (Distributed MinIO)                │
│  <10ms latency • Erasure coded • Multi-node distributed    │
│  Use case: Working datasets, intermediate results, tables  │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│              ❄️  COLD TIER (Archive Storage)                │
│  Seconds latency • Compressed • NFS/S3/Local mount         │
│  Use case: Long-term retention, compliance, backups        │
└─────────────────────────────────────────────────────────────┘
```

## Architecture Components

### 1. Hot Tier - NVMe Local Storage

**Technology**: Alluxio distributed cache backed by NVMe storage

**Characteristics**:
- **Latency**: Sub-millisecond (typically 50-200 microseconds)
- **Capacity**: 30-40% of node storage (user-configurable)
- **Deployment**: DaemonSet on each node + StatefulSet for master
- **Data Locality**: Data co-located with compute for zero-network latency

**Configuration**:
```yaml
alluxio:
  enabled: true
  worker:
    nvme:
      enabled: true
      path: /mnt/nvme
      size: 100Gi  # Per node
    memory:
      enabled: true
      size: 16Gi   # RAM cache tier
```

**Use Cases**:
- Spark shuffle data and RDD caching
- Active JupyterHub notebook workloads
- Checkpoint files for streaming jobs
- Temporary computation results

### 2. Warm Tier - Distributed MinIO

**Technology**: MinIO in distributed mode with erasure coding

**Characteristics**:
- **Latency**: <10 milliseconds (network-dependent)
- **Capacity**: 50-60% of remaining storage after hot tier
- **Deployment**: StatefulSet with erasure coding (EC:4 for 4+ nodes)
- **Durability**: Survives up to 4 simultaneous node failures (EC:4)

**Single-Node Configuration**:
```yaml
minio:
  enabled: true
  mode: standalone
  replicas: 1
  persistence:
    size: 200Gi
```

**Multi-Node Configuration** (4+ nodes):
```yaml
minio:
  enabled: true
  mode: distributed
  replicas: 4  # Matches node count
  persistence:
    size: 200Gi  # Per node
  erasureCoding:
    enabled: true
    scheme: EC:4  # 4 data + 4 parity shards
```

**Effective Capacity** (EC:4):
- Raw capacity: 200GB × 4 nodes = 800GB
- Usable capacity: 400GB (50% due to 4 parity shards)
- Survives: 4 node failures

**Use Cases**:
- Iceberg/Delta Lake table storage
- Parquet/ORC data files
- Intermediate ETL results
- Trino query working data

### 3. Cold Tier - Archive Storage

**Technology**: Configurable (NFS / S3 / Local mount / Cloud storage)

**Characteristics**:
- **Latency**: Seconds to minutes (depends on backend)
- **Capacity**: Unlimited (for cloud) or remaining local storage
- **Deployment**: Varies by backend type
- **Compression**: Data typically compressed before archival

**Local Mount Configuration**:
```yaml
storage:
  cold:
    enabled: true
    type: local
    path: /mnt/cold
    size: 500Gi
```

**NFS Configuration**:
```yaml
storage:
  cold:
    enabled: true
    type: nfs
    nfs:
      server: 192.168.1.100
      path: /exports/openlakes-archive
```

**S3 Configuration**:
```yaml
storage:
  cold:
    enabled: true
    type: s3
    s3:
      bucket: openlakes-archive
      region: us-west-2
      storageClass: GLACIER
```

**Use Cases**:
- Historical data archival (>90 days old)
- Compliance and audit logs
- Backup snapshots
- Infrequently accessed datasets

## Automatic Data Tiering

### Lifecycle Policies

OpenLakes uses MinIO lifecycle policies to automatically tier data based on age and access patterns:

```yaml
minio:
  buckets:
    - name: openlakes
      lifecycle:
        # Tier to warm after 7 days in hot cache
        - id: hot-to-warm
          transition:
            days: 7
            storageClass: WARM

        # Tier to cold after 90 days
        - id: warm-to-cold
          transition:
            days: 90
            storageClass: COLD

        # Delete after 365 days (optional)
        - id: cold-expiry
          expiration:
            days: 365
```

### Access Pattern Detection

Alluxio automatically promotes frequently accessed data from warm to hot tier:

```yaml
alluxio:
  master:
    metadataSync:
      enabled: true
      interval: 5m

  worker:
    tiering:
      policy: LRU  # Least Recently Used eviction
      promotionEnabled: true
      quotaEnabled: true
```

## Interactive Storage Configuration

### Quick Start

Run the interactive storage wizard:

```bash
./configure-storage.sh
```

The wizard will:

1. **Detect node storage** - Query all nodes for available capacity
2. **Configure hot tier** - Allocate NVMe storage uniformly across nodes
3. **Configure warm tier** - Auto-calculate from remaining capacity
4. **Configure cold tier** - Present options and allow selection
5. **Generate config** - Create `/tmp/openlakes-storage-config.yaml`

### Wizard Flow

```
Step 1: Detecting Node Storage
  ✓ Found 4 nodes in cluster

  Node: node-01
    Total Storage:       500GB
    Allocatable Storage: 450GB
    ✓ NVMe storage class detected

  Node: node-02
    Total Storage:       500GB
    Allocatable Storage: 450GB
    ✓ NVMe storage class detected
  ...

Step 2: Configure Hot Tier (NVMe Local Storage)

  Based on your cluster, we recommend:
    Hot Tier Size: 135GB per node
    (This leaves 315GB per node for warm/cold tiers)

  Enter hot tier size in GB per node (or press Enter for 135GB): 150

  ✓ Hot tier configured: 150GB per node

  Hot Tier Summary:
    Size per node:   150GB
    Storage class:   nvme-local
    Total capacity:  600GB

  Confirm hot tier configuration? [Y/n]: y

Step 3: Configure Warm Tier (Distributed Object Storage)

  Remaining storage per node: 300GB

  Recommended warm tier allocation:
    Warm Tier Size: 180GB per node
    (This leaves 120GB per node for cold tier)

  Multi-node setup: MinIO will run in distributed mode with erasure coding
    Erasure coding will be configured for EC:4 (4 data + 4 parity shards)
    This provides tolerance for up to 4 simultaneous node failures

  Enter warm tier size in GB per node (or press Enter for 180GB):

  ✓ Warm tier configured: 180GB per node

  Warm Tier Summary:
    Size per node:   180GB
    MinIO mode:      distributed
    Replicas:        4
    Total capacity:  720GB
    Erasure coding:  EC:4 (survives 4 node failures)
    Usable capacity: 360GB (50% with EC:4)

  Confirm warm tier configuration? [Y/n]: y

Step 4: Configure Cold Tier (Archive Storage)

  Remaining storage per node: 120GB

  Available cold storage options:

    1. Local storage on cluster nodes
       - Uses remaining local disk space
       - Capacity: 120GB per node
       - Performance: Good (local disk)

    2. /cold mount point (detected)
       - Dedicated cold storage mount
       - Capacity: 2000GB
       - Performance: Depends on underlying storage

    3. NFS storage (detected: nfs-provisioner)
       - Network File System
       - Capacity: Dynamic (based on NFS server)
       - Performance: Network-dependent

    4. Register new NFS server
       - Configure custom NFS mount

    5. Cloud object storage (S3/GCS/Azure)
       - External cloud storage
       - Capacity: Unlimited (pay-per-use)
       - Performance: Network-dependent, higher latency

    6. Skip cold tier configuration

  Select cold storage option [1-6]: 2

  ✓ Selected: Mount point /cold (2000GB)

  Cold Tier Summary:
    Type:            mount
    Mount point:     /cold
    Capacity:        2000GB

  Confirm cold tier configuration? [Y/n]: y

Step 5: Generate Storage Configuration

  ✓ Configuration file generated: /tmp/openlakes-storage-config.yaml

  ═══════════════════════════════════════════════════════════
              Storage Configuration Summary
  ═══════════════════════════════════════════════════════════

  Hot Tier (Fastest - Sub-millisecond latency)
    ├─ Size per node:  150GB
    ├─ Storage class:  nvme-local
    └─ Total capacity: 600GB

  Warm Tier (Fast - <10ms latency)
    ├─ Size per node:  180GB
    ├─ MinIO mode:     distributed
    ├─ Replicas:       4
    ├─ Erasure coding: EC:4
    ├─ Raw capacity:   720GB
    └─ Usable:         360GB (50% with EC:4)

  Cold Tier (Archive - Seconds latency)
    ├─ Type:           mount
    ├─ Mount point:    /cold
    └─ Capacity:       2000GB

  ═══════════════════════════════════════════════════════════

  Next Steps:

  1. Review the configuration file:
     /tmp/openlakes-storage-config.yaml

  2. Apply this configuration to your OpenLakes deployment:
     ./deploy-openlakes.sh --storage-config /tmp/openlakes-storage-config.yaml

  3. Or manually integrate into your values files:
     - layers/01-infrastructure/values.yaml (for MinIO warm tier)
     - layers/05-analytics/values.yaml (for JupyterHub hot tier access)
```

## Deployment Integration

### Option 1: Interactive Wizard During Deployment

Run storage wizard automatically before deployment:

```bash
./deploy-openlakes.sh --configure-storage
```

### Option 2: Use Pre-Generated Configuration

Generate configuration separately, then deploy:

```bash
# Step 1: Generate storage config
./configure-storage.sh

# Step 2: Review configuration
cat /tmp/openlakes-storage-config.yaml

# Step 3: Deploy with storage config
./deploy-openlakes.sh --storage-config /tmp/openlakes-storage-config.yaml
```

### Option 3: Manual Configuration

Edit layer values files directly:

**layers/01-infrastructure/values.yaml**:
```yaml
minio:
  mode: distributed
  replicas: 4
  persistence:
    size: 180Gi

  buckets:
    - name: openlakes
      lifecycle:
        - id: tier-to-warm
          transition:
            days: 7
            storageClass: "WARM"
        - id: tier-to-cold
          transition:
            days: 90
            storageClass: "COLD"

alluxio:
  enabled: true
  master:
    replicas: 1
  worker:
    resources:
      limits:
        memory: 16Gi
    tieredstore:
      levels:
        - level: 0
          alias: MEM
          path: /dev/shm
          type: MEM
          quota: 16GB
        - level: 1
          alias: SSD
          path: /mnt/nvme
          type: SSD
          quota: 150GB
```

## Performance Tuning

### Alluxio Cache Hit Optimization

Monitor cache hit rates:

```bash
# Check Alluxio metrics
kubectl exec -n openlakes alluxio-master-0 -- alluxio fsadmin report metrics

# Expected output:
# Local Cache Hit Rate: >80% (good)
# Remote Cache Hit Rate: >90% (excellent)
```

Tune cache policies:

```yaml
alluxio:
  properties:
    # Pin frequently accessed paths to cache
    alluxio.user.file.writetype.default: CACHE_THROUGH
    alluxio.user.file.readtype.default: CACHE_PROMOTE

    # Increase metadata cache
    alluxio.master.metadatastore.rocks.cache.size: 1GB
```

### MinIO Erasure Coding Tuning

For 4-node cluster:
```yaml
minio:
  # EC:4 = 4 data + 4 parity (50% overhead, survives 4 failures)
  erasureCoding: EC:4
```

For 8-node cluster:
```yaml
minio:
  # EC:2 = 8 data + 2 parity (25% overhead, survives 2 failures)
  # Better capacity efficiency but less fault tolerance
  erasureCoding: EC:2
```

### Spark Integration

Configure Spark to use tiered storage:

```python
spark = SparkSession.builder \
    .config("spark.hadoop.fs.s3a.endpoint", "http://infrastructure-minio:9000") \
    .config("spark.hadoop.fs.s3a.path.style.access", "true") \
    .config("spark.sql.adaptive.enabled", "true") \
    .config("spark.sql.adaptive.coalescePartitions.enabled", "true") \
    .getOrCreate()

# Write to hot tier (Alluxio cache)
df.write.mode("overwrite") \
    .option("path", "alluxio://infrastructure-alluxio-master:19998/data/hot/table") \
    .saveAsTable("hot_table")

# Write to warm tier (MinIO)
df.write.mode("overwrite") \
    .option("path", "s3a://openlakes/data/warm/table") \
    .saveAsTable("warm_table")

# Read from cold tier (archive)
df = spark.read.parquet("s3a://openlakes-archive/data/cold/table")
```

## Monitoring and Observability

### Storage Metrics Dashboard

Key metrics to monitor:

1. **Hot Tier (Alluxio)**:
   - Cache hit rate (target: >80%)
   - Cache capacity used (%)
   - Eviction rate (lower is better)

2. **Warm Tier (MinIO)**:
   - Total capacity used (%)
   - Read/write throughput
   - Replication lag (multi-node)

3. **Cold Tier**:
   - Archive storage used (%)
   - Data retrieval latency
   - Lifecycle policy compliance

### Prometheus Queries

```promql
# Alluxio cache hit rate
100 * (alluxio_worker_bytes_read_local / (alluxio_worker_bytes_read_local + alluxio_worker_bytes_read_remote))

# MinIO capacity utilization
100 * (minio_cluster_capacity_usable_total_bytes - minio_cluster_capacity_usable_free_bytes) / minio_cluster_capacity_usable_total_bytes

# Data tier distribution
sum(minio_bucket_objects_count{tier="hot"})
sum(minio_bucket_objects_count{tier="warm"})
sum(minio_bucket_objects_count{tier="cold"})
```

## Scaling Considerations

### Single Node → Multi-Node

When expanding from 1 to 4+ nodes:

1. **Backup existing data** in MinIO
2. **Run storage wizard** with new node count
3. **Migrate to distributed mode**:
   ```bash
   # Update values.yaml
   minio:
     mode: distributed
     replicas: 4

   # Redeploy infrastructure layer
   helm upgrade --install 01-infrastructure ./layers/01-infrastructure \
     --namespace openlakes \
     --values layers/01-infrastructure/values.yaml
   ```
4. **Restore data** to distributed MinIO
5. **Deploy Alluxio workers** on new nodes

### Adding More Nodes

For 8+ node clusters:

```yaml
minio:
  replicas: 8
  erasureCoding: EC:2  # More efficient for large clusters

alluxio:
  worker:
    replicas: 8  # One worker per node
```

## Troubleshooting

### Hot Tier Issues

**Problem**: Low cache hit rate (<50%)

**Solution**:
```bash
# Check Alluxio worker capacity
kubectl exec -n openlakes alluxio-worker-0 -- alluxio fsadmin report capacity

# Increase NVMe allocation
# Edit configure-storage.sh and rerun wizard
```

**Problem**: Alluxio worker out of space

**Solution**:
```bash
# Manually evict old data
kubectl exec -n openlakes alluxio-worker-0 -- alluxio fs free /path/to/old/data

# Or increase eviction rate
# Edit alluxio properties to be more aggressive
```

### Warm Tier Issues

**Problem**: MinIO distributed mode not working

**Solution**:
```bash
# Check MinIO pod status
kubectl get pods -n openlakes -l app=minio

# Verify erasure coding is active
kubectl logs -n openlakes infrastructure-minio-0 | grep "erasure"

# Expected: "Erasure sets: 1, drives per erasure set: 8"
```

**Problem**: Data not replicating across nodes

**Solution**:
```bash
# Check MinIO health
kubectl exec -n openlakes infrastructure-minio-0 -- mc admin info local

# Verify all nodes are online
# Add --force flag to heal if needed
kubectl exec -n openlakes infrastructure-minio-0 -- mc admin heal local --force
```

### Cold Tier Issues

**Problem**: NFS mount not accessible

**Solution**:
```bash
# Test NFS connectivity from pod
kubectl run -it --rm nfs-test --image=busybox --restart=Never -- sh
mount -t nfs 192.168.1.100:/exports/openlakes /mnt

# Check NFS server exports
# On NFS server:
exportfs -v
```

## Best Practices

1. **Hot Tier**:
   - Allocate 30-40% of NVMe storage for hot tier
   - Enable data locality (co-locate compute and storage)
   - Monitor cache hit rates regularly

2. **Warm Tier**:
   - Use distributed mode for 4+ nodes
   - Configure erasure coding based on fault tolerance needs
   - Set up lifecycle policies for automatic tiering

3. **Cold Tier**:
   - Use compression for archived data
   - Implement retention policies
   - Regular backup validation

4. **General**:
   - Run storage wizard for initial configuration
   - Review and adjust lifecycle policies quarterly
   - Monitor capacity and performance metrics

## Additional Resources

- [Alluxio Documentation](https://docs.alluxio.io/)
- [MinIO Erasure Coding Guide](https://min.io/docs/minio/linux/operations/concepts/erasure-coding.html)
- [Apache Iceberg Table Formats](https://iceberg.apache.org/)
- [Spark Performance Tuning](https://spark.apache.org/docs/latest/tuning.html)
