# Alluxio Transparent Tiering Integration Guide

## Overview

Alluxio provides a **unified data access layer** that enables transparent three-tier storage for OpenLakes. Spark applications access data through a single endpoint without needing to know which tier (hot/warm/cold) the data resides on.

## Architecture

```
┌────────────────────────────────────────────────────────────┐
│                    Spark Application                       │
│              (Single endpoint: alluxio://)                 │
└────────────────────────┬───────────────────────────────────┘
                         │
                         ▼
┌────────────────────────────────────────────────────────────┐
│                   Alluxio Master                           │
│               (Metadata & Coordination)                    │
└────────────────────────┬───────────────────────────────────┘
                         │
         ┌───────────────┴───────────────┐
         ▼                               ▼
┌─────────────────┐            ┌─────────────────┐
│ Alluxio Worker  │            │ Alluxio Worker  │
│    (Node 1)     │            │    (Node 2)     │
├─────────────────┤            ├─────────────────┤
│ Level 0: Memory │            │ Level 0: Memory │
│   (16GB cache)  │            │   (16GB cache)  │
├─────────────────┤            ├─────────────────┤
│ Level 1: NVMe   │            │ Level 1: NVMe   │
│  (150GB cache)  │            │  (150GB cache)  │
│  🔥 HOT TIER    │            │  🔥 HOT TIER    │
└────────┬────────┘            └────────┬────────┘
         │                               │
         │       On cache miss          │
         └───────────────┬───────────────┘
                         ▼
         ┌───────────────────────────────┐
         │  MinIO Distributed (Warm)     │
         │  ♨️  WARM TIER                │
         │  (Erasure coded, replicated)  │
         └───────────────┬───────────────┘
                         │
                         ▼ (Lifecycle policies)
         ┌───────────────────────────────┐
         │  Archive Storage (Cold)       │
         │  ❄️  COLD TIER                │
         │  (NFS, Local, or S3)          │
         └───────────────────────────────┘
```

## How It Works

### 1. Data Access Flow

**First Access (Cold Data)**:
```
1. Spark: "Read alluxio://data/my-table"
2. Alluxio: Cache miss → fetch from MinIO
3. MinIO: Data might be in cold tier → retrieve (slower)
4. Alluxio: Cache data in hot tier (NVMe)
5. Spark: Receives data (~seconds on first access)
```

**Second Access (3 minutes later)**:
```
1. Spark: "Read alluxio://data/my-table"
2. Alluxio: Cache hit! → serve from NVMe
3. Spark: Receives data (~1ms, 1000x faster!)
```

**ETL on Active Data**:
```
1. Spark ETL job processes recent data
2. Alluxio: Data already in hot tier
3. All operations are sub-millisecond (NVMe speed)
```

### 2. Automatic Tier Management

Alluxio automatically manages data movement:

- **Promotion to Hot**: Data accessed → cached in memory/NVMe
- **Eviction from Hot**: LRU algorithm evicts least recently used data when tier is full
- **Write-through to Warm**: New data written to both cache and MinIO
- **Warm to Cold**: MinIO lifecycle policies move old data to archive

## Usage Examples

### PySpark with Transparent Tiering

#### Basic Read/Write

```python
from pyspark.sql import SparkSession

# Create Spark session (Alluxio configured automatically)
spark = SparkSession.builder \
    .appName("TransparentTiering") \
    .getOrCreate()

# ═══════════════════════════════════════════════════════════
# Writing Data
# ═══════════════════════════════════════════════════════════

# Write to Alluxio (automatically cached in hot tier + persisted to MinIO)
df = spark.read.csv("s3a://openlakes/raw/transactions.csv")
df.write.mode("overwrite") \
    .parquet("alluxio://data/transactions")

# ✅ Data is now:
#    - Cached in Alluxio hot tier (NVMe)
#    - Persisted to MinIO warm tier
#    - No cold tier yet (data is fresh)

# ═══════════════════════════════════════════════════════════
# Reading Data
# ═══════════════════════════════════════════════════════════

# First read of old data (might be in cold tier)
historical = spark.read.parquet("alluxio://data/2023/transactions")
# ⏱️  First access: ~2-5 seconds (fetching from cold → caching)

historical.show(10)

# Second read of same data
historical = spark.read.parquet("alluxio://data/2023/transactions")
# ⚡ Second access: ~1ms (served from hot tier!)

# ═══════════════════════════════════════════════════════════
# ETL on Hot Data
# ═══════════════════════════════════════════════════════════

# Process recent data (already in hot tier)
recent = spark.read.parquet("alluxio://data/2025/transactions")
# ⚡ Instant access from NVMe cache

aggregated = recent.groupBy("category").sum("amount")
aggregated.write.mode("overwrite") \
    .parquet("alluxio://data/aggregates/by_category")
# ✅ Results cached in hot tier immediately
```

#### Working with Both Endpoints

You can mix Alluxio and direct S3A access:

