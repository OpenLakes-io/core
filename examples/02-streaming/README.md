# Category 2: Streaming Patterns

Real-time data processing patterns using Kafka and Spark Structured Streaming.

## Overview

This category demonstrates 8 real-time data processing patterns for sub-second to second-latency analytics. All patterns use Apache Iceberg for ACID transactions and support both interactive execution (JupyterHub) and automated orchestration (Airflow).

## Patterns

| Pattern | Name | Latency | Complexity | Notebook Size |
|---------|------|---------|------------|---------------|
| **2.1** | Kafka → Spark Streaming → Iceberg | Seconds | Low | 13KB |
| **2.2** | Spark Continuous Processing | Sub-second | Medium | 14KB |
| **2.3** | CDC - Database → Lakehouse | Seconds | Medium | 17KB |
| **2.4** | Multi-Topic Stream Join | Seconds | High | 18KB |
| **2.5** | Stream Enrichment | Seconds | Medium | 16KB |
| **2.6** | Windowed Aggregations | Window interval | Medium | 18KB |
| **2.7** | Exactly-Once Spark | Sub-second | Medium | 16KB |
| **2.8** | Session Window Analytics | Session gap | High | 18KB |

**Total**: 8 patterns, ~122KB of production-ready code

---

## Pattern Details

### 2.1: Kafka → Spark Streaming → Iceberg

**What**: Basic real-time ingestion from Kafka to Iceberg lakehouse.

**Architecture**:
```
Kafka Topic → Spark Structured Streaming → Iceberg Table
```

**Key Concepts**:
- Structured Streaming API
- JSON parsing from Kafka
- Iceberg append mode
- Checkpointing for fault tolerance

**Use Cases**: Clickstream analytics, IoT sensor ingestion, log aggregation

**Run Interactive**:
```bash
# Open in JupyterHub
http://localhost:8000/hub
# Navigate to: notebooks/02-streaming/01-kafka-spark-streaming.ipynb
```

**Run Automated**:
```bash
# Trigger Airflow DAG
airflow dags trigger 01_kafka_spark_streaming
```

---

### 2.2: Spark Continuous Processing (Sub-100ms Latency)

**What**: Ultra-low latency stream processing using Spark 4.1 continuous mode.

**Architecture**:
```
Kafka → Spark Continuous Processing → Iceberg
```

**Key Concepts**:
- Event-time processing
- Stateful filtering (temperature threshold)
- Event enrichment (alert severity)
- Millisecond latency

**Spark Continuous Processing**:
- Sub-100ms latency with continuous triggers
- Unified API for batch and streaming

**Use Cases**: Fraud detection, anomaly detection, real-time alerting

---

### 2.3: CDC - Database → Lakehouse Replication

**What**: Real-time database replication using Change Data Capture.

**Architecture**:
```
PostgreSQL (OLTP) → Debezium → Kafka → Spark → Iceberg (OLAP)
```

**Key Concepts**:
- Debezium CDC format (before/after values)
- Real-time replication without OLTP impact
- INSERT/UPDATE/DELETE capture
- Near real-time analytics

**Production Debezium Setup**:
```bash
# Deploy Debezium PostgreSQL connector
curl -X POST http://kafka-connect:8083/connectors \
  -H "Content-Type: application/json" \
  -d '{
    "name": "postgres-cdc-connector",
    "config": {
      "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
      "database.hostname": "postgres",
      "database.port": "5432",
      "database.user": "debezium",
      "database.dbname": "orders",
      "database.server.name": "dbserver1",
      "table.include.list": "public.orders"
    }
  }'
```

**Use Cases**: Real-time reporting, data warehousing, event-driven architectures

---

### 2.4: Multi-Topic Stream Join

**What**: Join 3 Kafka topics with watermarks for late-arriving data.

**Architecture**:
```
Kafka (actions) ──┐
Kafka (purchases) ├─→ Stream Join (with watermarks) → Iceberg
Kafka (sessions) ─┘
```

**Key Concepts**:
- Multi-way joins (left + inner)
- Watermarks (handle late data)
- Event-time processing
- Unified activity stream

**Watermark Example**:
```python
df.withWatermark("event_time", "30 seconds")  # Wait 30s for late data
```

**Join Types**:
- `actions ⟕ purchases`: LEFT (not all actions have purchases)
- `result ⟗ sessions`: INNER (require device info)

**Use Cases**: Customer 360 view, user journey analytics, attribution modeling

---

### 2.5: Stream Enrichment with Dimension Lookup

**What**: Enrich streaming events with reference data using broadcast joins.

**Architecture**:
```
Kafka (raw events, ID only) + Iceberg (dimension table) → Enriched Stream
```

