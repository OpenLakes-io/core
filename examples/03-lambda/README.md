# Category 3: Lambda Architecture Patterns

This category demonstrates two architectural approaches for handling real-time and batch data processing.

## Overview

**Lambda Architecture** and **Kappa Architecture** represent two different philosophies for building data pipelines that serve both real-time and historical analytics.

### Pattern Summary

| Pattern | Type | Complexity | Use Case |
|---------|------|------------|----------|
| **3.1** | Lambda (Speed + Batch) | High | Real-time + accurate history |
| **3.2** | Kappa (Stream-only) | Medium | Pure event-driven processing |

---

## Pattern 3.1: Lambda Architecture (Speed + Batch Layers)

**File**: `01-speed-batch-layers.ipynb`

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Kafka (order_events)                   │
└────────────────────┬───────────────────┬────────────────┘
                     │                   │
         ┌───────────▼──────────┐   ┌───▼────────────────┐
         │   SPEED LAYER        │   │   BATCH LAYER      │
         │  Spark Streaming     │   │   Spark Batch      │
         │  (hourly windows)    │   │   (daily recompute)│
         └───────────┬──────────┘   └────────┬───────────┘
                     │                       │
         ┌───────────▼──────────┐   ┌───────▼────────────┐
         │  orders_speed        │   │  orders_batch      │
         │  (Iceberg)           │   │  (Iceberg)         │
         │  Real-time view      │   │  Accurate history  │
         └──────────────────────┘   └────────────────────┘
                     │                       │
                     └───────────┬───────────┘
                                 │
                       ┌─────────▼──────────┐
                       │   SERVING LAYER    │
                       │  Recent: Speed     │
                       │  History: Batch    │
                       └────────────────────┘
```

### Dual-Layer Benefits

1. **Speed Layer** (Streaming):
   - Real-time insights (sub-minute latency)
   - Hourly windowed aggregates
   - Immediate trend visibility
   - Approximations acceptable

2. **Batch Layer** (Daily):
   - Historical accuracy
   - Full deduplication
   - Late-arriving data handling
   - Complex enrichment

### When to Use Lambda

✅ **Use Lambda When:**
- Need both real-time dashboards AND accurate historical reports
- Late-arriving data is common (orders confirmed hours later)
- Regulatory requirements for batch recomputation
- Different logic for real-time vs. batch (complex deduplication)
- Speed-accuracy tradeoff is acceptable

❌ **Avoid Lambda When:**
- Operational complexity is a concern (two code paths)
- Team is small (harder to maintain)
- Event-time processing is sufficient
- All data flows through event stream

### Key Code: Speed Layer

```python
# Spark Streaming with hourly windows
df_speed_agg = df_parsed \
    .withWatermark("order_timestamp", "10 minutes") \
    .groupBy(window(col("order_timestamp"), "1 hour")) \
    .agg(
        count("*").alias("total_orders"),
        sum("order_value").alias("total_revenue"),
        avg("order_value").alias("avg_order_value")
    )

# Write to speed table
df_speed_agg.writeStream \
    .format("iceberg") \
    .option("path", "lakehouse.prod.orders_speed") \
    .trigger(processingTime='10 seconds') \
    .start()
```

### Key Code: Batch Layer

```python
# Batch recompute with deduplication
df_batch_agg = df_batch_parsed \
    .dropDuplicates(["order_id"]) \  # Full dedup
    .withColumn("order_date", to_date(col("order_timestamp"))) \
    .groupBy("order_date") \
    .agg(
        count("*").alias("total_orders"),
        sum("order_value").alias("total_revenue"),
        avg("order_value").alias("avg_order_value"),
        countDistinct("customer_id").alias("unique_customers")  # Enriched
    )

# Overwrite daily partition
df_batch_agg.writeTo("lakehouse.prod.orders_batch") \
    .using("iceberg") \
    .overwritePartitions()
```

### Serving Layer Query

```sql
-- Recent data (last 24h): Use speed layer
SELECT * FROM lakehouse.prod.orders_speed
WHERE order_hour >= CURRENT_TIMESTAMP - INTERVAL 24 HOURS

UNION ALL

-- Historical data (> 24h): Use batch layer
SELECT * FROM lakehouse.prod.orders_batch
WHERE order_date < CURRENT_DATE - INTERVAL 1 DAY
```

---

## Pattern 3.2: Kappa Architecture (Stream-Only)

**File**: `02-kappa-stream-only.ipynb`

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  Kafka (event_log)                      │
│              [Source of Truth, Retained]                │
└────────────────────────┬────────────────────────────────┘
                         │
              ┌──────────▼───────────┐
              │  SINGLE STREAM PATH  │
              │  Spark Continuous    │
              │  Event-time windows  │
              │  Watermarks enabled  │
              └──────────┬───────────┘
                         │
              ┌──────────▼───────────┐
              │    event_stream      │
              │    (Iceberg)         │
              │  Time-partitioned    │
              └──────────────────────┘

     ┌───────────────────────────────────────┐
     │  REPROCESSING (Kappa Advantage)       │
     │  1. Stop streaming job                │
     │  2. Clear checkpoint                  │
     │  3. Replay Kafka from beginning       │
     │  4. Same code, fresh results          │
     └───────────────────────────────────────┘
```