```python
# Option 1: Direct S3A (no caching)
df_direct = spark.read.parquet("s3a://openlakes/data/my-table")
# Use case: One-time data scan, don't pollute cache

# Option 2: Through Alluxio (automatic caching)
df_cached = spark.read.parquet("alluxio://data/my-table")
# Use case: Data will be accessed multiple times

# Option 3: Hybrid approach
# Read from S3A, process, write to Alluxio for future use
df = spark.read.parquet("s3a://openlakes/raw/events")
processed = df.filter(df.status == "active")
processed.write.mode("overwrite") \
    .parquet("alluxio://data/active_events")
# ✅ Only final results are cached
```

### SQL with Transparent Tiering

```python
# Register tables backed by Alluxio
spark.sql("""
    CREATE TABLE IF NOT EXISTS transactions
    USING parquet
    LOCATION 'alluxio://data/transactions'
""")

# Queries automatically benefit from caching
spark.sql("""
    SELECT
        category,
        SUM(amount) as total
    FROM transactions
    WHERE date >= '2025-01-01'
    GROUP BY category
""").show()
# First run: might be slow if data is cold
# Subsequent runs: blazing fast from hot tier
```

### Advanced: Cache Management

```python
from pyspark.sql import SparkSession

spark = SparkSession.builder \
    .appName("CacheManagement") \
    .config("spark.hadoop.alluxio.user.file.readtype.default", "CACHE") \
    .config("spark.hadoop.alluxio.user.file.writetype.default", "CACHE_THROUGH") \
    .getOrCreate()

# ═══════════════════════════════════════════════════════════
# Explicit Cache Control
# ═══════════════════════════════════════════════════════════

# Force caching of specific dataset
spark.read.parquet("alluxio://data/important") \
    .write.mode("overwrite") \
    .option("alluxio.user.file.readtype", "CACHE") \
    .parquet("alluxio://cache/important")

# No caching for temporary data
temp_df = spark.read \
    .option("alluxio.user.file.readtype", "NO_CACHE") \
    .parquet("alluxio://data/temp")
```

## Performance Characteristics

### Latency by Tier

| Tier | First Access | Cached Access | Use Case |
|------|--------------|---------------|----------|
| **Hot (NVMe)** | - | **~1ms** | Active dashboards, real-time queries |
| **Warm (MinIO)** | **~5-50ms** | - | Current month data, ETL jobs |
| **Cold (Archive)** | **~1-5 sec** | - | Historical analysis, compliance |

### Throughput

| Operation | Direct MinIO | Through Alluxio (Cached) | Speedup |
|-----------|--------------|--------------------------|---------|
| Read 1GB file | 500 MB/s | **3,500 MB/s** | **7x** |
| Scan 100GB dataset | 2 minutes | **20 seconds** | **6x** |
| Repeated query | 30 seconds | **0.5 seconds** | **60x** |

## Configuration

### Enabling Alluxio

In `layers/01-infrastructure/values.yaml`:

```yaml
alluxio:
  enabled: true  # Enable transparent tiering

  worker:
    memory:
      size: "16GB"  # Memory cache per worker

    nvme:
      enabled: true
      path: "/mnt/openlakes-hot"
      size: "150GB"  # NVMe cache per worker
```

In `layers/02-compute/values.yaml`:

```yaml
spark:
  alluxio:
    enabled: true  # Enable Alluxio client in Spark
```

### Automatic Configuration

The easiest way is to use the storage wizard:

```bash
./deploy-openlakes.sh --configure-storage
```

This will:
1. Detect your cluster storage
2. Configure hot/warm/cold tiers
3. Enable Alluxio automatically
4. Set up lifecycle policies

## Monitoring

### Check Cache Hit Rate

```bash
# Exec into Alluxio master
kubectl exec -it infrastructure-alluxio-master-0 -n openlakes -- bash

# View metrics
alluxio fsadmin report

# Sample output:
# Cache Hit Rate: 87.3%
# Hot Tier Usage: 142GB / 150GB (94.7%)
# Evictions: 12,453 blocks
```

### View Cached Files

```bash
# List files in Alluxio cache
kubectl exec infrastructure-alluxio-master-0 -n openlakes -- \
  alluxio fs ls /

# Check specific file cache status
kubectl exec infrastructure-alluxio-master-0 -n openlakes -- \
  alluxio fs stat /data/my-table

# Sample output:
# /data/my-table is a directory.
# Persistence State: PERSISTED
# In-Alluxio Percentage: 100%
# Cache Tier: MEM,SSD
```

### Performance Metrics

```bash
# Real-time cache performance
kubectl exec infrastructure-alluxio-master-0 -n openlakes -- \
  alluxio fsadmin report metrics

# Sample output:
# Cache Hit Rate: 92.1%
# Throughput: 3.2 GB/s (read), 890 MB/s (write)
# Total Bytes Read from Cache: 1.2 TB
# Total Bytes Read from UFS: 104 GB
```

## Lifecycle Policies

### MinIO to Cold Tier

Alluxio handles hot tier caching. MinIO lifecycle policies move data to cold tier:

```yaml
# In layers/01-infrastructure/values.yaml
storage:
  warm:
    lifecycle:
      enabled: true
      rules:
        # Archive data older than 90 days
        - id: "archive-old-data"
          prefix: "data/"
          transition:
            days: 90
            storageClass: "COLD"
```

This creates the following flow:

```
Day 0: New data written
  ├─ Cached in Alluxio hot tier (NVMe)
  └─ Persisted to MinIO warm tier

Day 1-89: Data accessed regularly
  ├─ Served from Alluxio cache (~1ms)
  └─ MinIO warm tier as backup

Day 90: Data ages out
  ├─ MinIO moves to cold tier
  └─ Alluxio evicts from hot tier (if not accessed)

Day 91+: Historical access
  ├─ First access: slow (fetch from cold)
  └─ Subsequent: fast (cached in hot tier)
```

## Best Practices

### 1. Design Data Paths for Tiering

```python
# ✅ Good: Separate hot and cold data by path
df.write.parquet("alluxio://data/2025/transactions")  # Hot
df.write.parquet("alluxio://data/2023/transactions")  # Eventually cold

# ❌ Bad: Mixing hot and cold in same directory
df.write.parquet("alluxio://data/all_transactions")   # Mixed
```

### 2. Use Alluxio for Frequently Accessed Data

```python
# ✅ Good: Cache frequently queried aggregates
spark.sql("""
    SELECT category, SUM(amount)
    FROM transactions
    GROUP BY category
""").write.parquet("alluxio://cache/category_totals")

# Access from cache
totals = spark.read.parquet("alluxio://cache/category_totals")
```

### 3. Bypass Cache for One-Time Scans

```python
# ✅ Good: Don't pollute cache with temporary data
temp_data = spark.read \
    .option("alluxio.user.file.readtype", "NO_CACHE") \
    .parquet("alluxio://temp/large_export")
```

### 4. Warm Up Cache Before Critical Jobs

```python
# Pre-load data into cache
spark.read.parquet("alluxio://data/critical") \
    .write.mode("overwrite") \
    .parquet("alluxio://cache/critical_warmed")

# Now run critical job (will be fast)
result = spark.read.parquet("alluxio://cache/critical_warmed") \
    .groupBy("key").agg(...)
```

## Troubleshooting

### Cache Miss Rate Too High

**Symptom**: Slow queries even for frequently accessed data

**Solution**:
```bash
# Check cache size
kubectl exec infrastructure-alluxio-master-0 -n openlakes -- \
  alluxio fsadmin report

# If cache is too small, increase hot tier size
# Edit layers/01-infrastructure/values.yaml:
alluxio:
  worker:
    nvme:
      size: "300GB"  # Increase from 150GB

# Redeploy
./deploy-openlakes.sh
```

### Alluxio Workers Not Starting

**Symptom**: Alluxio workers in CrashLoopBackOff

**Solution**:
```bash
# Check if hot tier directory exists
kubectl exec -it infrastructure-alluxio-worker-xxx -n openlakes -- \
  ls -la /mnt/openlakes-hot

# If not, create on each node:
# SSH to each node and run:
sudo mkdir -p /mnt/openlakes-hot
sudo chmod 777 /mnt/openlakes-hot
```

### Data Not Persisting to MinIO

**Symptom**: Data only in cache, lost after Alluxio restart

**Solution**:
```python
# Ensure write-through mode
df.write \
    .option("alluxio.user.file.writetype", "CACHE_THROUGH") \
    .parquet("alluxio://data/my-table")

# Or set globally in Spark config:
spark.conf.set("spark.hadoop.alluxio.user.file.writetype.default", "CACHE_THROUGH")
```

## FAQ

**Q: Do I need to change my existing Spark code?**

A: Minimal changes. Just change `s3a://openlakes/` to `alluxio://` in paths. Everything else stays the same.

**Q: What happens if Alluxio goes down?**

A: Data is safe in MinIO (warm tier). You can temporarily switch back to `s3a://` paths until Alluxio is restored.

**Q: Can I use both Alluxio and direct S3A in the same job?**

A: Yes! Use `alluxio://` for frequently accessed data and `s3a://` for one-time scans.

**Q: How much faster is cached data?**

A: NVMe cache is typically **50-1000x faster** than cold storage, and **5-10x faster** than warm tier MinIO.

**Q: When should I NOT use Alluxio?**

A: For write-heavy workloads that don't benefit from caching (e.g., bulk ETL landing zone). Use direct `s3a://` instead.

## Next Steps

1. **Enable Alluxio**: Run `./deploy-openlakes.sh --configure-storage`
2. **Update Spark Jobs**: Change paths from `s3a://` to `alluxio://`
3. **Monitor Performance**: Check cache hit rates and adjust tier sizes
4. **Optimize Lifecycle**: Configure warm→cold transitions based on access patterns

---

For more details, see:
- [STORAGE-ARCHITECTURE.md](STORAGE-ARCHITECTURE.md) - Complete architecture guide
- [STORAGE-QUICK-START.md](../STORAGE-QUICK-START.md) - Quick reference
