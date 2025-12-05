# Layer 08 - Monitoring

Complete Kubernetes and OpenLakes monitoring solution with metrics, logs, alerts, and dashboards.

## Overview

This layer deploys a comprehensive monitoring stack for OpenLakes:

- **Prometheus** - Time-series metrics database with 15-day retention
- **Grafana** - Visualization and dashboarding platform
- **Loki** - Log aggregation system (Prometheus for logs)
- **Promtail** - Log shipping agent (DaemonSet on each node)
- **Alertmanager** - Alert routing and silencing
- **Exporters** - Metrics exporters for various components

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         Grafana                              │
│         (Dashboards & Visualization)                         │
│         http://grafana.openlakes.local                       │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ├─► Prometheus (Metrics)
                  │   - 50GB storage, 15d retention
                  │   - Scrapes all ServiceMonitors
                  │   - http://prometheus.openlakes.local
                  │
                  └─► Loki (Logs)
                      - 10GB storage, 7d retention
                      - Aggregates logs from Promtail
                      - Query logs in Grafana

┌─────────────────────────────────────────────────────────────┐
│                    Metrics Collection                        │
└─────────────────────────────────────────────────────────────┘
├─► Kubernetes Metrics (built-in)
│   ├─ Node Exporter (CPU, RAM, disk, network)
│   ├─ Kube State Metrics (pods, deployments, etc.)
│   ├─ cAdvisor (container metrics)
│   └─ Kubelet (node-level metrics)
│
├─► OpenLakes Components (ServiceMonitors)
│   ├─ MinIO (S3 storage metrics)
│   ├─ Spark (master/worker metrics)
│   ├─ Trino (query engine metrics)
│   ├─ Kafka (broker metrics via exporter)
│   ├─ PostgreSQL (database metrics via exporter)
│   ├─ Nessie (catalog API metrics)
│   ├─ Alluxio (cache metrics, if enabled)
│   ├─ Airflow (DAG/task metrics)
│   ├─ Superset (dashboard metrics)
│   ├─ OpenMetadata (catalog metrics)
│   └─ Traefik (ingress metrics)
│
└─► GPU Metrics (auto-detected)
    └─ NVIDIA DCGM Exporter (GPU utilization, memory, temp)
       - Deployed as DaemonSet on GPU nodes
       - Automatically enabled if GPUs detected

┌─────────────────────────────────────────────────────────────┐
│                      Log Collection                          │
└─────────────────────────────────────────────────────────────┘
└─► Promtail (DaemonSet)
    ├─ Scrapes logs from all pods
    ├─ Parses Docker JSON logs
    ├─ Supports multiline logs
    └─ Ships to Loki

┌─────────────────────────────────────────────────────────────┐
│                      Alerting                                │
└─────────────────────────────────────────────────────────────┘
└─► Alertmanager
    ├─ Routes alerts by severity (critical/warning/default)
    ├─ Configurable receivers (Slack, PagerDuty, webhooks)
    └─ http://alertmanager.openlakes.local
```

## Metrics Configuration Status

### ✅ Fully Configured (Metrics Available Now)

**Infrastructure Layer:**
- ✅ **MinIO**: Built-in Prometheus endpoint `/minio/v2/metrics/cluster`
- ✅ **Kafka**: Via `kafka-exporter` (broker, topic, consumer metrics)
- ✅ **PostgreSQL**: Via `postgres-exporter` (connections, transactions, performance)
- ✅ **Traefik**: Built-in metrics on `/metrics` endpoint
- ✅ **Nessie**: Quarkus metrics on `/q/metrics` (if enabled in Nessie config)

**Compute Layer:**
- ✅ **Spark**: Configured with `metrics.properties` → `/metrics/prometheus` on master (port 8080) and worker (port 8081)
- ✅ **Trino**: JMX exporter sidecar container → `/metrics` on port 9404

**Orchestration Layer:**
- ✅ **Airflow**: StatsD metrics → StatsD exporter → Prometheus `/metrics` on port 9102

**Infrastructure (Optional):**
- ✅ **Alluxio**: PrometheusMetricsServlet configured (if Alluxio is deployed)
- ✅ **NVIDIA GPUs**: DCGM Exporter auto-deployed if GPUs detected

**Kubernetes System:**
- ✅ **Node Exporter**: CPU, RAM, disk, network metrics
- ✅ **Kube State Metrics**: Pod, deployment, service metrics
- ✅ **cAdvisor**: Container resource usage
- ✅ **Kubelet**: Node-level metrics

### ⚠️ Requires Additional Configuration

**Analytics Layer:**
- ⚠️ **Superset**: No built-in Prometheus metrics
  - Requires custom metrics exporter or StatsD integration
  - Alternative: Monitor via PostgreSQL metrics (Superset metadata DB)

**Catalog Layer:**
- ⚠️ **OpenMetadata**: Metrics endpoint uncertain
  - Check if `/metrics` endpoint exists after deployment
  - May require OpenMetadata metrics plugin

**What This Means:**
- Services marked ✅ will show metrics in Grafana immediately after deployment
- Services marked ⚠️ will have empty dashboards until additional configuration is completed
- All Kubernetes and infrastructure metrics are fully functional out of the box

## Access

### Web UIs

**Grafana** (Primary Dashboard):
- URL: `http://grafana.openlakes.local`
- Username: `admin`
- Password: `admin123` (change in production!)

