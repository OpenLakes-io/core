# Kafka Schema Registry Guide

OpenLakes includes **Apicurio Registry (Apache 2.0, Confluent-compatible)** for managing Avro, Protobuf, and JSON schemas in Kafka.

---

## What is Schema Registry?

Schema Registry provides a centralized repository for managing and validating schemas for Kafka topics.

### Benefits

✅ **Schema Evolution** - Safely evolve schemas with compatibility checking
✅ **Data Quality** - Enforce data contracts between producers and consumers
✅ **Decoupling** - Producers and consumers don't need to share schema files
✅ **Serialization** - Efficient binary serialization with Avro/Protobuf
✅ **Versioning** - Track schema changes over time
✅ **Integration** - Works with Kafka Connect, Debezium, Spark, ksqlDB

---

## Access Schema Registry

### REST API

- **Compatibility API (Confluent clients)**: http://schema-registry.openlakes.local/apis/ccompat/v6
- **Internal compatibility endpoint**: http://infrastructure-schema-registry:8081/apis/ccompat/v6
- **Native Apicurio API**: http://schema-registry.openlakes.local/apis/registry/v2

### Common Endpoints

```bash
# List all subjects (topics)
curl http://schema-registry.openlakes.local/apis/ccompat/v6/subjects

# Get schema versions for a subject
curl http://schema-registry.openlakes.local/apis/ccompat/v6/subjects/my-topic-value/versions

# Get specific schema version
curl http://schema-registry.openlakes.local/apis/ccompat/v6/subjects/my-topic-value/versions/1

# Get latest schema
curl http://schema-registry.openlakes.local/apis/ccompat/v6/subjects/my-topic-value/versions/latest

# Test compatibility
curl -X POST -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data '{"schema": "{...}"}' \
  http://schema-registry.openlakes.local/apis/ccompat/v6/compatibility/subjects/my-topic-value/versions/latest
```

---

## Schema Compatibility Modes

Schema Registry enforces compatibility rules when registering new schema versions.

| Mode | Description | Use Case |
|------|-------------|----------|
| **BACKWARD** (default) | New schema can read old data | Adding optional fields |
| **FORWARD** | Old schema can read new data | Removing fields |
| **FULL** | Both backward and forward compatible | Most restrictive |
| **NONE** | No compatibility checking | Development only |

### Change Compatibility Mode

```bash
# Set global compatibility
curl -X PUT -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data '{"compatibility": "FULL"}' \
  http://schema-registry.openlakes.local/apis/ccompat/v6/config

# Set per-subject compatibility
curl -X PUT -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data '{"compatibility": "BACKWARD"}' \
  http://schema-registry.openlakes.local/apis/ccompat/v6/config/my-topic-value
```

---

## Usage Examples

### 1. Avro Schema with Python

**Install Dependencies**:
```bash
pip install confluent-kafka[avro] avro-python3
```

**Producer** (with Avro schema):
```python
from confluent_kafka import Producer
from confluent_kafka.avro import AvroProducer

# Define Avro schema
value_schema_str = """
{
  "type": "record",
  "name": "User",
  "fields": [
    {"name": "name", "type": "string"},
    {"name": "age", "type": "int"},
    {"name": "email", "type": ["null", "string"], "default": null}
  ]
}
"""

# Create Avro producer
producer = AvroProducer({
    'bootstrap.servers': 'infrastructure-kafka:9092',
    'schema.registry.url': 'http://infrastructure-schema-registry:8081/apis/ccompat/v6'
}, default_value_schema=avro.loads(value_schema_str))

# Send message with schema validation
producer.produce(
    topic='users',
    value={'name': 'Alice', 'age': 30, 'email': 'alice@example.com'}
)
producer.flush()
```

**Consumer** (automatically gets schema):
```python
from confluent_kafka.avro import AvroConsumer

consumer = AvroConsumer({
    'bootstrap.servers': 'infrastructure-kafka:9092',
    'schema.registry.url': 'http://infrastructure-schema-registry:8081/apis/ccompat/v6',
    'group.id': 'my-consumer-group',
    'auto.offset.reset': 'earliest'
})

consumer.subscribe(['users'])

while True:
    msg = consumer.poll(1.0)
    if msg is None:
        continue

    # Value is automatically deserialized using schema
    user = msg.value()
    print(f"Name: {user['name']}, Age: {user['age']}")
```

---

### 2. Spark with Avro and Schema Registry

