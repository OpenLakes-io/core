# Storage Performance Comparison Notebooks

This directory contains notebooks demonstrating the performance difference between direct MinIO access and Alluxio transparent tiering for Nessie + Iceberg workloads.

## Notebooks

### 01-iceberg-direct-minio.ipynb
**Status**: ✅ Complete

**What it demonstrates**:
- Baseline performance with direct MinIO S3A access
- No caching layer - every read goes to network storage
- Repeat queries show **NO speedup** (±10% variance is normal)

**Architecture**:
```
Spark → Nessie (catalog) → Iceberg → Direct MinIO (s3a://)
```

**Key Metrics** (100K rows):
- Write: ~2-5 seconds
- First read: ~0.5-2 seconds (from MinIO)
- Second read: ~0.5-2 seconds (still from MinIO - no caching!)
- Aggregation: ~1-3 seconds each time

**Best for**:
- One-time ETL jobs
- Write-heavy pipelines
- Single-node deployments

---

### 02-iceberg-alluxio-cached.ipynb
**Status**: ✅ Complete

**What it demonstrates**:
- Transparent tiering with Alluxio distributed cache
- First access fetches from MinIO → caches in hot tier (NVMe)
- Repeat access served from hot tier (**50-1000x faster!**)

**Architecture**:
```
Spark → Nessie (catalog) → Iceberg → Alluxio → MinIO
                                    ↓
                              Hot Tier (NVMe cache)
```

**Expected Metrics** (100K rows):
- Write: ~2-5 seconds (same as direct)
- First read: ~0.5-2 seconds (cache miss - fetches from MinIO)
- **Second read: ~0.001-0.01 seconds** (**100-1000x faster!**)
- First aggregation: ~1-3 seconds
- **Repeat aggregation: ~0.01-0.1 seconds** (**50-100x faster!**)

**Best for**:
- Multi-node clusters (4+ nodes)
- Read-heavy analytical workloads
- Dashboards with repeat queries
- Time travel / historical analysis

**Prerequisites**:
- Alluxio enabled (`alluxio.enabled: true` in values.yaml)
- Multi-node cluster (for distributed caching)
- NVMe storage available on each node

**Spark Configuration**:
```python
spark = SparkSession.builder \
    .config("spark.sql.catalog.lakehouse.warehouse", "alluxio://warehouse/") \
    .config("spark.hadoop.fs.alluxio.impl", "alluxio.hadoop.FileSystem") \
    .config("alluxio.master.hostname", "infrastructure-alluxio-master") \
    .getOrCreate()
```

---

### 03-performance-comparison.ipynb
**Status**: 🚧 TODO

**What it demonstrates**:
- Side-by-side comparison with charts
- Speedup calculations (cached vs non-cached)
- Cache hit rate analysis
- When to use each approach

**Charts to include**:
1. **Read Latency**: First vs Second access
2. **Throughput**: Direct MinIO vs Alluxio cached
3. **Cache Hit Rate**: Over multiple queries
4. **Cost/Benefit**: Storage overhead vs performance gain

---

## Quick Start

### Test Direct MinIO (Baseline)

```bash
# Deploy OpenLakes without Alluxio (default)
./deploy-openlakes.sh

# Run baseline notebook
jupyter notebook 01-iceberg-direct-minio.ipynb
```

### Test Alluxio Transparent Tiering

```bash
# Deploy OpenLakes with storage wizard
./deploy-openlakes.sh --configure-storage
# Select: Enable Alluxio? [Y]

# Verify Alluxio is running
kubectl get pods -n openlakes | grep alluxio

# Run Alluxio notebook
jupyter notebook 02-iceberg-alluxio-tiering.ipynb
```

---

## Architecture Comparison

