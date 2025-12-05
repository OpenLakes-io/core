# Category 4: Federated Query Patterns

This category demonstrates using Trino to query across multiple data sources without ETL.

## Overview

**Federated queries** allow you to join data from operational databases (PostgreSQL) and analytical lakehouses (Iceberg) in a single SQL query—eliminating the need for ETL pipelines for ad-hoc analysis.

### Pattern Summary

| Pattern | Sources | Use Case | Complexity |
|---------|---------|----------|------------|
| **4.1** | PostgreSQL + Iceberg | Operational + Analytical | Low |
| **4.2** | Spark Batch + Streaming → Iceberg | Multi-engine writes | Medium |
| **4.3** | PostgreSQL + 2x Iceberg | Customer 360 | Low |

---

## Pattern 4.1: Operational + Analytical Federation

**File**: `01-operational-analytical.ipynb`

### Use Case

Join live order status (PostgreSQL) with historical customer purchase patterns (Iceberg) to provide sales reps with complete customer context.

### Architecture

```
PostgreSQL (current_orders)      Iceberg (historical_sales)
    ↓                                   ↓
    └──────────→ Trino ←────────────────┘
                  ↓
         Unified Result Set
```

### Key Code

```python
# Spark reads from both sources
df_postgres = spark.read.format("jdbc").option("dbtable", "current_orders").load()
df_iceberg = spark.table("lakehouse.demo.historical_sales")

# Federated join
df_federated = df_postgres.join(df_iceberg, on="customer_id", how="left")
```

### When to Use

✅ Ad-hoc queries combining operational and analytical data
✅ Real-time dashboards with historical context
✅ Customer 360 views
❌ Repeated queries (materialize instead)

---

## Pattern 4.2: Multi-Engine Iceberg Access

**File**: `02-multi-engine-iceberg.ipynb`

### Use Case

Product inventory where Spark Batch loads historical data, Spark Streaming applies real-time updates, and Trino queries the unified view.

### Architecture

```
Spark Batch ────────┐
                    ├──→ Iceberg (ACID)
Spark Streaming ────┘      ↓
                        Trino Query
```

### ACID Guarantees

- **Concurrent writes**: Batch and streaming write simultaneously
- **Snapshot isolation**: Readers see consistent view
- **Optimistic concurrency**: No locks required
- **Durability**: Metadata in S3/MinIO

### Key Code

```python
# Spark Batch: Overwrite partition
df_batch.writeTo(full_table).using("iceberg").overwritePartitions()

# Spark Streaming: MERGE updates
spark.sql(f"""
    MERGE INTO {full_table} AS target
    USING updates AS source
    ON target.product_id = source.product_id
    WHEN MATCHED THEN UPDATE SET ...
""")
```

### When to Use

✅ Multiple write sources (batch + streaming)
✅ Unified analytics across engines
✅ No vendor lock-in (open format)
✅ Engine specialization

---

## Pattern 4.3: Cross-Database Federation

**File**: `03-cross-database.ipynb`

### Use Case

Customer 360 view combining customer master (PostgreSQL), transaction history (Iceberg), and product catalog (Iceberg) in a 3-way join.

### Architecture

```
PostgreSQL (customers) ──┐
                         │
Iceberg (transactions) ──┼──→ Trino 3-Way Join
                         │
Iceberg (products) ──────┘
```

### Key Code

```python
# Three-way federated join
df_customer_360 = df_transactions \
    .join(df_customers, on="customer_id") \
    .join(df_products, on="product_id")
```

### Trino SQL Example

```sql
SELECT
    c.customer_name,
    p.product_name,
    t.transaction_date,
    t.quantity * p.unit_price AS amount
FROM iceberg.demo.transactions t
JOIN postgresql.public.customers c ON t.customer_id = c.customer_id
JOIN iceberg.demo.products p ON t.product_id = p.product_id
WHERE t.transaction_date >= CURRENT_DATE - INTERVAL '30' DAY;
```

---

## Federated Query vs. ETL

### When to Use Federation

✅ Ad-hoc queries (exploratory analysis)
✅ One-time reports
✅ Real-time operational data needed
✅ Flexible query requirements

### When to Use ETL Instead

❌ Repeated queries (high volume)
❌ Complex transformations
❌ Operational DB performance impact
❌ Production dashboards (SLA requirements)

---

## Technology Stack

- **Trino**: Federated query engine
- **PostgreSQL**: Operational database
- **Apache Iceberg**: Lakehouse table format
- **Apache Spark**: ETL and federated queries
- **Superset**: BI dashboards

---

## Running the Patterns

### Via JupyterHub

```bash
# Pattern 4.1
Open: /opt/jupyterhub/notebooks/04-federated/01-operational-analytical.ipynb

# Pattern 4.2
Open: /opt/jupyterhub/notebooks/04-federated/02-multi-engine-iceberg.ipynb

# Pattern 4.3
Open: /opt/jupyterhub/notebooks/04-federated/03-cross-database.ipynb
```

### Via Airflow

```bash
airflow dags trigger 01_operational_analytical
airflow dags trigger 02_multi_engine_iceberg
airflow dags trigger 03_cross_database
```

---

## Production Setup

### Trino Catalogs Configuration

```yaml
# values.yaml for Trino
additionalCatalogs:
  postgresql:
    connector.name: postgresql
    connection-url: jdbc:postgresql://infrastructure-postgresql:5432/openlakes
    connection-user: admin
    connection-password: admin123

  iceberg:
    connector.name: iceberg
    iceberg.catalog.type: hadoop
    hive.metastore.uri: thrift://infrastructure-hive-metastore:9083
```

### Superset Integration

```python
# Connect Superset to Trino
SQLAlchemy URI: trino://admin@analytics-trino:8080/iceberg/demo

# Create dataset from federated query
SELECT
    c.region,
    SUM(t.quantity * p.unit_price) as revenue
FROM iceberg.demo.transactions t
JOIN postgresql.public.customers c ON t.customer_id = c.customer_id
JOIN iceberg.demo.products p ON t.product_id = p.product_id
GROUP BY c.region;
```

---

## Key Learnings

### Federated Query Benefits

1. **No ETL Required**: Query across systems directly
2. **Real-Time Data**: Access operational databases live
3. **Flexibility**: Ad-hoc joins, exploratory analysis
4. **SQL Access**: Analysts can query without code

### ACID with Iceberg

1. **Concurrent Writes**: Multiple engines write safely
2. **Snapshot Isolation**: Consistent reads
3. **Time Travel**: Query historical snapshots
4. **Schema Evolution**: Add columns without rewrites

### Common Pitfalls

❌ **Overusing Federation**: Repeated queries should be materialized
❌ **Operational Impact**: Heavy queries on production PostgreSQL
❌ **No Transformations**: Federation is for reads, not complex ETL
❌ **Performance Expectations**: Federated queries slower than pre-joined data

---

## External Resources

- [Trino Documentation](https://trino.io/docs/current/)
- [Iceberg Multi-Engine Support](https://iceberg.apache.org/multi-engine-support/)
- [PostgreSQL JDBC Connector](https://trino.io/docs/current/connector/postgresql.html)

---

## Summary

**Category 4 demonstrates federated queries** for joining operational and analytical data sources without ETL. Use Trino for ad-hoc SQL queries, Iceberg for multi-engine ACID writes, and Superset for visualization.

**Next**: Category 5 (Analytics & BI) demonstrates self-service analytics, scheduled reports, and reverse ETL patterns.
