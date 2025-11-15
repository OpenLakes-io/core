# Airflow Plugins Installation Guide

## Overview
This guide shows three methods to add plugins to the Airflow instance in the OpenLakes cluster.

## Current Setup
- **Airflow Version**: 3.1.2 (check `layers/04-orchestration/values.yaml`)
- **Location**: Layer 04-orchestration
- **Namespace**: openlakes
- **DAGs Volume**: PVC mounted at `/opt/airflow/dags`
- **Plugins Folder**: `/opt/airflow/plugins` (not yet mounted)

---

## Method 1: Add Plugins Volume (Best for Custom Python Code)

### Step 1: Create Plugins PVC

Add to `layers/04-orchestration/templates/airflow.yaml` after the dags PVC:

```yaml
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ .Values.airflow.fullnameOverride }}-plugins
  namespace: {{ .Values.global.namespace }}
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: {{ .Values.global.storageClass }}
  resources:
    requests:
      storage: 1Gi
```

### Step 2: Mount in Webserver Deployment

Find the webserver deployment and update volumes:

```yaml
# In webserver deployment
volumeMounts:
- name: dags
  mountPath: /opt/airflow/dags
- name: plugins  # ADD THIS
  mountPath: /opt/airflow/plugins

volumes:
- name: dags
  persistentVolumeClaim:
    claimName: {{ .Values.airflow.fullnameOverride }}-dags
- name: plugins  # ADD THIS
  persistentVolumeClaim:
    claimName: {{ .Values.airflow.fullnameOverride }}-plugins
```

### Step 3: Mount in Scheduler Deployment

Repeat the same volume mounts for the scheduler deployment.

### Step 4: Deploy and Add Plugins

```bash
# Redeploy Airflow
helm upgrade openlakes-orchestration layers/04-orchestration --namespace openlakes

# Copy plugins to the volume
kubectl exec -it deployment/airflow-webserver -n openlakes -- mkdir -p /opt/airflow/plugins

# Example: Copy a custom operator
kubectl cp my_custom_operator.py openlakes/airflow-webserver-xxx:/opt/airflow/plugins/
```

---

## Method 2: Use ConfigMap for Small Plugins

### Step 1: Create Plugin ConfigMap

Add to `layers/04-orchestration/templates/airflow.yaml`:

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: airflow-plugins
  namespace: {{ .Values.global.namespace }}
data:
  my_custom_operator.py: |
    from airflow.models import BaseOperator
    from airflow.utils.decorators import apply_defaults

    class MyCustomOperator(BaseOperator):
        @apply_defaults
        def __init__(self, my_param, *args, **kwargs):
            super().__init__(*args, **kwargs)
            self.my_param = my_param

        def execute(self, context):
            self.log.info(f"Executing with param: {self.my_param}")
            # Your logic here
```

### Step 2: Mount ConfigMap

```yaml
# In webserver and scheduler deployments
volumeMounts:
- name: plugins-config
  mountPath: /opt/airflow/plugins/my_custom_operator.py
  subPath: my_custom_operator.py

volumes:
- name: plugins-config
  configMap:
    name: airflow-plugins
```

---

## Method 3: Build Custom Docker Image (Production Recommended)

### Step 1: Create Dockerfile

Create `layers/04-orchestration/Dockerfile`:

```dockerfile
FROM apache/airflow:3.1.2-python3.11

# Switch to root to install system packages
USER root

# Install any system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Switch back to airflow user
USER airflow

# Install Python packages and plugins
COPY requirements-plugins.txt /tmp/
RUN pip install --no-cache-dir -r /tmp/requirements-plugins.txt

# Copy custom plugins
COPY plugins/ /opt/airflow/plugins/

# Copy any additional configuration
COPY airflow.cfg /opt/airflow/
```

### Step 2: Create requirements-plugins.txt

```
# Apache Airflow Providers
apache-airflow-providers-postgres>=5.0.0
apache-airflow-providers-http>=4.0.0
apache-airflow-providers-slack>=8.0.0

# Custom packages
great-expectations>=0.18.0
dbt-core>=1.7.0
sqlalchemy>=2.0.0
```

### Step 3: Build and Push Image

```bash
cd layers/04-orchestration

