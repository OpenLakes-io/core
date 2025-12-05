# OpenLakes JupyterHub Notebook Image

Custom JupyterHub singleuser notebook image with Spark 4.1.0 and OpenLakes pattern dependencies.

## What's Included

### Apache Spark 4.1.0-preview3
- **Matches OpenLakes compute cluster** (Layer 02)
- Scala 2.13
- Hadoop 3.4.2

### Pre-installed JARs
- **Apache Iceberg 1.10.0** (`iceberg-spark-runtime-4.0_2.13`)
  - Note: Spark 4.x uses runtime 4.0 for Spark 4.0+
- **Hadoop AWS 3.4.2** (S3A support)
- **AWS SDK Bundle 2.29.39** (required by Hadoop 3.4+ and Iceberg 1.10+)
- **Alluxio 2.9.3** (`alluxio-shaded-client`)
  - Enables transparent S3A filesystem interception for write-back caching

### Python Dependencies
- **PySpark 4.0.1** (matches Spark 4.1.0 API)
- **Kafka clients**: kafka-python, confluent-kafka
- **OpenMetadata SDK**: openmetadata-ingestion
- **Query engines**: Trino connector, SQLAlchemy
- **Notebook execution**: Papermill, nbformat
- **JupyterLab widgets**: ipywidgets

## Registry

```
ghcr.io/openlakes/core/jupyterhub-notebook
```

## Tags

- `1.0.0`, `1.0`, `1`, `latest` - Production release
- `staging`, `1.0.0-staging` - Release candidate
- `dev` - Development (team collaboration)
- `local` - Local builds (not pushed to registry)

## Building

### Local Development (Fastest)
```bash
./build.sh
# Creates: jupyterhub-notebook:local
# Use with: imagePullPolicy: Never
```

### Collaborative Development
```bash
BUILD_ENV=dev ./build.sh
# Creates and pushes: ghcr.io/openlakes/core/jupyterhub-notebook:dev
```

### Staging (Release Candidate)
```bash
BUILD_ENV=staging VERSION=1.0.0 ./build.sh
# Creates and pushes:
#   - ghcr.io/openlakes/core/jupyterhub-notebook:staging
#   - ghcr.io/openlakes/core/jupyterhub-notebook:1.0.0-staging
```

### Production (Automated via CI)
```bash
BUILD_ENV=production VERSION=1.0.0 ./build.sh
# Creates and pushes:
#   - ghcr.io/openlakes/core/jupyterhub-notebook:1.0.0
#   - ghcr.io/openlakes/core/jupyterhub-notebook:1.0
#   - ghcr.io/openlakes/core/jupyterhub-notebook:1
#   - ghcr.io/openlakes/core/jupyterhub-notebook:latest
```

## Usage in Layer 05 (Analytics)

### Production (values.yaml)
```yaml
jupyterhub:
  singleuser:
    image:
      name: ghcr.io/openlakes/core/jupyterhub-notebook
      tag: "1.0.0"
      pullPolicy: IfNotPresent
```

### Local Development (values-local.yaml)
```yaml
jupyterhub:
  singleuser:
    image:
      name: jupyterhub-notebook
      tag: "local"
      pullPolicy: Never
```

### Dev Environment (values-dev.yaml)
```yaml
jupyterhub:
  singleuser:
    image:
      name: ghcr.io/openlakes/core/jupyterhub-notebook
      tag: "dev"
      pullPolicy: Always
```

## Why This Image?

### Problem
The official `jupyter/pyspark-notebook:ubuntu-22.04` has:
- Spark 3.5.0 (OpenLakes cluster uses 4.1.0)
- Scala 2.12 (OpenLakes uses 2.13)
- Hadoop 3.3.4 (OpenLakes uses 3.4.2)
- No Iceberg or S3A JARs pre-installed

### Solution
This custom image:
✅ Matches OpenLakes Spark cluster version exactly
✅ Pre-downloads all required JARs (faster pod startup)
✅ Includes all OpenLakes pattern dependencies
✅ Notebooks work without modification
✅ Consistent environment across local/dev/staging/production

## Testing Locally

```bash
# Build local image
./build.sh

# Test in Docker
docker run --rm -p 8888:8888 jupyterhub-notebook:local

# Verify Spark version
docker run --rm jupyterhub-notebook:local spark-submit --version

# Verify PySpark
docker run --rm jupyterhub-notebook:local python -c "import pyspark; print(pyspark.__version__)"
```

## Notebook Compatibility

Notebooks can use Spark without downloading JARs:

```python
# No need to specify spark.jars.packages - JARs are pre-installed!
spark = SparkSession.builder \
    .appName("Pattern-1.1-BasicETL") \
    .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions") \
    .config("spark.sql.catalog.lakehouse", "org.apache.iceberg.spark.SparkCatalog") \
    .config("spark.sql.catalog.lakehouse.type", "hadoop") \
    .config("spark.sql.catalog.lakehouse.warehouse", "s3a://openlakes/warehouse") \
    .config("spark.hadoop.fs.s3a.endpoint", "http://infrastructure-minio:9000") \
    .config("spark.hadoop.fs.s3a.access.key", "admin") \
    .config("spark.hadoop.fs.s3a.secret.key", "admin123") \
    .config("spark.hadoop.fs.s3a.path.style.access", "true") \
    .getOrCreate()
```

**Note**: For notebooks that need to dynamically download JARs (testing different versions), you can still use `spark.jars.packages`.

## Alluxio Write-Back Cache Support

This image includes Alluxio client JARs for transparent S3A filesystem interception, enabling write-back caching:

```python
# Configure Spark to use Alluxio for S3A operations
spark = SparkSession.builder \
    .appName("Alluxio Cached Pipeline") \
    .config("spark.sql.catalog.lakehouse.warehouse", "s3a://openlakes/warehouse/") \
    .config("spark.hadoop.fs.s3a.impl", "alluxio.hadoop.shaded.client.UnderFileSystemFileSystem") \
    .config("spark.hadoop.fs.alluxio.impl", "alluxio.hadoop.FileSystem") \
    .config("spark.hadoop.fs.AbstractFileSystem.alluxio.impl", "alluxio.hadoop.AlluxioFileSystem") \
    .config("spark.hadoop.alluxio.master.rpc.addresses", "infrastructure-alluxio-master:19998") \
    .config("spark.hadoop.alluxio.user.file.writetype.default", "ASYNC_THROUGH") \
    .config("spark.hadoop.alluxio.user.file.readtype.default", "CACHE") \
    .getOrCreate()
```

**Benefits**:
- First write: Cache to NVMe, async persist to MinIO
- Repeat reads: Served from hot tier (50-1000x faster)
- No URI changes needed - same `s3a://` paths work for both direct and cached access

See: `examples/notebooks/06-storage-performance/04-alluxio-minio-benchmark.ipynb`

## Versioning

This image follows OpenLakes semantic versioning:

- **PATCH** (1.0.0 → 1.0.1): Update dependency versions (same major)
- **MINOR** (1.0.0 → 1.1.0): Add new dependencies/features (backward compatible)
- **MAJOR** (1.0.0 → 2.0.0): Upgrade Spark/Hadoop major versions (breaking)

## Base Image

Built on: `jupyter/pyspark-notebook:ubuntu-22.04`
- Python 3.11
- JupyterLab
- Conda package manager
- Scientific Python stack (pandas, numpy, scipy, matplotlib)
