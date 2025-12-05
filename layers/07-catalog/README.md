# Layer 07 - Catalog

This layer contains OpenMetadata catalog deployment and configuration.

## Bot Setup & Service Registration

### Single Source of Truth Pattern

The bot setup, service registration, and validation logic is maintained in `test-bot-setup.sh` and automatically injected into the Kubernetes Job YAML template. This provides:

- ✅ **Syntax highlighting** in your editor for shell scripts
- ✅ **Type checking** and validation while editing
- ✅ **Single source of truth** - no copy/paste between files
- ✅ **Easy testing** - run the script directly for local testing
- ✅ **Consolidated automation** - one job handles bot creation, service registration, and validation

### What It Does

The `bot-and-connector-setup-job` performs the following tasks:

1. **Bot Creation** - Creates OpenMetadata bot user with JWT authentication
2. **Service Registration** - Registers all OpenLakes data sources:
   - PostgreSQL, Trino, StarRocks (databases)
   - Kafka, Debezium (messaging)
   - Airflow, Flink, Spark, Meltano (pipelines)
   - Superset (dashboards)
   - MinIO (storage)
   - OpenSearch (search)
3. **Validation** - Tests bot authentication and verifies service connectivity

### File Structure

- **`test-bot-setup.sh`** - The main script containing all bot setup, service registration, and validation logic
- **`templates/bot-and-connector-setup-job.yaml`** - Kubernetes Job template that injects the script using Helm's `.Files.Get`

### How It Works

The YAML template uses Helm's `.Files.Get` function to read and inject the script:

```yaml
command:
  - sh
  - -c
  - |
    set -e
    apk add --no-cache curl jq kubectl
{{ .Files.Get "test-bot-setup.sh" | indent 10 }}
```

### Testing Locally

For local testing with port-forwarding, add these variables at the top of `test-bot-setup.sh`:

```bash
# Local testing configuration (comment out for production)
OM_HOST="localhost"
OM_PORT="30585"
ADMIN_USER="admin"
NAMESPACE="default"
```

Then run:
```bash
./test-bot-setup.sh
```

### Deployment

When you make changes to `test-bot-setup.sh`, they will automatically be included in the next Helm deployment:

```bash
helm upgrade --install catalog-layer ./
```

No need to manually copy between files!
