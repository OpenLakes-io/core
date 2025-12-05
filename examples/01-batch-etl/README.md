# Category 1: Batch ETL Patterns

6 pipeline patterns demonstrating batch data processing approaches.

## Patterns

| # | Pattern | Description | Use Case |
|---|---------|-------------|----------|
| 1.1 | Basic ETL | Traditional ETL with Spark | Daily sales aggregation |
| 1.2 | ELT (Trino) | SQL-based transformations | Customer segmentation |
| 1.3 | Multi-Source | Join 3 sources | Customer 360 view |
| 1.4 | SCD Type 2 | Historical tracking | Price history, audit trail |
| 1.5 | SCD Type 1 | Current state only | Reference data updates |
| 1.6 | Batch Aggregation | Pre-compute summaries | Dashboard acceleration |

## Running

**Interactive (JupyterHub)**: http://localhost:30888
- Development defaults, run cells interactively

**Automated (Airflow)**: http://localhost:30082
- Production parameters via Papermill
