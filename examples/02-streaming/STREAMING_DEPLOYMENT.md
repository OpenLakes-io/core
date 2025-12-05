# Streaming Deployment Guide

This document explains the two modes for working with OpenLakes streaming patterns.

## Two Deployment Modes

### Mode 1: Interactive Learning (JupyterHub + Papermill)

**Purpose**: Learning, testing, prototyping, ad-hoc analysis

**How it works**:
- Notebooks run in JupyterHub (interactive) or Airflow (automated via Papermill)
- Streaming queries run for fixed duration (30-60 seconds)
- Results stored in Iceberg for analysis
- Ideal for understanding streaming concepts

**When to use**:
- Learning streaming patterns
- Testing streaming logic interactively
- Prototyping new streaming pipelines
- Running finite streaming jobs for demos

**Example**:
```bash
# In JupyterHub
Open: notebooks/02-streaming/01-kafka-spark-streaming.ipynb
Run all cells → streams for 30 seconds → results in Iceberg

# Via Airflow (Papermill)
airflow dags trigger 01_kafka_spark_streaming
# Executes notebook with production parameters
```

---

### Mode 2: Production Deployment (K8s Spark Operator)

**Purpose**: Long-running production streaming pipelines

**How it works**:
- Convert notebook logic to standalone Python streaming app
- Deploy as SparkApplication CRD via Spark Operator
- Runs continuously (24/7) until explicitly stopped
- Airflow manages lifecycle (deploy, monitor, upgrade), NOT execution

**When to use**:
- Production real-time pipelines
- 24/7 continuous processing
- Mission-critical streaming (payments, fraud detection)
- High-throughput production workloads

**Architecture**:
```
Airflow DAG:
  ├─ Task 1: Deploy SparkApplication (kubectl apply)
  ├─ Task 2: Wait for driver pod ready
  ├─ Task 3: Monitor streaming job health
  └─ Task 4: Alert on failures

Kubernetes:
  ├─ SparkApplication CRD (managed by Spark Operator)
  ├─ Driver Pod (runs streaming logic)
  └─ Executor Pods (process data)

Streaming App:
  └─ Runs indefinitely: Kafka → Spark → Iceberg
```

**Example SparkApplication Manifest**:
```yaml
apiVersion: sparkoperator.k8s.io/v1beta2
kind: SparkApplication
metadata:
  name: kafka-iceberg-streaming
  namespace: openlakes
spec:
  type: Python
  mode: cluster
  image: ghcr.io/openlakes/spark:latest
  mainApplicationFile: local:///opt/spark/apps/kafka_to_iceberg.py
  sparkVersion: "4.1.0"
  restartPolicy:
    type: OnFailure
    onFailureRetries: 3
  driver:
    cores: 2
    memory: "2g"
  executor:
    cores: 2
    instances: 3
    memory: "2g"
```

**Airflow DAG** (lifecycle management):
```python
from airflow import DAG
from airflow.providers.cncf.kubernetes.operators.kubernetes_pod import KubernetesPodOperator

with DAG('deploy_kafka_streaming') as dag:
    deploy = KubernetesPodOperator(
        task_id='deploy_streaming_job',
        cmds=['kubectl', 'apply', '-f', '/manifests/kafka-streaming.yaml'],
    )

    monitor = KubernetesPodOperator(
        task_id='monitor_health',
        cmds=['curl', 'http://spark-driver:4040/api/v1/applications'],
    )

    deploy >> monitor
```

---

## Conversion Guide: Notebook → Production App

To convert an interactive notebook to a production streaming app:

### Step 1: Extract Core Logic

**From Notebook** (examples/notebooks/02-streaming/01-kafka-spark-streaming.ipynb):
```python
# Cell: Read from Kafka
df_stream = spark.readStream \
    .format("kafka") \
    .option("kafka.bootstrap.servers", "kafka:9092") \
    .option("subscribe", "clickstream") \
    .load()

# Cell: Transform
df_parsed = df_stream.select(...)

# Cell: Write to Iceberg (runs 30 seconds)
query = df_parsed.writeStream \
    .format("iceberg") \
    .option("path", "lakehouse.prod.clickstream") \
    .start()

time.sleep(30)  # REMOVE FOR PRODUCTION
query.stop()    # REMOVE FOR PRODUCTION
```