| Feature | Direct MinIO | Alluxio Tiering |
|---------|--------------|-----------------|
| **Latency (first read)** | 50-200ms | 50-200ms (same) |
| **Latency (repeat read)** | 50-200ms | **1-10ms** (50-100x faster) |
| **Cluster requirement** | Single-node OK | Multi-node (4+) |
| **Storage overhead** | None | NVMe cache (150GB/node) |
| **Use case** | Write-heavy, one-time scans | Read-heavy, dashboards |
| **Complexity** | Simple | Requires Alluxio deployment |

---

## Deployment Recommendations

### Single-Node (Laptop, Desktop, Small Server)

**Configuration**:
- MinIO: Standalone mode
- Alluxio: **Disabled** (not needed for single node)
- Storage: Direct S3A access

**Why**: Distributed caching doesn't provide benefits on single node

```bash
# Automatic detection
./deploy-openlakes.sh
# Wizard will detect single-node and disable Alluxio
```

### Multi-Node Cluster (4+ nodes)

**Configuration**:
- MinIO: Distributed mode with erasure coding (EC:4 or EC:2)
- Alluxio: **Enabled** (distributed cache across nodes)
- Hot tier: 150-300GB NVMe per node
- Warm tier: MinIO distributed storage

**Why**: Distributed caching provides massive speedup for analytical queries

```bash
# Deploy with storage wizard
./deploy-openlakes.sh --configure-storage
# Wizard will:
# 1. Detect multi-node cluster
# 2. Configure MinIO with erasure coding
# 3. Enable Alluxio distributed cache
# 4. Set up lifecycle policies
```

---

## Performance Expectations

### Direct MinIO (No Caching)

| Query Type | First Run | Repeat Run | Speedup |
|------------|-----------|------------|---------|
| Full table scan (100K rows) | 0.8s | 0.8s | **None** |
| Aggregation | 1.2s | 1.2s | **None** |
| Time travel (6 snapshots) | 8.0s | 8.0s | **None** |

### Alluxio Transparent Tiering

| Query Type | First Run (cache miss) | Repeat Run (cached) | Speedup |
|------------|----------------------|---------------------|---------|
| Full table scan (100K rows) | 0.8s | **0.01s** | **80x faster** |
| Aggregation | 1.2s | **0.02s** | **60x faster** |
| Time travel (6 snapshots) | 8.0s | **0.1s** | **80x faster** |

---

## Troubleshooting

### Alluxio not starting?

```bash
# Check Alluxio pods
kubectl get pods -n openlakes | grep alluxio

# Check logs
kubectl logs -n openlakes infrastructure-alluxio-master-0

# Verify NVMe mount exists on each node
kubectl exec -n openlakes infrastructure-alluxio-worker-xxx -- ls -la /mnt/openlakes-hot
```

### Poor cache hit rate?

```bash
# Check cache usage
kubectl exec -n openlakes infrastructure-alluxio-master-0 -- alluxio fsadmin report

# Expected output:
# Cache Hit Rate: 85-95% (good)
# Hot Tier Usage: 140GB / 150GB (good - close to full)
#
# If hit rate < 50%:
# - Increase hot tier size
# - Check if data is too large to fit in cache
```

### MinIO erasure coding not working?

```bash
# Check MinIO mode
kubectl get statefulset -n openlakes infrastructure-minio -o yaml | grep replicas

# Single node: replicas: 1 (standalone mode)
# Multi-node: replicas: 4+ (distributed with EC)

# Verify node count
kubectl get nodes

# Need 4+ nodes for erasure coding
```

---

## Next Steps

1. **Run notebook 01** to establish baseline
2. **Deploy with Alluxio** (if multi-node cluster)
3. **Run notebook 02** to see performance improvement
4. **Monitor cache hit rates** and adjust hot tier size

For full documentation, see:
- [STORAGE-QUICK-START.md](../../STORAGE-QUICK-START.md)
- [docs/ALLUXIO-TRANSPARENT-TIERING.md](../../docs/ALLUXIO-TRANSPARENT-TIERING.md)
