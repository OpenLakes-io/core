"""
Airflow DAG showcasing how Papermill + Spark orchestrate open-data ingestion pipelines.
The DAG performs:
1. NOAA batch ETL via PapermillOperator (runs the updated 01-basic-etl notebook).
2. USGS earthquake ingestion into Kafka (Python/Bash task).
3. Spark structured streaming job that writes USGS events to Iceberg.
"""
from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.providers.apache.spark.operators.spark_submit import SparkSubmitOperator
from airflow.providers.papermill.operators.papermill import PapermillOperator

DEFAULT_ARGS = {
    "owner": "openlakes",
    "depends_on_past": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
}

NOTEBOOK_PATH = "/opt/airflow/dags/examples/01-batch-etl/01-basic-etl.ipynb"
NOTEBOOK_OUTPUT = "/opt/airflow/artifacts/noaa_batch_etl-{{ ds }}.ipynb"
USGS_PRODUCER_CMD = (
    "python /opt/airflow/dags/examples/02-streaming/usgs_to_kafka.py "
    "--bootstrap-servers infrastructure-kafka.openlakes.svc.cluster.local:9092 "
    "--topic usgs_quakes --duration 180"
)
SPARK_APP = "/opt/airflow/dags/examples/02-streaming/usgs_stream_processor.py"

with DAG(
    dag_id="open_data_ingestion",
    default_args=DEFAULT_ARGS,
    start_date=datetime(2025, 1, 1),
    schedule="@hourly",
    catchup=False,
) as dag:
    noaa_batch_etl = PapermillOperator(
        task_id="noaa_batch_etl",
        input_nb=NOTEBOOK_PATH,
        output_nb=NOTEBOOK_OUTPUT,
        parameters={"execution_date": "{{ ds }}", "environment": "production"},
    )

    usgs_feed_to_kafka = BashOperator(
        task_id="usgs_feed_to_kafka",
        bash_command=USGS_PRODUCER_CMD,
    )

    usgs_stream_processor = SparkSubmitOperator(
        task_id="usgs_stream_processor",
        application=SPARK_APP,
        conn_id="spark_default",
        name="usgs-stream-processor",
        verbose=True,
    )

    noaa_batch_etl >> usgs_feed_to_kafka >> usgs_stream_processor