**Key Concepts**:
- Broadcast join (dimension table → all workers)
- Minimal latency (no shuffle)
- Separation of events and reference data
- Storage efficient

**Broadcast Join**:
```python
df_stream.join(broadcast(df_dimension), on="customer_id")
```

**Benefits**:
- Fast (no shuffle for small dimensions)
- Works best for dimension tables < 1GB
- Dimension table cached on each worker

**Use Cases**: Clickstream enrichment, IoT sensor metadata, log enrichment

---

### 2.6: Windowed Aggregations

**What**: Real-time aggregations over tumbling and sliding time windows.

**Architecture**:
```
Kafka → Windowed Aggregation → Iceberg (5-min avg)
```

**Window Types**:

**Tumbling** (non-overlapping):
```
[00:00-00:05] [00:05-00:10] [00:10-00:15]
Each event appears in exactly 1 window
```

**Sliding** (overlapping):
```
[00:00-00:05]
  [00:01-00:06]
    [00:02-00:07]
Each event appears in multiple windows (smoother trends)
```

**Implementation**:
```python
# Tumbling window
df.groupBy(window(col("timestamp"), "5 minutes"))

# Sliding window
df.groupBy(window(col("timestamp"), "5 minutes", "1 minute"))  # 5-min window, 1-min slide
```

**When to Use**:
- **Tumbling**: Hourly reports, daily summaries, distinct periods
- **Sliding**: Moving averages, smoothed trends, real-time dashboards

**Use Cases**: Traffic metrics, IoT sensor averages, financial tick data

---

### 2.7: Exactly-Once Streaming with Spark

**What**: Guarantee exactly-once processing for financial transactions using Spark.

**Architecture**:
```
Kafka → Spark Streaming (checkpointing) → Iceberg (ledger)
```

**Exactly-Once Mechanisms**:

1. **Checkpointing**: Periodic state snapshots
   - Recovery point on failure
   - State saved to MinIO

2. **Idempotent Writes**: Transaction hash prevents duplicates
   - SHA256 hash of transaction data
   - Deterministic (same input → same output)

3. **Two-Phase Commit**: Kafka offsets + Iceberg commits coordinated
   - Either both succeed or both fail

**Spark Structured Streaming Config**:
```yaml
```

**Guarantees**:
- Zero duplicates
- Zero data loss
- Recovers from failures automatically

**Use Cases**: Payment processing, billing systems, financial ledgers, audit logs

---

### 2.8: Session Window Analytics

**What**: Track user sessions with dynamic gap-based windows.

**Architecture**:
```
Kafka (user events) → Session Window (gap timeout) → Iceberg (sessions)
```

**Session Window Explained**:

**Gap Timeout**: 5 minutes

```
Events:  E1───E2──E3─────────────E4──E5──────────E6
Time:    10:00 10:02 10:04      10:15 10:17      10:30

Sessions:
  Session 1: [E1, E2, E3]  (10:00-10:04, no 5-min gap)
  Session 2: [E4, E5]      (10:15-10:17, no 5-min gap)
  Session 3: [E6]          (10:30, isolated event)
```

**Key Difference from Fixed Windows**:
- Session windows adapt to user behavior
- No fixed start/end times
- Session closes after inactivity gap
- Natural grouping of related events

**Gap Selection**:
- **Short (1-5 min)**: Focused sessions, web analytics
- **Medium (15-30 min)**: Standard web, mobile apps
- **Long (60+ min)**: Extended workflows, enterprise apps

**Session Metrics**:
- Duration (first event → last event)
- Event count
- Conversion (purchased during session?)
- Revenue (total purchase value)

**Use Cases**: Web analytics, mobile app engagement, support interactions, gaming

---

## Technical Stack

### Core Technologies
- **Kafka**: Event streaming platform
- **Spark 4.1.0**: Stream processing engine
- **Spark 4.1**: Continuous and micro-batch processing
- **Iceberg 1.8.0**: Lakehouse with ACID transactions
- **MinIO**: S3-compatible object storage

### Integration
- **Airflow 2.10.4**: Workflow orchestration
- **Papermill 2.6.0**: Notebook parameterization
- **JupyterHub**: Interactive development
- **Trino**: SQL analytics on Iceberg

---

## Common Patterns

### Papermill Parameterization

All notebooks follow the Papermill pattern with a tagged parameters cell:

```python
# Cell tagged with "parameters"
execution_date = "2025-01-16"
environment = "development"
database_name = "demo"
kafka_topic = "clickstream_events"
enable_validation = True
enable_cleanup = False
```

### Development vs Production

