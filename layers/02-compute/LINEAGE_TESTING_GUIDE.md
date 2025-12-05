# Spark + OpenMetadata Lineage Testing Guide

## Quick Reference

The Spark + OpenMetadata integration is **deployed and configured**. This guide shows how to test lineage capture.

## Prerequisites Verified ✅

- ✅ Custom Spark image with OpenMetadata agent deployed
- ✅ JWT token injected into Spark pods
- ✅ Configuration loaded in spark-defaults.conf
- ✅ OpenMetadata service registered
- ✅ Spark master and worker running

## Testing Approaches

### Option 1: PySpark Shell (Recommended for Quick Test)

```bash
# Access Spark master
kubectl exec -it <spark-master-pod> -n openlakes -- bash

# Start pyspark shell
/opt/spark/bin/pyspark --master spark://compute-spark-master:7077

# In the pyspark shell, run:
```

```python
# Create test data
data = [("Alice", 25), ("Bob", 30), ("Charlie", 35)]
df = spark.createDataFrame(data, ["name", "age"])

# Transform
from pyspark.sql.functions import upper
df_transformed = df.withColumn("name_upper", upper("name"))

# Write to MinIO (triggers lineage capture)
df_transformed.write.mode("overwrite").parquet("s3a://openlakes-data/lineage-test/quick-test")

print("✅ Test complete - check OpenMetadata UI for lineage")
```

### Option 2: Spark SQL

```bash
# Access Spark master
kubectl exec -it <spark-master-pod> -n openlakes -- bash

# Start spark-sql
/opt/spark/bin/spark-sql --master spark://compute-spark-master:7077
```

```sql
-- Create temporary view
CREATE OR REPLACE TEMP VIEW employees AS
SELECT 'Alice' as name, 28 as age, 'Engineering' as dept
UNION ALL
SELECT 'Bob', 34, 'Marketing'
UNION ALL
SELECT 'Charlie', 31, 'Sales';

-- Transform and save
CREATE TABLE lineage_test_sql
USING parquet
LOCATION 's3a://openlakes-data/lineage-test/sql-test'
AS
SELECT
  UPPER(name) as name_upper,
  age,
  age * 12 as annual_months,
  dept
FROM employees;
```

### Option 3: JupyterHub Notebook

If JupyterHub is deployed (Layer 05):

1. Access: `http://localhost:30888`
2. Create new Python notebook
3. Install PySpark (if not already available)
4. Run the test lineage script

### Option 4: Airflow DAG

If Airflow is deployed (Layer 04):

1. Create DAG with SparkSubmitOperator
2. Configure connection to Spark master
3. Submit lineage test job
4. Check Airflow task logs and OpenMetadata UI

## Verification Steps

### 1. Check Spark Logs for Lineage Events

```bash
# View Spark driver logs
kubectl logs -n openlakes <spark-master-pod> | grep -i "openmetadata\|lineage"
```

Expected: You should see OpenMetadata agent initialization and lineage event sending.

### 2. Verify Data in MinIO

```bash
# Port forward MinIO
kubectl port-forward -n openlakes svc/infrastructure-minio 9001:9001

# Open browser: http://localhost:9001
# Login: admin / admin123
# Navigate to: openlakes-data bucket → lineage-test folder
```

### 3. Check OpenMetadata UI

```bash
# Port forward OpenMetadata
kubectl port-forward -n openlakes svc/catalog-openmetadata-server 30585:8585

# Open browser: http://localhost:30585
# Login with admin credentials
```

**Navigate to:**
1. **Explore** → **Tables**
2. Search for: `lineage-test`
3. Click on discovered tables
4. Select **Lineage** tab

**Expected to See:**
- Source columns: name, age, (dept if using SQL test)
- Transformed columns: name_upper, annual_months, etc.
- Lineage graph showing data flow
- **Created by**: openlakesbot
- **Pipeline**: openlakes-spark-jobs
- **Service**: compute-spark

## Troubleshooting

### No Lineage Appearing

**1. Check OpenMetadata agent loaded:**
```bash
kubectl exec -n openlakes <spark-master-pod> -- \
  ls -lh /opt/spark/jars/openmetadata-spark-agent-1.0-beta.jar
```

**2. Verify listener configuration:**
```bash
kubectl exec -n openlakes <spark-master-pod> -- \
  cat /opt/spark/conf/spark-defaults.conf | grep extraListeners
```

