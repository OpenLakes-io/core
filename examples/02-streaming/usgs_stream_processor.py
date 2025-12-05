#!/usr/bin/env python3
"""
Structured Streaming job that reads USGS earthquake events from Kafka and writes them
to an Iceberg table for downstream analytics. This script is launched via Airflow's
SparkSubmitOperator for full observability.
"""
from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.types import (
    StructType,
    StructField,
    StringType,
    DoubleType,
    LongType,
)

KAFKA_TOPIC = "usgs_quakes"
KAFKA_BOOTSTRAP = "infrastructure-kafka.openlakes.svc.cluster.local:9092"
ICEBERG_TABLE = "lakehouse.streaming.usgs_quakes"
CHECKPOINT_PATH = "s3a://openlakes/checkpoints/usgs_quakes_stream/"


def build_spark_session() -> SparkSession:
    return (
        SparkSession.builder.appName("USGSEarthquakeStream")
        .config(
            "spark.jars.packages",
            ",".join(
                [
                    "org.apache.spark:spark-sql-kafka-0-10_2.13:3.5.4",
                    "org.apache.iceberg:iceberg-spark-runtime-3.5_2.13:1.8.0",
                ]
            ),
        )
        .config(
            "spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions"
        )
        .config("spark.sql.catalog.lakehouse", "org.apache.iceberg.spark.SparkCatalog")
        .config("spark.sql.catalog.lakehouse.catalog-impl", "org.apache.iceberg.spark.SparkSessionCatalog")
        .config("spark.sql.catalog.lakehouse.type", "hadoop")
        .config("spark.sql.catalog.lakehouse.warehouse", "s3a://openlakes/warehouse/")
        .config("spark.hadoop.fs.s3a.endpoint", "http://infrastructure-minio:9000")
        .config("spark.hadoop.fs.s3a.access.key", "admin")
        .config("spark.hadoop.fs.s3a.secret.key", "admin123")
        .config("spark.hadoop.fs.s3a.path.style.access", "true")
        .getOrCreate()
    )


def main():
    spark = build_spark_session()
    schema = (
        StructType()
        .add("event_id", StringType())
        .add("place", StringType())
        .add("magnitude", DoubleType())
        .add("ts", LongType())
        .add("longitude", DoubleType())
        .add("latitude", DoubleType())
        .add("depth_km", DoubleType())
    )

    print("🚀 Starting structured streaming job for USGS events")

    raw_stream = (
        spark.readStream.format("kafka")
        .option("kafka.bootstrap.servers", KAFKA_BOOTSTRAP)
        .option("subscribe", KAFKA_TOPIC)
        .option("startingOffsets", "latest")
        .load()
    )

    parsed = (
        raw_stream.selectExpr("CAST(value AS STRING) as json_payload")
        .select(F.from_json("json_payload", schema).alias("event"))
        .select("event.*")
        .withColumn("event_time", (F.col("ts") / 1000).cast("timestamp"))
    )

    spark.sql(f"CREATE TABLE IF NOT EXISTS {ICEBERG_TABLE} "
              "(event_id string, place string, magnitude double, ts long, longitude double, latitude double, depth_km double, event_time timestamp) "
              "USING iceberg")

    query = (
        parsed.writeStream.format("iceberg")
        .outputMode("append")
        .option("checkpointLocation", CHECKPOINT_PATH)
        .toTable(ICEBERG_TABLE)
    )

    query.awaitTermination()


if __name__ == "__main__":
    main()
