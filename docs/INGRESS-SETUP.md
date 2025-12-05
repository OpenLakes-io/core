# OpenLakes Ingress Setup Guide

OpenLakes uses **Traefik** as the ingress controller to provide host-based routing for all services. This allows you to access all components via clean, memorable URLs like `http://superset.openlakes.local` instead of NodePort addresses like `http://localhost:30088`.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    User Browser / Client                        │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     │ http://superset.openlakes.local
                     │ http://metadata.openlakes.local
                     │ http://spark.openlakes.local
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│            Traefik Ingress Controller (Port 80)                 │
│                                                                  │
│  - Host-based routing (*.openlakes.local)                       │
│  - Single entry point for all services                          │
│  - Dynamic service discovery                                    │
└────────┬─────────┬──────────┬──────────┬──────────┬────────────┘
         │         │          │          │          │
         ▼         ▼          ▼          ▼          ▼
    ┌────────┬────────┬────────┬────────┬────────────┐
    │ MinIO  │Superset│Airflow │  Spark │OpenMetadata│
    │        │        │        │        │            │
    │ :9001  │ :8088  │ :8080  │ :8080  │   :8585    │
    └────────┴────────┴────────┴────────┴────────────┘
```

---

## Service Access URLs

All services are accessible via `*.openlakes.local` domain:

### Infrastructure Layer
- **MinIO Console**: http://minio.openlakes.local
- **Nessie REST API**: http://nessie.openlakes.local
- **Apicurio Schema Registry**: http://schema-registry.openlakes.local
- **Traefik Dashboard**: http://traefik.openlakes.local/dashboard/

### Compute Layer
- **Trino**: http://trino.openlakes.local
- **Spark Master**: http://spark.openlakes.local
- **Spark Worker**: http://spark-worker.openlakes.local
- **Spark History**: http://spark-history.openlakes.local
- **StarRocks** (if enabled): http://starrocks.openlakes.local

### Orchestration Layer
- **Airflow**: http://airflow.openlakes.local

### Analytics Layer
- **Superset**: http://superset.openlakes.local
- **JupyterHub**: http://jupyter.openlakes.local

### Ingestion Layer
- **Debezium**: http://debezium.openlakes.local

> Meltano now runs as a headless runtime pod and is orchestrated through Airflow/Dagster instead of exposing its own UI.

### Catalog Layer
- **OpenMetadata**: http://metadata.openlakes.local
- **OpenMetadata Ingestion**: http://ingestion.openlakes.local

### Monitoring Layer
- **Grafana** (Dashboards): http://grafana.openlakes.local
- **Prometheus** (Metrics): http://prometheus.openlakes.local
- **Alertmanager** (Alerts): http://alertmanager.openlakes.local

---

## Local DNS Configuration

To access services via `*.openlakes.local` domains, you need to configure local DNS resolution.

### Option 1: /etc/hosts (Simple, Manual)

**Pros**: Simple, no additional software
**Cons**: Must add each domain manually, requires sudo

**Setup**:

1. Edit your hosts file:
   ```bash
   sudo nano /etc/hosts
   ```

2. Add all OpenLakes domains:
   ```
   # OpenLakes Services
   127.0.0.1 minio.openlakes.local
   127.0.0.1 nessie.openlakes.local
   127.0.0.1 schema-registry.openlakes.local
   127.0.0.1 traefik.openlakes.local
   127.0.0.1 trino.openlakes.local
   127.0.0.1 spark.openlakes.local
   127.0.0.1 spark-worker.openlakes.local
   127.0.0.1 spark-history.openlakes.local
   127.0.0.1 starrocks.openlakes.local
   127.0.0.1 airflow.openlakes.local
   127.0.0.1 superset.openlakes.local
   127.0.0.1 jupyter.openlakes.local
   127.0.0.1 debezium.openlakes.local
   127.0.0.1 metadata.openlakes.local
   127.0.0.1 ingestion.openlakes.local
   127.0.0.1 grafana.openlakes.local
   127.0.0.1 prometheus.openlakes.local
   127.0.0.1 alertmanager.openlakes.local
   ```

3. Save and test:
   ```bash
   ping minio.openlakes.local
   # Should respond from 127.0.0.1
   ```

---

### Option 2: dnsmasq (Advanced, Wildcard Support)

**Pros**: Automatic wildcard resolution (`*.openlakes.local`), no manual entries
**Cons**: Requires additional software, slightly more complex

#### macOS (Homebrew)

1. Install dnsmasq:
   ```bash
   brew install dnsmasq
   ```

2. Configure dnsmasq to resolve `*.openlakes.local` to localhost:
   ```bash
   echo 'address=/.openlakes.local/127.0.0.1' >> $(brew --prefix)/etc/dnsmasq.conf
   ```

3. Start dnsmasq:
   ```bash
   sudo brew services start dnsmasq
   ```

4. Configure macOS to use dnsmasq for `.local` domains:
   ```bash
   sudo mkdir -p /etc/resolver
   echo "nameserver 127.0.0.1" | sudo tee /etc/resolver/openlakes.local
   ```

5. Test:
   ```bash
   ping minio.openlakes.local
   # Should respond from 127.0.0.1
   ```

#### Linux (Ubuntu/Debian)

1. Install dnsmasq:
   ```bash
   sudo apt-get update
   sudo apt-get install dnsmasq
   ```

2. Configure dnsmasq:
   ```bash
   echo 'address=/.openlakes.local/127.0.0.1' | sudo tee -a /etc/dnsmasq.conf
   ```

3. Restart dnsmasq:
   ```bash
   sudo systemctl restart dnsmasq
   ```

4. Configure NetworkManager to use dnsmasq:
   ```bash
   echo '[main]
   dns=dnsmasq' | sudo tee /etc/NetworkManager/NetworkManager.conf
   sudo systemctl restart NetworkManager
   ```

5. Test:
   ```bash
   ping superset.openlakes.local
   # Should respond from 127.0.0.1
   ```

---

## Traefik Access

Traefik is exposed on **port 30080** (HTTP) and provides the dashboard for monitoring routing rules.

### Access Traefik

- **Entry Point**: http://localhost:30080 (or use port 80 if you configure port forwarding)
- **Dashboard**: http://traefik.openlakes.local/dashboard/

### Traefik Dashboard Features

- **HTTP Routers**: View all IngressRoute rules and host mappings
- **Services**: View all backend services and health status
- **Middleware**: View applied middleware (authentication, rate limiting, etc.)
- **Metrics**: Real-time request metrics and latency

---

## Port Forwarding (Optional)

If you want to access Traefik on port 80 (standard HTTP) instead of 30080:

### macOS/Linux

```bash
# Forward port 80 → 30080
sudo socat TCP-LISTEN:80,fork TCP:localhost:30080
```

Or use `iptables` (Linux):

```bash
sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 30080
```

---

## Troubleshooting

### DNS Not Resolving

**Symptom**: `curl minio.openlakes.local` returns "Could not resolve host"

**Solutions**:

1. **Check /etc/hosts**:
   ```bash
   cat /etc/hosts | grep openlakes
   ```

2. **Test DNS resolution**:
   ```bash
   nslookup minio.openlakes.local
   # Should return 127.0.0.1
   ```

3. **Flush DNS cache** (macOS):
   ```bash
   sudo dscacheutil -flushcache
   sudo killall -HUP mDNSResponder
   ```

4. **Flush DNS cache** (Linux):
   ```bash
   sudo systemd-resolve --flush-caches
   ```

---

### Traefik Not Routing

**Symptom**: DNS resolves but service returns "404 Page Not Found"

**Solutions**:

1. **Check Traefik is running**:
   ```bash
   kubectl get pods -n openlakes | grep traefik
   # Should show: infrastructure-traefik-... Running
   ```

2. **Check IngressRoute resources**:
   ```bash
   kubectl get ingressroute -n openlakes
   # Should show all service IngressRoutes
   ```

3. **Check Traefik logs**:
   ```bash
   kubectl logs -n openlakes -l app.kubernetes.io/name=traefik -f
   ```

4. **Verify service exists**:
   ```bash
   kubectl get svc -n openlakes | grep <service-name>
   ```

---

### Service Not Accessible

**Symptom**: DNS resolves, Traefik routes, but service returns "503 Service Unavailable"

**Solutions**:

1. **Check service pods are running**:
   ```bash
   kubectl get pods -n openlakes
   # Look for the specific service pods
   ```

2. **Check service health**:
   ```bash
   kubectl describe svc <service-name> -n openlakes
   # Look for Endpoints
   ```

3. **Check pod logs**:
   ```bash
   kubectl logs -n openlakes <pod-name> -f
   ```

---

## Migration from NodePort

If you previously used NodePort-based access (e.g., `http://localhost:30088` for Superset), the new ingress setup provides these benefits:

### Before (NodePort)
```
http://localhost:30088  → Superset
http://localhost:30082  → Airflow
http://localhost:30585  → OpenMetadata
http://localhost:30077  → Spark Master
...15+ different ports to remember
```

### After (Ingress)
```
http://superset.openlakes.local  → Superset
http://airflow.openlakes.local   → Airflow
http://metadata.openlakes.local  → OpenMetadata
http://spark.openlakes.local     → Spark Master
...clean, memorable URLs
```

### Advantages

1. **Memorable URLs**: `superset.openlakes.local` instead of `localhost:30088`
2. **Single Entry Point**: Port 80 (or 30080) for all services
3. **Production-Ready**: Same routing mechanism used in production
4. **Standard HTTP Port**: Can use port 80 with port forwarding
5. **Easier Sharing**: Share URLs with team members
6. **Browser Compatibility**: No CORS issues with different ports

---

## Custom Domain (Advanced)

If you want to use a different domain (e.g., `*.openlakes.dev`):

1. **Update global networking domain** in all layers' `values.yaml`:
   ```yaml
   global:
     networking:
       domain: openlakes.dev  # Changed from openlakes.local
   ```

2. **Update DNS configuration**:
   - For `/etc/hosts`: Replace `.openlakes.local` with `.openlakes.dev`
   - For `dnsmasq`: Update the `address=` line

3. **Redeploy OpenLakes**:
   ```bash
   ./deploy-openlakes.sh
   ```

---

## Next Steps

1. **Configure DNS** using Option 1 (hosts file) or Option 2 (dnsmasq)
2. **Deploy OpenLakes**:
   ```bash
   ./deploy-openlakes.sh
   ```
3. **Access services** via `*.openlakes.local` URLs
4. **Monitor routing** via Traefik dashboard at http://traefik.openlakes.local/dashboard/

For deployment issues, see [Troubleshooting](#troubleshooting).