**Prometheus** (Raw Metrics):
- URL: `http://prometheus.openlakes.local`
- No authentication by default

**Alertmanager** (Alert Management):
- URL: `http://alertmanager.openlakes.local`
- No authentication by default

### Pre-configured Grafana Dashboards

Layer 08 includes five custom OpenLakes dashboards:

1. **OpenLakes - Cluster Overview**
   - Node count, pod count, CPU/memory usage
   - Network and disk I/O
   - Overall cluster health

2. **OpenLakes - Storage Performance**
   - MinIO: Throughput, request rate, storage capacity
   - PostgreSQL: Connections, transaction rate
   - Storage trends and capacity planning

3. **OpenLakes - Compute Performance**
   - Spark: Worker status, resource usage, application metrics
   - Trino: Active workers, query execution time
   - Resource allocation and utilization

4. **OpenLakes - Kafka Streaming**
   - Broker health and topic metrics
   - Message rates and throughput
   - Consumer lag monitoring
   - Under-replicated partitions

5. **OpenLakes - GPU Utilization** (if GPUs detected)
   - GPU utilization by device
   - Memory usage and temperature
   - Power consumption and clock speeds
   - Per-GPU and aggregate metrics

## Automatic Features

### GPU Detection

The deployment script automatically detects GPUs in your cluster:

```bash
# If GPUs detected:
✓ Detected 4 GPU(s) across 2 node(s)
ℹ Enabling GPU monitoring (NVIDIA DCGM Exporter)

# Deploys NVIDIA DCGM Exporter DaemonSet on GPU nodes
# Grafana GPU dashboard becomes populated with metrics
```

**Manual GPU monitoring** (if auto-detection fails):
```bash
# Enable GPU monitoring manually
helm upgrade --install monitoring ./layers/08-monitoring \
  --namespace openlakes \
  --set dcgmExporter.enabled=true
```

### Metrics-Server Verification

The deployment script ensures `metrics-server` is installed:

```bash
# If not installed:
⚠ metrics-server not found in cluster
ℹ Installing metrics-server (required for resource metrics)...
✓ metrics-server installed successfully

# Required for:
# - kubectl top nodes
# - kubectl top pods
# - Horizontal Pod Autoscaling (HPA)
# - Prometheus resource metrics
```

## Metrics Retention

| Component | Retention | Storage | Configurable |
|-----------|-----------|---------|-------------|
| Prometheus | 15 days | 50GB | `prometheus.prometheusSpec.retention` |
| Loki | 7 days | 10GB | `loki.loki.limits_config.retention_period` |
| Grafana Dashboards | Persistent | 5GB | `grafana.persistence.size` |

## ServiceMonitor Configuration

ServiceMonitors tell Prometheus where to scrape metrics. Layer 08 includes ServiceMonitors for all OpenLakes components:

| Component | Port | Path | Interval |
|-----------|------|------|----------|
| MinIO | 9000 | `/minio/v2/metrics/cluster` | 30s |
| Spark Master | webui (8080) | `/metrics/prometheus` | 30s |
| Spark Worker | webui (8081) | `/metrics/prometheus` | 30s |
| Trino | metrics (9404) | `/metrics` | 30s (via JMX exporter) |
| Nessie | http | `/q/metrics` | 30s |
| Alluxio Master | metrics | `/metrics/prometheus` | 30s (if enabled) |
| Alluxio Worker | metrics | `/metrics/prometheus` | 30s (if enabled) |
| Kafka | 9308 | `/metrics` | 30s (via kafka-exporter) |
| PostgreSQL | 9187 | `/metrics` | 30s (via postgres-exporter) |
| **Airflow** | **9102** | **`/metrics`** | **30s (via statsd-exporter)** |
| Traefik | traefik | `/metrics` | 30s |