### Step 2: Create Standalone App

**Production App** (examples/streaming-apps/kafka_to_iceberg.py):
```python
from pyspark.sql import SparkSession

def main():
    spark = SparkSession.builder \
        .appName("Kafka-Iceberg-Streaming") \
        .getOrCreate()

    # Read from Kafka
    df_stream = spark.readStream \
        .format("kafka") \
        .option("kafka.bootstrap.servers", "kafka:9092") \
        .option("subscribe", "clickstream") \
        .load()

    # Transform (same logic as notebook)
    df_parsed = df_stream.select(...)

    # Write to Iceberg (runs indefinitely)
    query = df_parsed.writeStream \
        .format("iceberg") \
        .option("path", "lakehouse.prod.clickstream") \
        .option("checkpointLocation", "s3://checkpoints/clickstream") \
        .start()

    # Run forever (or until K8s pod is deleted)
    query.awaitTermination()

if __name__ == "__main__":
    main()
```

**Key Changes**:
1. Remove `time.sleep()` and `query.stop()` → run indefinitely
2. Add `awaitTermination()` → block until stopped externally
3. Use production checkpoint location (S3, not /tmp)
4. Use production database (prod, not demo)
5. Add proper logging and error handling

### Step 3: Deploy

```bash
# Build Docker image with app
docker build -t streaming-app:1.0 .

# Apply SparkApplication manifest
kubectl apply -f sparkapplication.yaml

# Monitor
kubectl get sparkapplication
kubectl logs <driver-pod-name>
```

---

## Current Status (v1.0.0)

### ✅ Implemented: Interactive Mode (Notebooks)

All 8 Category 2 patterns have **interactive notebooks** for learning:
- 01-kafka-spark-streaming.ipynb ✅
- 02-spark-continuous-processing.ipynb ✅
- 03-cdc-postgres-to-iceberg.ipynb ✅
- 04-multi-stream-join.ipynb ✅
- 05-stream-enrichment.ipynb ✅
- 06-windowed-aggregations.ipynb ✅
- 07-exactly-once-spark.ipynb ✅
- 08-session-window-analytics.ipynb ✅

**Run via**:
- JupyterHub (interactive cell execution)
- Airflow + Papermill (automated notebook execution)

### 🔜 Future: Production Mode (Streaming Apps)

**Post v1.0.0**: Convert notebooks to standalone streaming apps with:
- `/examples/streaming-apps/*.py` - Production streaming applications
- `/examples/k8s-manifests/*.yaml` - SparkApplication manifests
- Updated DAGs - Lifecycle management (deploy/monitor)

**Timeline**: After v1.0.0 release (focuses on 30 pattern coverage)

---

## Why Two Modes?

**Interactive (Notebooks)** - Essential for:
- ✅ Learning streaming concepts
- ✅ Rapid prototyping
- ✅ Testing streaming logic
- ✅ Demonstrating patterns
- ✅ v1.0.0 completeness (30 patterns)

**Production (Apps)** - Needed for:
- 🔄 24/7 continuous processing
- 🔄 Mission-critical workloads
- 🔄 High availability requirements
- 🔄 Enterprise deployments

**Both are valid**: Use the right tool for the job.

---

## Recommendation for v1.0.0

**Focus**: Complete all 30 patterns as interactive notebooks
- Categories 1-2: ✅ Complete (14/30 patterns)
- Categories 3-8: 🔄 Implement as notebooks (16/30 patterns)

**Post-v1.0.0**: Add production streaming apps for critical patterns

This approach:
1. Achieves v1.0.0 completeness faster
2. Provides comprehensive learning resource
3. Enables future production conversion
4. Maintains flexibility

---

## Questions?

**Q: Can I run notebooks in production?**
A: Yes, for finite streaming jobs (hourly aggregations, daily CDC sync). Not for 24/7 critical streaming.

**Q: When should I convert to standalone apps?**
A: When you need:
- Continuous 24/7 operation
- High availability (restarts on failure)
- Production SLAs
- Mission-critical processing

**Q: How do I monitor streaming jobs?**
A:
- **Notebooks**: Airflow task logs, JupyterHub output
- **Apps**: Spark UI (port 4040), K8s pod logs, Prometheus metrics

---

**OpenLakes v1.0.0** | Focus: Comprehensive pattern coverage via notebooks