### Single-Path Benefits

1. **Operational Simplicity**:
   - One code path (not two)
   - Easier to maintain
   - Unified batch + streaming API
   - Fewer failure modes

2. **Event-Time Semantics**:
   - Watermarks handle late data
   - Event timestamps (not processing time)
   - Deterministic results
   - Idempotent reprocessing

3. **Reprocessing**:
   - Replay Kafka from beginning
   - Same streaming code
   - No separate batch job
   - Kafka is source of truth

### When to Use Kappa

✅ **Use Kappa When:**
- All data flows through Kafka/event stream
- Kafka retention covers reprocessing window (e.g., 30 days)
- Event-time semantics are sufficient
- Prefer operational simplicity
- Team is small or focused on streaming
- Idempotent processing is achievable

❌ **Avoid Kappa When:**
- Need complex batch-only transformations
- Historical data not in Kafka
- Kafka retention too short for reprocessing
- Batch and streaming have fundamentally different logic
- Storage costs of Kafka retention are prohibitive

### Key Code: Event-Time Processing

```python
# Single streaming path with event-time windows
df_agg = df_parsed \
    .withWatermark("event_timestamp", "20 seconds") \  # Late data handling
    .groupBy(
        window(col("event_timestamp"), "5 minutes"),  # Event-time window
        col("event_type")
    ).agg(
        count("*").alias("total_events"),
        avg("duration_ms").alias("avg_duration_ms")
    )

# Write to Iceberg with checkpointing
df_agg.writeStream \
    .format("iceberg") \
    .option("checkpointLocation", "/checkpoints/event_stream") \
    .trigger(processingTime='2 seconds') \
    .start()
```

### Reprocessing Pattern

```bash
# Kappa reprocessing workflow

# 1. Stop current streaming job
kubectl delete sparkapplication event-processor

# 2. Clear checkpoint (forces full reprocessing)
hdfs dfs -rm -r /checkpoints/event_stream

# 3. (Optional) Truncate target table for clean slate
spark-sql -e "TRUNCATE TABLE lakehouse.prod.event_stream"

# 4. Restart with earliest offset
kubectl apply -f sparkapplication-event-processor.yaml
# Job reads from Kafka beginning, recomputes all windows
```

**Why This Works**:
- Kafka retains all events (e.g., 30 days)
- Event timestamps preserved
- Same streaming code
- Deterministic results (idempotent)

---

## Lambda vs. Kappa Comparison

### Architectural Differences

| Aspect | Lambda Architecture | Kappa Architecture |
|--------|---------------------|-------------------|
| **Processing Layers** | Speed + Batch (dual) | Stream only (single) |
| **Code Complexity** | Two code paths | One code path |
| **Operational Overhead** | Higher (manage 2 systems) | Lower (manage 1 system) |
| **Late Data Handling** | Batch recomputes daily | Watermarks in stream |
| **Reprocessing** | Separate batch job | Replay Kafka stream |
| **Accuracy** | Batch guarantees accuracy | Event-time semantics |
| **Latency** | Speed: seconds, Batch: hours | Continuous: sub-second |
| **Storage** | Speed + Batch tables | Single stream table |
| **Team Size** | Larger team (2 systems) | Smaller team (1 system) |

### Performance Characteristics

| Metric | Lambda | Kappa |
|--------|--------|-------|
| **Real-time Latency** | 1-10 seconds (speed) | 1-5 seconds (stream) |
| **Historical Accuracy** | Batch guarantees | Event-time guarantees |
| **Reprocessing Time** | Hours (batch job) | Hours (Kafka replay) |
| **Storage Overhead** | 2x (speed + batch) | 1x (stream table) |
| **Operational Cost** | Higher (dual systems) | Lower (single system) |

### Decision Matrix

**Choose Lambda If:**
- ✅ Real-time dashboards + regulatory batch reports required
- ✅ Late-arriving data is common (hours/days later)
- ✅ Different transformations for real-time vs. batch
- ✅ Complex deduplication or enrichment in batch
- ✅ Historical data not in event stream
- ✅ Large team can maintain two systems

**Choose Kappa If:**
- ✅ All data flows through Kafka/event stream
- ✅ Kafka retention covers reprocessing needs
- ✅ Event-time semantics sufficient for accuracy
- ✅ Prefer operational simplicity (one system)
- ✅ Small team focused on streaming
- ✅ Idempotent processing is achievable