# Build image
docker build -t your-registry/openlakes-airflow:3.1.2-custom .

# Push to registry
docker push your-registry/openlakes-airflow:3.1.2-custom
```

### Step 4: Update values.yaml

```yaml
airflow:
  image:
    repository: your-registry/openlakes-airflow
    tag: 3.1.2-custom
```

### Step 5: Redeploy

```bash
helm upgrade openlakes-orchestration layers/04-orchestration --namespace openlakes
```

---

## Common Plugins to Add

### 1. Great Expectations Data Quality

```python
# plugins/great_expectations_operator.py
from airflow.models import BaseOperator
import great_expectations as gx

class GreatExpectationsOperator(BaseOperator):
    def __init__(self, expectation_suite, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.expectation_suite = expectation_suite

    def execute(self, context):
        context_root = gx.get_context()
        # Run validations
        pass
```

### 2. Custom Slack Notifications

```python
# plugins/slack_webhook_operator.py
from airflow.providers.http.hooks.http import HttpHook
from airflow.models import BaseOperator

class SlackWebhookOperator(BaseOperator):
    def __init__(self, webhook_url, message, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.webhook_url = webhook_url
        self.message = message

    def execute(self, context):
        hook = HttpHook(method='POST', http_conn_id='slack_webhook')
        hook.run(endpoint='', json={"text": self.message})
```

### 3. OpenMetadata Integration

```python
# plugins/openmetadata_lineage.py
from airflow.models import BaseOperator
from metadata.ingestion.ometa.ometa_api import OpenMetadata

class OpenMetadataLineageOperator(BaseOperator):
    def execute(self, context):
        # Capture lineage from DAG execution
        pass
```

---

## Installing Apache Airflow Providers

Providers are the easiest way to add functionality:

```bash
# Option A: Install in running pod (temporary)
kubectl exec -it deployment/airflow-webserver -n openlakes -- \
  pip install apache-airflow-providers-amazon

# Option B: Add to custom image (permanent)
# In requirements-plugins.txt:
apache-airflow-providers-amazon[s3]>=8.0.0
apache-airflow-providers-google>=10.0.0
apache-airflow-providers-snowflake>=5.0.0
```

### Popular Providers

| Provider | Package | Use Case |
|----------|---------|----------|
| Amazon | `apache-airflow-providers-amazon` | S3, EMR, Redshift |
| Google | `apache-airflow-providers-google` | GCS, BigQuery, GKE |
| Postgres | `apache-airflow-providers-postgres` | PostgreSQL operations |
| HTTP | `apache-airflow-providers-http` | REST API calls |
| Slack | `apache-airflow-providers-slack` | Notifications |
| Snowflake | `apache-airflow-providers-snowflake` | Snowflake ops |
| dbt | `apache-airflow-providers-dbt-cloud` | dbt integration |

---

## Verification

After adding plugins:

```bash
# Check plugins are loaded
kubectl exec -it deployment/airflow-webserver -n openlakes -- \
  airflow plugins

# Check installed packages
kubectl exec -it deployment/airflow-webserver -n openlakes -- \
  pip list | grep airflow-providers

# Restart pods to load new plugins
kubectl rollout restart deployment/airflow-webserver -n openlakes
kubectl rollout restart deployment/airflow-scheduler -n openlakes
```

---

## Troubleshooting

### Plugin Not Found

```bash
# Check PYTHONPATH includes plugins
kubectl exec -it deployment/airflow-webserver -n openlakes -- \
  python -c "import sys; print('\n'.join(sys.path))"

# Verify plugin file exists
kubectl exec -it deployment/airflow-webserver -n openlakes -- \
  ls -la /opt/airflow/plugins/
```

### Import Errors

```bash
# Check airflow logs
kubectl logs deployment/airflow-scheduler -n openlakes | grep -i "import\|error"

# Test import manually
kubectl exec -it deployment/airflow-webserver -n openlakes -- \
  python -c "from plugins.my_custom_operator import MyCustomOperator"
```

---

## Recommended Approach

**For development**: Use Method 1 (Plugins Volume) for easy iteration

**For production**: Use Method 3 (Custom Image) for:
- Version control of plugins
- Reproducible builds
- CI/CD integration
- Faster pod startup
