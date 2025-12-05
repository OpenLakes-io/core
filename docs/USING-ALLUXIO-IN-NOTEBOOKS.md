# Using Alluxio in Jupyter Notebooks

This guide explains how to configure Spark sessions in Jupyter notebooks to use Alluxio for transparent data caching in multi-node deployments.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Jupyter Notebook                         │
│                   (PySpark Application)                      │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
         ┌─────────────────────────────┐
         │   Spark Cluster (Executors) │
         │  with Alluxio integration   │
         └─────────────┬───────────────┘
                       │
      ┌────────────────┴────────────────┐
      ▼                                 ▼
┌──────────────┐              ┌──────────────┐
│   Alluxio    │              │    Trino     │
│ (Cache Layer)│              │ (SQL Engine) │
│              │              │              │
│ - Memory     │              │ Reads from   │
│ - NVMe SSD   │              │ MinIO S3     │
└──────┬───────┘              └──────┬───────┘
       │                              │
       │ CACHE_THROUGH                │ Direct S3
       ▼                              ▼
┌────────────────────────────────────────┐
│           MinIO Object Storage         │
│       (Persistent Data Layer)          │
└────────────────────────────────────────┘
```

### Data Flow Explanation

1. **Spark writes** → Alluxio (cached) → MinIO (persisted) via CACHE_THROUGH mode
2. **Spark reads** → Alluxio cache (if available) → MinIO (on cache miss)
3. **Trino queries** → MinIO directly (reads data written by Spark)

**Key Benefit**: Spark operations are 10-1000x faster on cached data, while Trino can still access all data from persistent storage.

---

## Configuration Patterns

### Pattern 1: Alluxio with Caching (Recommended for Multi-Node)

Use this pattern when Alluxio is enabled in your cluster for maximum performance on repeat queries and iterative workloads.

```python
from pyspark.sql import SparkSession
import os

# Set AWS credentials for MinIO understore
os.environ["AWS_REGION"] = "us-east-1"
os.environ["AWS_ACCESS_KEY_ID"] = "admin"
os.environ["AWS_SECRET_ACCESS_KEY"] = "admin123"

spark = SparkSession.builder \
    .appName("MyApp-Alluxio-Cached") \
    .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions") \
    .config("spark.sql.catalog.lakehouse", "org.apache.iceberg.spark.SparkCatalog") \
    .config("spark.sql.catalog.lakehouse.catalog-impl", "org.apache.iceberg.nessie.NessieCatalog") \
    .config("spark.sql.catalog.lakehouse.uri", "http://infrastructure-nessie:19120/api/v2") \
    .config("spark.sql.catalog.lakehouse.ref", "main") \
    .config("spark.sql.catalog.lakehouse.authentication.type", "NONE") \
    \
    .config("spark.sql.catalog.lakehouse.warehouse", "alluxio://infrastructure-alluxio-master:19998/openlakes/warehouse/") \
    .config("spark.sql.catalog.lakehouse.io-impl", "org.apache.iceberg.aws.s3.S3FileIO") \
    .config("spark.sql.catalog.lakehouse.s3.endpoint", "http://infrastructure-minio:9000") \
    .config("spark.sql.catalog.lakehouse.s3.path-style-access", "true") \
    \
    .config("spark.hadoop.fs.alluxio.impl", "alluxio.hadoop.FileSystem") \
    .config("spark.hadoop.alluxio.master.hostname", "infrastructure-alluxio-master") \
    .config("spark.hadoop.alluxio.master.rpc.port", "19998") \
    .config("spark.hadoop.alluxio.user.file.readtype.default", "CACHE") \
    .config("spark.hadoop.alluxio.user.file.writetype.default", "CACHE_THROUGH") \
    .config("spark.hadoop.alluxio.user.file.passive.cache.enabled", "true") \
    .config("spark.hadoop.alluxio.user.short.circuit.enabled", "true") \
    \
    .config("spark.hadoop.fs.s3a.endpoint", "http://infrastructure-minio:9000") \
    .config("spark.hadoop.fs.s3a.access.key", "admin") \
    .config("spark.hadoop.fs.s3a.secret.key", "admin123") \
    .config("spark.hadoop.fs.s3a.path.style.access", "true") \
    .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem") \
    .getOrCreate()

print("✅ Spark configured with Alluxio transparent caching")
print(f"   Warehouse: alluxio://infrastructure-alluxio-master:19998/openlakes/warehouse/")
print(f"   Understore: MinIO (s3a://openlakes/)")
print(f"   Caching: CACHE_THROUGH (cache + persist)")
```

**Key Configuration**:
- `warehouse`: Uses `alluxio://` protocol for cached access
- `io-impl`: S3FileIO for Iceberg data files (stored in MinIO)
- `readtype`: CACHE - automatically cache data on read
- `writetype`: CACHE_THROUGH - write to cache AND MinIO for durability