All ServiceMonitors are labeled with `release: monitoring` for automatic discovery.

## Alert Configuration

### Alert Routing

Alerts are routed by severity:

```yaml
# Critical alerts (immediate action required)
severity: critical
  → receiver: openlakes-critical
  → repeat_interval: 5m

# Warning alerts (requires attention)
severity: warning
  → receiver: openlakes-warning
  → repeat_interval: 30m

# Default (informational)
  → receiver: openlakes-default
  → repeat_interval: 12h
```

### Configuring Alert Receivers

**Edit `values.yaml`** to add Slack, PagerDuty, or webhook receivers:

```yaml
alertmanager:
  config:
    receivers:
    - name: 'openlakes-critical'
      slack_configs:
      - api_url: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'
        channel: '#openlakes-critical'
        title: 'CRITICAL: {{ .GroupLabels.alertname }}'

      pagerduty_configs:
      - service_key: 'YOUR_PAGERDUTY_SERVICE_KEY'

    - name: 'openlakes-warning'
      slack_configs:
      - api_url: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'
        channel: '#openlakes-alerts'
```

## Common Queries

### PromQL Examples

```promql
# CPU usage by pod
100 * (1 - avg(rate(container_cpu_usage_seconds_total{namespace="openlakes"}[5m])) by (pod))

# Memory usage by pod
container_memory_usage_bytes{namespace="openlakes"}

# Kafka message rate
rate(kafka_server_broker_topic_metrics_messages_in_total[5m])

# Spark worker CPU utilization
100 * (1 - (spark_worker_cores_free / spark_worker_cores_total))

# MinIO request rate
rate(minio_s3_requests_total[5m])

# GPU utilization
DCGM_FI_DEV_GPU_UTIL
```

### LogQL Examples (Loki)

```logql
# All logs from openlakes namespace
{namespace="openlakes"}

# Errors in Spark
{namespace="openlakes", app="spark"} |= "ERROR"

# Airflow task failures
{namespace="openlakes", app="airflow"} |~ "Task.*failed"

# Kafka broker logs
{namespace="openlakes", app="kafka"} | json

# High severity logs
{namespace="openlakes"} | regexp `level=(?P<level>\w+)` | level = "ERROR" or level = "FATAL"
```

## Troubleshooting

### Prometheus Not Scraping Metrics

```bash
# Check if ServiceMonitor is created
kubectl get servicemonitor -n openlakes

# Check if Prometheus can reach the service
kubectl get svc -n openlakes

# Check Prometheus targets (should see all OpenLakes services)
# Visit: http://prometheus.openlakes.local/targets

# Check Prometheus service discovery
# Visit: http://prometheus.openlakes.local/service-discovery
```

### Grafana Dashboards Not Showing Data

```bash
# Verify Prometheus data source
# Grafana → Configuration → Data Sources → Prometheus
# Should point to: http://monitoring-kube-prometheus-prometheus:9090

# Check if metrics exist in Prometheus
# Visit: http://prometheus.openlakes.local/graph
# Run query: up{namespace="openlakes"}

# Verify dashboard time range matches data retention
# Prometheus retains 15 days by default
```

### Loki Logs Not Appearing

```bash
# Check if Promtail is running on all nodes
kubectl get daemonset -n openlakes monitoring-promtail

# Check Promtail logs
kubectl logs -n openlakes daemonset/monitoring-promtail

# Verify Loki data source in Grafana
# Grafana → Configuration → Data Sources → Loki
# Should point to: http://monitoring-loki:3100

# Test query in Grafana Explore
# {namespace="openlakes"}
```

### GPU Metrics Not Showing

```bash
# Check if GPUs are detected
kubectl get nodes -o json | grep nvidia.com/gpu

# Check if DCGM exporter is enabled
helm get values monitoring -n openlakes | grep dcgmExporter

# Check if DCGM pods are running
kubectl get pods -n openlakes -l app=dcgm-exporter

# Manually enable GPU monitoring if auto-detection failed
helm upgrade --install monitoring ./layers/08-monitoring \
  --namespace openlakes \
  --set dcgmExporter.enabled=true
```