---

## Technology Stack

Both patterns use:

- **Apache Kafka**: Event stream source of truth
- **Apache Spark 4.1**: Structured Streaming for both patterns
- **Apache Iceberg 1.8.0**: Lakehouse storage with ACID transactions
- **MinIO**: S3-compatible object storage
- **Airflow**: Orchestration (batch jobs, monitoring)

### Lambda-Specific:
- **Dual Spark Jobs**: Streaming (speed) + Batch (daily)
- **Dual Iceberg Tables**: `orders_speed` + `orders_batch`

### Kappa-Specific:
- **Single Spark Streaming Job**: Continuous processing
- **Single Iceberg Table**: `event_stream`
- **Kafka Retention**: Configured for reprocessing window

---

## Running the Patterns

### Via JupyterHub (Interactive Learning)

```bash
# Lambda Architecture
Open: /opt/jupyterhub/notebooks/03-lambda/01-speed-batch-layers.ipynb
Run All Cells → Speed layer streams 30s → Batch layer recomputes

# Kappa Architecture
Open: /opt/jupyterhub/notebooks/03-lambda/02-kappa-stream-only.ipynb
Run All Cells → Continuous streaming 30s → Event-time windows
```

### Via Airflow (Automated Execution)

```bash
# Lambda Architecture
airflow dags trigger 01_lambda_speed_batch

# Kappa Architecture
airflow dags trigger 02_kappa_stream_only
```

### Production Deployment (K8s Spark Operator)

See: `STREAMING_DEPLOYMENT.md` for converting notebooks to long-running K8s jobs.

**Lambda Production**:
- Speed layer: Continuous K8s SparkApplication
- Batch layer: Airflow daily job

**Kappa Production**:
- Single continuous K8s SparkApplication
- Airflow monitors health, handles upgrades

---

## Key Learnings

### Lambda Architecture

1. **Dual Code Paths**:
   - More complex to maintain
   - Allows different transformations
   - Speed can approximate, batch guarantees accuracy

2. **Storage Overhead**:
   - Two tables (speed + batch)
   - Speed data eventually replaced by batch
   - Higher storage cost

3. **Use Cases**:
   - Financial reporting (real-time + regulatory batch)
   - E-commerce analytics (live trends + accurate attribution)
   - IoT monitoring (real-time alerts + daily summaries)

### Kappa Architecture

1. **Operational Simplicity**:
   - Single code path
   - Easier to reason about
   - Unified batch + streaming API

2. **Kafka as Source of Truth**:
   - Must retain events for reprocessing
   - Replay from beginning to recompute
   - Same streaming code for historical data

3. **Use Cases**:
   - Event log processing
   - Application monitoring
   - User activity tracking
   - Audit trail processing

---

## Common Pitfalls

### Lambda Pitfalls

❌ **Dual Code Drift**: Speed and batch logic diverge over time
   - **Solution**: Share common transformation functions

❌ **Over-Engineering**: Using Lambda when Kappa would suffice
   - **Solution**: Start with Kappa, migrate to Lambda if needed

❌ **Incomplete Batch Correction**: Batch doesn't fully replace speed
   - **Solution**: Clear serving layer query (recent = speed, old = batch)

### Kappa Pitfalls

❌ **Insufficient Kafka Retention**: Can't replay for reprocessing
   - **Solution**: Set retention to 30+ days, monitor storage

❌ **Non-Idempotent Processing**: Different results on replay
   - **Solution**: Use event timestamps, avoid processing-time operations

❌ **Late Data Beyond Watermark**: Events arrive after window closes
   - **Solution**: Tune watermark delay, accept trade-off

---

## External Resources

- [Lambda Architecture (Nathan Marz)](http://nathanmarz.com/blog/how-to-beat-the-cap-theorem.html) - Original Lambda concept
- [Kappa Architecture (Jay Kreps)](https://www.oreilly.com/radar/questioning-the-lambda-architecture/) - Kappa proposal
- [Spark Structured Streaming Guide](https://spark.apache.org/docs/latest/structured-streaming-programming-guide.html)
- [Event Time vs Processing Time](https://www.oreilly.com/library/view/streaming-systems/9781491983867/)

---

## Summary

**Category 3 demonstrates two architectural patterns**:

1. **Lambda**: Dual-layer (speed + batch) for real-time + accuracy
2. **Kappa**: Single streaming layer for operational simplicity

**Key Takeaway**: Choose based on team size, operational complexity, and accuracy requirements. Start with Kappa (simpler), migrate to Lambda if dual-layer benefits justify the complexity.

**Next**: Category 4 (Federated Query Patterns) demonstrates querying across multiple data sources using Trino.