Expected: `spark.extraListeners io.openlineage.spark.agent.OpenLineageSparkListener`

**3. Check JWT token:**
```bash
kubectl exec -n openlakes <spark-master-pod> -- \
  env | grep SPARK_OPENMETADATA_JWT_TOKEN
```

Token should be ~651 characters.

**4. Test OpenMetadata connectivity:**
```bash
kubectl exec -n openlakes <spark-master-pod> -- \
  curl -v http://catalog-openmetadata-server:8585/api/v1/health-check
```

**5. Check OpenMetadata logs:**
```bash
kubectl logs -n openlakes <openmetadata-pod> | grep -i "lineage\|spark"
```

### Port Binding Issues

If you see "Cannot assign requested address" when running Spark jobs:

- Use separate worker pods (not master) for job execution
- OR use spark-shell/pyspark which handles driver configuration automatically
- OR submit jobs from outside the cluster via NodePort

### MinIO Connection Issues

If S3A writes fail:

```bash
# Verify MinIO is accessible
kubectl exec -n openlakes <spark-master-pod> -- \
  curl -v http://infrastructure-minio:9000

# Check S3A configuration in spark-defaults.conf
kubectl exec -n openlakes <spark-master-pod> -- \
  cat /opt/spark/conf/spark-defaults.conf | grep s3a
```

## Advanced Testing

### Custom Lineage Metadata

Add custom facets to lineage:

```python
spark.conf.set("spark.openmetadata.facets.dataset.ownership", "data-engineering-team")
spark.conf.set("spark.openmetadata.facets.dataset.domain", "customer-analytics")
```

### Multi-Stage Pipeline

Test complex lineage with multiple transformations:

```python
# Stage 1: Raw data
df_raw = spark.read.parquet("s3a://openlakes-data/source/customers")

# Stage 2: Cleaned
df_clean = df_raw.dropna().filter("age > 18")
df_clean.write.mode("overwrite").parquet("s3a://openlakes-data/staging/customers-clean")

# Stage 3: Aggregated
df_agg = spark.read.parquet("s3a://openlakes-data/staging/customers-clean") \
    .groupBy("country").count()
df_agg.write.mode("overwrite").parquet("s3a://openlakes-data/curated/customers-by-country")
```

Each stage creates lineage nodes that connect in OpenMetadata.

### Cross-System Lineage

Test lineage across different data sources:

```python
# Read from PostgreSQL
df_postgres = spark.read \
    .format("jdbc") \
    .option("url", "jdbc:postgresql://infrastructure-postgres:5432/openlakes") \
    .option("dbtable", "public.users") \
    .option("user", "openlakes") \
    .option("password", "openlakes123") \
    .load()

# Join with MinIO data
df_minio = spark.read.parquet("s3a://openlakes-data/events")

# Transform and write to Trino
df_joined = df_postgres.join(df_minio, "user_id")
df_joined.write \
    .format("jdbc") \
    .option("url", "jdbc:trino://compute-trino:8080/iceberg/analytics") \
    .option("dbtable", "user_events") \
    .save()
```

OpenMetadata will show lineage across Postgres → Spark → MinIO → Trino.

## Success Criteria

- [ ] Spark job executes successfully
- [ ] Data written to MinIO (s3a://openlakes-data/lineage-test/)
- [ ] Tables appear in OpenMetadata Explore within 1-2 minutes
- [ ] Lineage tab shows transformation graph
- [ ] Column-level lineage visible
- [ ] openlakesbot shown as creator
- [ ] Pipeline tagged as openlakes-spark-jobs

## Next Steps After Successful Test

1. **Integrate with Airflow** - Create production DAGs with lineage
2. **Add to CI/CD** - Automated lineage validation
3. **User Training** - Show data engineers how to leverage lineage
4. **Custom Facets** - Add business metadata to lineage
5. **Alerts** - Set up OpenMetadata alerts for lineage quality

## References

- Test script: `/test-lineage.py` (root of repo)
- Setup guide: `layers/02-compute/OPENMETADATA_SETUP.md`
- Verification: `layers/02-compute/docker/VERIFICATION.md`
- OpenMetadata Docs: https://docs.open-metadata.org/latest/connectors/ingestion/lineage/spark-lineage
