# Category 5: Analytics & BI Patterns

This category demonstrates business intelligence and analytics workflows using Superset, Trino, and Iceberg.

## Overview

**Analytics & BI** patterns enable business users to derive insights from data through self-service dashboards, scheduled reports, and operational syncs.

### Pattern Summary

| Pattern | Type | Audience | Frequency |
|---------|------|----------|-----------|
| **5.1** | Self-Service Dashboards | Business users | Interactive |
| **5.2** | Data Exploration | Data analysts | Ad-hoc |
| **5.3** | Scheduled Reports | Executives | Weekly/Monthly |
| **5.4** | Reverse ETL | Applications | Daily |

---

## Pattern 5.1: Self-Service SQL Analytics

**File**: `01-superset-self-service.ipynb`

### Use Case

Enable marketing, sales, and product teams to create their own SQL dashboards without data engineering support.

### Architecture

```
Business Users (SQL + Drag-Drop)
    ↓
Superset (BI Platform)
    ↓
Trino (Query Engine)
    ↓
Iceberg (Lakehouse)
```

### Key Features

- **SQL Editor**: Write custom queries
- **Chart Builder**: Drag-drop visualization
- **Scheduled Refresh**: Auto-update dashboards
- **Alerts**: Notifications on thresholds
- **RBAC**: Role-based data access

### When to Use

✅ Standard SQL queries (aggregations, joins)
✅ Business users comfortable with SQL
✅ High volume of ad-hoc requests
✅ Need for departmental autonomy

---

## Pattern 5.2: Interactive Data Exploration

**Reference**: Existing pattern in `examples/notebooks/01-spark-iceberg-trino-pipeline.ipynb`

### Use Case

Data analysts use JupyterHub + Spark for exploratory data analysis.

### Capabilities

- Pandas/PySpark dataframes
- matplotlib/seaborn visualizations
- Statistical analysis
- Ad-hoc transformations

---

## Pattern 5.3: Scheduled Report Generation

**File**: `examples/dags/05-analytics-bi/03_scheduled_report_generation.py` (DAG only)

### Use Case

Generate weekly sales reports and email to executives.

### Architecture

```
Iceberg → Trino Query → Pandas → CSV/PDF → MinIO → Email
```

### Report Types

- **Executive Summary**: PDF with charts
- **Detailed Metrics**: CSV with full data
- **Visualizations**: PNG charts
- **Multi-format**: Email attachments

### Schedule Examples

| Frequency | Use Case | Recipients |
|-----------|----------|------------|
| Daily | Operational metrics | Team leads |
| Weekly | Performance summaries | Managers |
| Monthly | Executive summaries | Leadership |
| Quarterly | Board presentations | Executives |

### Key Code

```python
# Query data via Trino
cursor.execute(\"\"\"
    SELECT region, SUM(revenue) as total
    FROM sales_data
    WHERE sale_date >= CURRENT_DATE - INTERVAL '7' DAY
    GROUP BY region
\"\"\")

# Generate report
df = pd.DataFrame(cursor.fetchall())
df.to_csv('weekly_sales.csv')

# Email via Airflow
EmailOperator(
    to=['executives@company.com'],
    subject='Weekly Sales Report',
    html_content=summary,
    files=['weekly_sales.csv']
)
```

---

## Pattern 5.4: Reverse ETL

**File**: `examples/dags/05-analytics-bi/04_reverse_etl_to_postgres.py` (DAG only)

### Use Case

Push pre-computed customer lifetime value from Iceberg to PostgreSQL for application use.

### Architecture

```
Iceberg (analytics) → Spark → PostgreSQL (operational)
```

### Concept: Reverse ETL

| Direction | Traditional ETL | Reverse ETL |
|-----------|----------------|-------------|
| **Flow** | Operational → Analytics | Analytics → Operational |
| **Purpose** | Historical analysis | Application enrichment |
| **Latency** | Hours/days | Daily sync |

### Use Cases

1. **Customer Segmentation**:
   - Compute segments in lakehouse (complex ML)
   - Push to PostgreSQL for app personalization
   - App displays content based on segment