**Spark Kafka → Avro → Iceberg**:

```python
from pyspark.sql import SparkSession

spark = SparkSession.builder \
    .config("spark.jars.packages",
            "org.apache.spark:spark-sql-kafka-0-10_2.13:3.5.0,"
            "org.apache.spark:spark-avro_2.13:3.5.0") \
    .getOrCreate()

# Read from Kafka with Avro deserialization
df = spark.readStream \
    .format("kafka") \
    .option("kafka.bootstrap.servers", "infrastructure-kafka:9092") \
    .option("subscribe", "users") \
    .option("startingOffsets", "earliest") \
    .load()

# Deserialize Avro using Schema Registry
from pyspark.sql.avro.functions import from_avro

# Get schema from Schema Registry
schema_registry_url = "http://infrastructure-schema-registry:8081/apis/ccompat/v6"
subject = "users-value"

parsed_df = df.select(
    from_avro(
        col("value"),
        schemaRegistryUrl=schema_registry_url,
        subject=subject
    ).alias("data")
).select("data.*")

# Write to Iceberg
parsed_df.writeStream \
    .format("iceberg") \
    .outputMode("append") \
    .option("checkpointLocation", "s3a://openlakes/checkpoints/users/") \
    .toTable("lakehouse.bronze.users")
```

---

### 3. Debezium CDC with Schema Registry

Debezium can automatically register schemas for database change events.

**Debezium Connector Configuration** (with Schema Registry):

```json
{
  "name": "postgres-users-connector",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "database.hostname": "infrastructure-postgres",
    "database.port": "5432",
    "database.user": "openlakes",
    "database.password": "openlakes123",
    "database.dbname": "openlakes",
    "database.server.name": "openlakes-postgres",
    "table.include.list": "public.users",

    "key.converter": "io.confluent.connect.avro.AvroConverter",
    "key.converter.schema.registry.url": "http://infrastructure-schema-registry:8081/apis/ccompat/v6",
    "value.converter": "io.confluent.connect.avro.AvroConverter",
    "value.converter.schema.registry.url": "http://infrastructure-schema-registry:8081/apis/ccompat/v6",

    "topic.prefix": "cdc"
  }
}
```

**Debezium automatically registers schemas**:
- `cdc.public.users-key` - Primary key schema
- `cdc.public.users-value` - Full row schema with CDC metadata

---

### 4. Register Schema Manually (REST API)

**Register Avro Schema**:

```bash
curl -X POST -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data '{
    "schema": "{\"type\":\"record\",\"name\":\"User\",\"fields\":[{\"name\":\"name\",\"type\":\"string\"},{\"name\":\"age\",\"type\":\"int\"}]}"
  }' \
  http://schema-registry.openlakes.local/apis/ccompat/v6/subjects/users-value/versions
```

**Register JSON Schema**:

```bash
curl -X POST -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data '{
    "schemaType": "JSON",
    "schema": "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"age\":{\"type\":\"integer\"}},\"required\":[\"name\"]}"
  }' \
  http://schema-registry.openlakes.local/apis/ccompat/v6/subjects/events-value/versions
```

**Register Protobuf Schema**:

```bash
curl -X POST -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data '{
    "schemaType": "PROTOBUF",
    "schema": "syntax = \"proto3\"; message User { string name = 1; int32 age = 2; }"
  }' \
  http://schema-registry.openlakes.local/apis/ccompat/v6/subjects/users-proto-value/versions
```

---

## Schema Evolution Examples

### Adding Optional Field (BACKWARD Compatible)

**Version 1**:
```json
{
  "type": "record",
  "name": "User",
  "fields": [
    {"name": "name", "type": "string"},
    {"name": "age", "type": "int"}
  ]
}
```

**Version 2** (adds optional field with default):
```json
{
  "type": "record",
  "name": "User",
  "fields": [
    {"name": "name", "type": "string"},
    {"name": "age", "type": "int"},
    {"name": "email", "type": ["null", "string"], "default": null}
  ]
}
```

✅ **Compatible**: Old consumers can still read new data (ignore email field)

---

### Removing Field (FORWARD Compatible)

**Version 1**:
```json
{
  "type": "record",
  "name": "User",
  "fields": [
    {"name": "name", "type": "string"},
    {"name": "age", "type": "int"},
    {"name": "temp_field", "type": ["null", "string"], "default": null}
  ]
}
```