### Alerts Not Firing

```bash
# Check Alertmanager configuration
kubectl get configmap -n openlakes monitoring-kube-prometheus-alertmanager -o yaml

# Check alert rules in Prometheus
# Visit: http://prometheus.openlakes.local/alerts

# Check Alertmanager status
# Visit: http://alertmanager.openlakes.local

# Test alert receiver (e.g., Slack webhook)
curl -X POST YOUR_SLACK_WEBHOOK_URL \
  -H 'Content-Type: application/json' \
  -d '{"text":"Test alert from OpenLakes"}'
```

## Resource Requirements

Default resource requests/limits:

| Component | CPU Request | Memory Request | CPU Limit | Memory Limit |
|-----------|-------------|----------------|-----------|--------------|
| Prometheus | 500m | 2Gi | 2000m | 4Gi |
| Grafana | 100m | 128Mi | 500m | 512Mi |
| Loki | 100m | 256Mi | 500m | 1Gi |
| Promtail | 50m | 64Mi | 200m | 256Mi |
| Kafka Exporter | 50m | 64Mi | 200m | 128Mi |
| Postgres Exporter | 50m | 64Mi | 200m | 128Mi |
| DCGM Exporter | 50m | 64Mi | 200m | 128Mi |
| Alertmanager | 10m | 32Mi | 100m | 128Mi |

**Total minimum resources**: ~1.5 CPU cores, ~4GB RAM
**With GPU monitoring**: Add ~0.05 CPU, ~64MB RAM per GPU node

## Customization

### Change Data Retention

**Prometheus** (edit `values.yaml`):
```yaml
prometheus:
  prometheusSpec:
    retention: 30d        # Keep metrics for 30 days
    retentionSize: "90GB" # Use up to 90GB storage
    storageSpec:
      volumeClaimTemplate:
        spec:
          resources:
            requests:
              storage: 100Gi  # Total storage allocation
```

**Loki** (edit `values.yaml`):
```yaml
loki:
  loki:
    limits_config:
      retention_period: 336h  # 14 days (in hours)
  singleBinary:
    persistence:
      size: 20Gi  # Total storage allocation
```

### Add Custom Dashboards

1. Export dashboard JSON from Grafana UI
2. Add to `templates/grafana-dashboards.yaml`:

```yaml
data:
  my-custom-dashboard.json: |
    {
      "dashboard": {
        "title": "My Custom Dashboard",
        ...
      }
    }
```

3. Redeploy: `./deploy-openlakes.sh`

### Add ServiceMonitor for Custom Service

Create `templates/custom-servicemonitor.yaml`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-custom-service
  namespace: openlakes
  labels:
    release: monitoring  # REQUIRED for Prometheus discovery
spec:
  selector:
    matchLabels:
      app: my-app
  endpoints:
  - port: metrics
    path: /metrics
    interval: 30s
```

## Security Considerations

### Production Recommendations

1. **Change default passwords**:
```yaml
# values.yaml
grafana:
  adminPassword: "CHANGE_ME_IN_PRODUCTION"
```

2. **Enable authentication for Prometheus/Alertmanager**:
```yaml
# Use OAuth proxy or basic auth
# See: https://prometheus.io/docs/guides/basic-auth/
```

3. **Enable TLS for Grafana**:
```yaml
grafana:
  ingress:
    enabled: true
    tls:
    - secretName: grafana-tls
      hosts:
      - grafana.openlakes.local
```

4. **Restrict network access**:
```yaml
# NetworkPolicy to limit access
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: monitoring-access
spec:
  podSelector:
    matchLabels:
      app: grafana
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: openlakes
```

## References

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Loki Documentation](https://grafana.com/docs/loki/latest/)
- [kube-prometheus-stack Chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [NVIDIA DCGM Exporter](https://docs.nvidia.com/datacenter/cloud-native/gpu-telemetry/dcgm-exporter.html)
- [metrics-server](https://github.com/kubernetes-sigs/metrics-server)

## Support

For issues or questions:
- GitHub Issues: https://github.com/openlakes/openlakes-core/issues
- Documentation: https://github.com/openlakes/openlakes-core/tree/main/docs