2. **Product Recommendations**:
   - ML model scores products in Iceberg
   - Push top 10 per user to PostgreSQL
   - App queries PostgreSQL (fast, no complex joins)

3. **Pre-Computed Metrics**:
   - Calculate KPIs in lakehouse
   - Push to PostgreSQL operational tables
   - Dashboards query PostgreSQL (not lakehouse)

### Key Code

```python
# Read analytics from Iceberg
df = spark.sql(\"\"\"
    SELECT
        customer_id,
        SUM(revenue) as lifetime_value,
        CASE
            WHEN SUM(revenue) > 10000 THEN 'VIP'
            ELSE 'Standard'
        END as segment
    FROM lakehouse.prod.orders
    GROUP BY customer_id
\"\"\")

# Write to PostgreSQL
df.write \
    .format("jdbc") \
    .option("url", "jdbc:postgresql://...") \
    .option("dbtable", "customer_metrics") \
    .mode("overwrite") \
    .save()
```

### Benefits

✅ **App Performance**: No complex analytics in operational DB
✅ **Separation**: Analytics workload doesn't impact app
✅ **Pre-Computation**: Expensive aggregations done once

---

## Technology Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| **BI Platform** | Superset | Self-service dashboards |
| **Query Engine** | Trino | Fast SQL analytics |
| **Lakehouse** | Iceberg | Source of truth |
| **Notebook** | JupyterHub | Exploratory analysis |
| **Orchestration** | Airflow | Scheduled reports, reverse ETL |

---

## Running the Patterns

### Via JupyterHub

```bash
# Pattern 5.1
Open: /opt/jupyterhub/notebooks/05-analytics-bi/01-superset-self-service.ipynb

# Pattern 5.2
Open: /opt/jupyterhub/notebooks/01-spark-iceberg-trino-pipeline.ipynb
```

### Via Airflow

```bash
# Pattern 5.1
airflow dags trigger 01_superset_self_service

# Pattern 5.3
airflow dags trigger 03_scheduled_report_generation

# Pattern 5.4
airflow dags trigger 04_reverse_etl_to_postgres
```

---

## Production Setup

### Superset Configuration

```yaml
# values.yaml
supersetNode:
  connections:
    db_uri: trino://admin@analytics-trino:8080/iceberg/prod

  auth_type: LDAP

  cache_config:
    CACHE_TYPE: redis
    CACHE_DEFAULT_TIMEOUT: 3600
```

### Email Configuration (Airflow)

```yaml
# airflow.cfg
[email]
email_backend = airflow.providers.sendgrid.utils.emailer.send_email
email_conn_id = sendgrid_default
```

---

## Key Learnings

### Self-Service Analytics

1. **Empower Users**: Business teams create own dashboards
2. **Reduce Backlog**: No data team tickets for reports
3. **Governance**: Certified datasets, RBAC, query limits

### Scheduled Reports

1. **Consistency**: Same report every week/month
2. **Automation**: No manual data pulls
3. **Distribution**: Email, Slack, SharePoint

### Reverse ETL

1. **Close the Loop**: Analytics → Operational
2. **Performance**: Pre-compute in lakehouse, fast reads in app
3. **Freshness**: Daily sync vs real-time (trade-off)

---

## Common Pitfalls

❌ **Ungoverned Self-Service**: Users create duplicate metrics
   - **Solution**: Certified datasets, metric definitions

❌ **Report Overload**: Too many unused reports
   - **Solution**: Track usage, archive inactive reports

❌ **Stale Reverse ETL**: App uses outdated analytics
   - **Solution**: Freshness checks, alerting on sync failures

---

## External Resources

- [Superset Documentation](https://superset.apache.org/docs/intro)
- [Trino SQL Guide](https://trino.io/docs/current/sql.html)
- [Reverse ETL Best Practices](https://www.getcensus.com/blog/what-is-reverse-etl)

---

## Summary

**Category 5 demonstrates analytics and BI workflows** from self-service dashboards to scheduled reports to reverse ETL. Empower business users while maintaining governance.

**Next**: Category 6 (Log & Event Analytics) demonstrates application logs, audit trails, and clickstream analysis.