### Pattern 2: Direct MinIO Access (Bypass Cache)

Use this pattern when you want to bypass caching or when Alluxio is not available (single-node deployments).

```python
from pyspark.sql import SparkSession

spark = SparkSession.builder \
    .appName("MyApp-Direct-MinIO") \
    .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions") \
    .config("spark.sql.catalog.lakehouse", "org.apache.iceberg.spark.SparkCatalog") \
    .config("spark.sql.catalog.lakehouse.catalog-impl", "org.apache.iceberg.nessie.NessieCatalog") \
    .config("spark.sql.catalog.lakehouse.uri", "http://infrastructure-nessie:19120/api/v2") \
    .config("spark.sql.catalog.lakehouse.ref", "main") \
    .config("spark.sql.catalog.lakehouse.warehouse", "s3a://openlakes/warehouse/") \
    .config("spark.hadoop.fs.s3a.endpoint", "http://infrastructure-minio:9000") \
    .config("spark.hadoop.fs.s3a.access.key", "admin") \
    .config("spark.hadoop.fs.s3a.secret.key", "admin123") \
    .config("spark.hadoop.fs.s3a.path.style.access", "true") \
    .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem") \
    .getOrCreate()

print("✅ Spark configured for direct MinIO access (no caching)")
print(f"   Warehouse: s3a://openlakes/warehouse/")
print(f"   Storage: MinIO direct")
```

**Key Difference**:
- `warehouse`: Uses `s3a://` protocol for direct S3/MinIO access
- No Alluxio configuration - data goes directly to/from MinIO
- No caching layer - every read hits MinIO storage

---

## When to Use Each Pattern

### Use Alluxio (Pattern 1) When:

✅ **Multi-node cluster** with Alluxio enabled
✅ **Iterative workloads** (ML training, graph processing)
✅ **Interactive analytics** (dashboards querying same data repeatedly)
✅ **Read-heavy workloads** (more reads than writes)
✅ **Hot data access** (recent/frequently accessed data)
✅ **ETL with multiple passes** (read → transform → read again)

**Performance**: 10-1000x faster on cache hits!

### Use Direct MinIO (Pattern 2) When:

✅ **Single-node deployment** (Alluxio not available)
✅ **Write-heavy workloads** (mostly new data)
✅ **One-time batch processing** (read once, process, never re-read)
✅ **Cold data access** (historical data accessed infrequently)
✅ **Debugging/troubleshooting** (want to ensure data persistence)

**Performance**: Consistent but slower (~50-200ms per read)

---

## Performance Comparison

### Alluxio Cached Access

```python
# First read: Cache miss - fetches from MinIO
df = spark.table("lakehouse.demo.products")
count = df.count()
# Time: ~200ms (MinIO network latency)

# Second read: Cache hit - served from NVMe
df = spark.table("lakehouse.demo.products")
count = df.count()
# Time: ~2ms (100x faster!)
```

### Direct MinIO Access

```python
# First read: Direct from MinIO
df = spark.table("lakehouse.demo.products")
count = df.count()
# Time: ~200ms

# Second read: Still from MinIO (no cache)
df = spark.table("lakehouse.demo.products")
count = df.count()
# Time: ~200ms (same as first read)
```

---

## Trino Integration

**Important**: Trino does not support the `alluxio://` protocol. It queries MinIO directly via S3.

### How Trino Benefits from Alluxio

Even though Trino queries MinIO directly, it benefits indirectly:

1. **Spark writes data** through Alluxio → cached AND written to MinIO (CACHE_THROUGH)
2. **Spark optimizes data** (compaction, sorting) using fast cached operations
3. **Trino queries optimized data** from MinIO → faster query execution

```python
# In Notebook: Write data with Spark (using Alluxio)
spark.sql("""
    CREATE TABLE lakehouse.demo.aggregated AS
    SELECT category, SUM(amount) as total
    FROM lakehouse.demo.transactions
    GROUP BY category
""")
# ✅ Data written to Alluxio cache + MinIO

# From Trino: Query the data
import trino
conn = trino.dbapi.connect(
    host='compute-trino',
    port=8080,
    catalog='lakehouse',
    schema='demo'
)

cursor = conn.cursor()
cursor.execute("SELECT * FROM aggregated ORDER BY total DESC")
# ✅ Reads from MinIO (data that Spark wrote via Alluxio)
```

**Result**: Trino gets optimized, compacted data that was efficiently processed by cached Spark operations.

---

## Example Notebook Template

Here's a complete example showing both patterns:

```python
from pyspark.sql import SparkSession
import os

# =============================================================================
# Configuration: Choose your pattern
# =============================================================================
USE_ALLUXIO = True  # Set to False to bypass cache

if USE_ALLUXIO:
    print("🔥 Using Alluxio transparent caching (multi-node optimized)")

    # Set MinIO credentials for understore
    os.environ["AWS_REGION"] = "us-east-1"
    os.environ["AWS_ACCESS_KEY_ID"] = "admin"
    os.environ["AWS_SECRET_ACCESS_KEY"] = "admin123"

    spark = SparkSession.builder \
        .appName("Demo-Alluxio-Cached") \
        .config("spark.sql.catalog.lakehouse.warehouse",
                "alluxio://infrastructure-alluxio-master:19998/openlakes/warehouse/") \
        .config("spark.hadoop.fs.alluxio.impl", "alluxio.hadoop.FileSystem") \
        .config("spark.hadoop.alluxio.master.hostname", "infrastructure-alluxio-master") \
        .config("spark.hadoop.alluxio.master.rpc.port", "19998") \
        .config("spark.hadoop.alluxio.user.file.readtype.default", "CACHE") \
        .config("spark.hadoop.alluxio.user.file.writetype.default", "CACHE_THROUGH") \
        # ... (other configs from Pattern 1)
        .getOrCreate()
else:
    print("📁 Using direct MinIO access (no caching)")

    spark = SparkSession.builder \
        .appName("Demo-Direct-MinIO") \
        .config("spark.sql.catalog.lakehouse.warehouse", "s3a://openlakes/warehouse/") \
        # ... (other configs from Pattern 2)
        .getOrCreate()

# Now use Spark normally - caching is transparent!
df = spark.sql("SELECT * FROM lakehouse.demo.products")
df.show()
```

---

## Checking Alluxio Cache Status

You can monitor cache efficiency through the Alluxio UI:

```bash
# Access Alluxio Master UI
open http://alluxio.openlakes.local
# Or port-forward: kubectl port-forward svc/infrastructure-alluxio-master 19999:19999 -n openlakes
```

**Key Metrics**:
- **Cache Hit Rate**: Percentage of reads served from cache
- **Cache Capacity**: Total cache size (Memory + NVMe)
- **Cache Usage**: How much cache is currently used
- **Throughput**: Read/write performance

---

## Troubleshooting

### Problem: "alluxio.hadoop.FileSystem not found"

**Solution**: Ensure Alluxio JARs are available in Spark classpath (pre-installed in OpenLakes images)

### Problem: Cache hit rate is low

**Possible causes**:
1. Data is not being re-read (one-time processing)
2. Cache eviction (working set larger than cache capacity)
3. Cold start (first access always misses cache)

**Solution**:
- Increase cache size via storage configuration wizard
- Use cache warming for frequently accessed data
- Check Alluxio worker logs

### Problem: Trino doesn't see data written by Spark

**Solution**: This should not happen with CACHE_THROUGH mode. Check:
1. Verify data is in MinIO: `aws s3 ls s3://openlakes/warehouse/`
2. Check Nessie catalog metadata: `kubectl logs -n openlakes deployment/infrastructure-nessie`
3. Ensure Iceberg S3FileIO is configured correctly

---

## Migration Guide

### Updating Existing Notebooks

To migrate existing notebooks from direct MinIO to Alluxio:

**Before** (Direct MinIO):
```python
.config("spark.sql.catalog.lakehouse.warehouse", "s3a://openlakes/warehouse/")
```

**After** (Alluxio Cached):
```python
import os
os.environ["AWS_REGION"] = "us-east-1"
os.environ["AWS_ACCESS_KEY_ID"] = "admin"
os.environ["AWS_SECRET_ACCESS_KEY"] = "admin123"

.config("spark.sql.catalog.lakehouse.warehouse",
        "alluxio://infrastructure-alluxio-master:19998/openlakes/warehouse/") \
.config("spark.sql.catalog.lakehouse.io-impl", "org.apache.iceberg.aws.s3.S3FileIO") \
.config("spark.sql.catalog.lakehouse.s3.endpoint", "http://infrastructure-minio:9000") \
.config("spark.sql.catalog.lakehouse.s3.path-style-access", "true") \
.config("spark.hadoop.fs.alluxio.impl", "alluxio.hadoop.FileSystem") \
.config("spark.hadoop.alluxio.master.hostname", "infrastructure-alluxio-master") \
.config("spark.hadoop.alluxio.master.rpc.port", "19998") \
.config("spark.hadoop.alluxio.user.file.readtype.default", "CACHE") \
.config("spark.hadoop.alluxio.user.file.writetype.default", "CACHE_THROUGH")
```

**Compatibility**: Both configurations write to the same MinIO location, so data is compatible.

---

## See Also

- [Alluxio Transparent Tiering Guide](./ALLUXIO-TRANSPARENT-TIERING.md)
- [Storage Performance Comparison Notebooks](../examples/06-storage-performance/)
- [Storage Architecture Overview](./STORAGE-ARCHITECTURE.md)