**Version 2** (removes field):
```json
{
  "type": "record",
  "name": "User",
  "fields": [
    {"name": "name", "type": "string"},
    {"name": "age", "type": "int"}
  ]
}
```

✅ **Compatible** (if mode is FORWARD): New consumers can read old data

---

## Monitoring and Management

### Check Schema Registry Health

```bash
# Health check
curl http://schema-registry.openlakes.local/apis/registry/v2/system/info

# Returns registry version/build metadata
```

### List All Schemas

```bash
# Get all subjects
curl http://schema-registry.openlakes.local/apis/ccompat/v6/subjects | jq

# Output:
# ["users-value", "events-value", "cdc.public.orders-value"]
```

### Delete Schema (Use with Caution!)

```bash
# Soft delete (can be restored)
curl -X DELETE http://schema-registry.openlakes.local/apis/ccompat/v6/subjects/my-topic-value/versions/1

# Hard delete (permanent)
curl -X DELETE http://schema-registry.openlakes.local/apis/ccompat/v6/subjects/my-topic-value?permanent=true
```

---

## Best Practices

### 1. Naming Conventions

- **Topic**: `domain.entity` (e.g., `sales.orders`, `user.events`)
- **Subject**: `<topic>-<key|value>` (auto-created by producers)
- **Schema Name**: Match entity name (e.g., `Order`, `UserEvent`)

### 2. Compatibility Mode Selection

- **BACKWARD** (default): Safe for most use cases, allows adding optional fields
- **FULL**: Use for critical schemas requiring strict compatibility
- **NONE**: Only for development environments

### 3. Schema Design

✅ **DO**:
- Use meaningful field names (`user_id` not `uid`)
- Add documentation to fields
- Use default values for new optional fields
- Version schema names (e.g., `UserV2`)

❌ **DON'T**:
- Change field types (breaks compatibility)
- Remove required fields (breaks old consumers)
- Rename fields (breaks both old/new consumers)

### 4. Testing

Always test schema compatibility before deploying:

```bash
# Test compatibility
curl -X POST -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data @new-schema.json \
  http://schema-registry.openlakes.local/apis/ccompat/v6/compatibility/subjects/users-value/versions/latest
```

---

## Troubleshooting

### Schema Not Found

**Error**: `Subject not found`

**Solution**:
1. Check subject name (case-sensitive)
2. Verify producer has sent at least one message
3. List all subjects to confirm:
   ```bash
   curl http://schema-registry.openlakes.local/apis/ccompat/v6/subjects
   ```

### Incompatible Schema

**Error**: `Schema being registered is incompatible with an earlier schema`

**Solution**:
1. Check compatibility mode
2. Review schema evolution rules
3. Test compatibility before registering:
   ```bash
   curl -X POST -H "Content-Type: application/vnd.schemaregistry.v1+json" \
     --data @new-schema.json \
     http://schema-registry.openlakes.local/apis/ccompat/v6/compatibility/subjects/my-topic-value/versions/latest
   ```

### Connection Refused

**Error**: `Connection refused` to Schema Registry

**Solution**:
1. Check Schema Registry is running:
   ```bash
   kubectl get pods -n openlakes | grep schema-registry
   ```
2. Check service:
   ```bash
   kubectl get svc -n openlakes infrastructure-schema-registry
   ```
3. View logs:
   ```bash
   kubectl logs -n openlakes deployment/infrastructure-schema-registry
   ```

---

## Integration with OpenLakes Components

### Debezium → Kafka → Schema Registry

Debezium automatically registers schemas for CDC events:

1. **Enable Avro converter** in Debezium connector
2. **Point to Schema Registry** URL
3. **Schemas auto-registered** when connector starts

### Spark Structured Streaming → Kafka with Avro

Use `from_avro` and `to_avro` functions with Schema Registry URL.

### Kafka Connect → Iceberg with Schema Registry

Kafka Connect Iceberg sink can deserialize Avro using Schema Registry.

---

## Next Steps

1. **Register your first schema** using REST API
2. **Create a Kafka producer** with Avro serialization
3. **Test schema evolution** with compatibility checking
4. **Integrate with Debezium** for CDC with schemas
5. **Use Spark** to process Avro-encoded Kafka streams

For more examples, see:
- [Apicurio Registry Documentation](https://www.apicur.io/registry/docs/apicurio-registry/latest/overview/assembly-overview.html)
- [Apache Avro Specification](https://avro.apache.org/docs/current/spec.html)