**Development** (JupyterHub):
- Use notebook defaults
- Interactive execution
- Immediate feedback
- `enable_cleanup = False` (inspect results)

**Production** (Airflow):
- Override with PapermillOperator
- Automated execution
- Production database (`database_name = "prod"`)
- `enable_cleanup = configurable`

### Validation Pattern

All notebooks include validation:

```python
if enable_validation:
    total_count = spark.sql(f"SELECT COUNT(*) FROM {table}").collect()[0][0]
    assert total_count > 0, "Should have processed events"
    print(f"✅ Processed {total_count} events")

    test_passed = True
    print("\n✅ All validations passed!")
```

---

## Running the Patterns

### Prerequisites

1. **Deploy OpenLakes**:
```bash
./deploy-openlakes.sh
```

2. **Verify Services**:
```bash
kubectl get pods -n openlakes
```

Expected running pods:
- `infrastructure-kafka-*`
- `infrastructure-postgres-*`
- `infrastructure-minio-*`
- `compute-spark-*`
- `orchestration-airflow-*`
- `analytics-jupyterhub-*`

### Interactive Execution (JupyterHub)

1. **Access JupyterHub**:
```bash
kubectl port-forward -n openlakes svc/analytics-jupyterhub 8000:80
# Open: http://localhost:8000
```

2. **Login**: admin / admin123

3. **Navigate**: `notebooks/02-streaming/`

4. **Run**: Click "Run All Cells" or execute cell-by-cell

### Automated Execution (Airflow)

1. **Access Airflow UI**:
```bash
kubectl port-forward -n openlakes svc/orchestration-airflow-webserver 8080:8080
# Open: http://localhost:8080
```

2. **Login**: admin / admin

3. **Trigger DAG**:
   - Navigate to DAGs page
   - Find `01_kafka_spark_streaming` (or any pattern 2.1-2.8)
   - Click "Trigger DAG" ▶

4. **Monitor Execution**:
   - Click DAG name → Graph
   - View task logs
   - Check output notebook in `/opt/airflow/outputs/`

---

## Key Streaming Concepts

### Watermarks

**Purpose**: Handle late-arriving data in streaming systems

```python
df.withWatermark("event_time", "30 seconds")
```

- Allows events up to 30 seconds late
- Events older than watermark are dropped
- Balances completeness vs latency

**Trade-off**:
- **Long watermark**: More complete data, higher latency
- **Short watermark**: Lower latency, may miss late data

### Checkpointing

**Purpose**: Fault tolerance and exactly-once semantics

```python
df.writeStream \
  .option("checkpointLocation", "/tmp/checkpoint_dir") \
  .start()
```

- Periodic state snapshots
- Recovers from failures automatically
- Enables exactly-once processing

### Output Modes

**Append**: Add new records only (most common)
```python
.outputMode("append")
```

**Complete**: Replace entire result table (for aggregations without watermark)
```python
.outputMode("complete")
```

**Update**: Update changed records only (for aggregations with watermark)
```python
.outputMode("update")
```

---

## Troubleshooting

### Issue: Streaming query not processing events

**Solution**:
1. Check Kafka topic exists and has data:
```bash
kubectl exec -it infrastructure-kafka-0 -n openlakes -- \
  kafka-console-consumer --bootstrap-server localhost:9092 \
    --topic clickstream_events --from-beginning --max-messages 5
```

2. Verify checkpoint directory is writable
3. Check Spark logs for errors

### Issue: Late data being dropped

**Solution**: Increase watermark delay
```python
df.withWatermark("event_time", "2 minutes")  # Increase from 30s
```

### Issue: Memory errors in windowed aggregations

**Solution**:
1. Ensure watermarks are configured (prevents unbounded state growth)
2. Use sliding windows sparingly (more memory than tumbling)
3. Increase Spark executor memory

---

## Next Steps

After mastering Category 2 (Streaming), proceed to:

- **Category 3**: Data Quality (Great Expectations, Deequ)
- **Category 4**: Orchestration (Complex DAGs, branching)
- **Category 5**: Real-Time Analytics (Druid, ClickHouse)

---

## Additional Resources

- **Spark Structured Streaming Guide**: https://spark.apache.org/docs/latest/structured-streaming-programming-guide.html
- **Apache Iceberg Streaming**: https://iceberg.apache.org/docs/latest/spark-writes/#streaming-writes
- **Kafka Documentation**: https://kafka.apache.org/documentation/
- **Spark Continuous Processing**: https://spark.apache.org/docs/latest/structured-streaming-programming-guide.html#continuous-processing

---

**OpenLakes v1.0.0 Framework** | Category 2 of 8 | 8 Patterns | ~122KB
