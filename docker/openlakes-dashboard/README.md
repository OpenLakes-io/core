# OpenLakes Dashboard

Material UI dashboard for OpenLakes Core that provides quick access to all service UIs.

## What's Included

A modern, responsive dashboard featuring:
- **Material UI design** with dark theme
- **Service cards** organized by category (Infrastructure, Compute, Orchestration, Analytics, Ingestion, Catalog)
- **Direct links** to all OpenLakes service UIs
- **Service status** and descriptions
- **Responsive grid layout** for desktop and mobile

## Services

### Infrastructure
- MinIO Object Storage (S3-compatible storage)
- Alluxio Web UI (distributed cache)
- Nessie Catalog (git-like data catalog)
- Kafka UI (stream processing)

### Compute
- Spark Master UI (distributed processing)
- Trino Web UI (SQL query engine)

### Orchestration
- Airflow (workflow scheduling)

### Analytics
- Superset (data visualization)
- JupyterHub (notebook server)

### Ingestion
- Meltano (Singer data integration)

### Catalog
- OpenMetadata (data catalog & lineage)

## Registry

```
ghcr.io/openlakes/core/openlakes-dashboard
```

## Tags

- `1.0.0`, `1.0`, `1`, `latest` - Production release
- `staging`, `1.0.0-staging` - Release candidate
- `dev` - Development (team collaboration)
- `local` - Local builds (not pushed to registry)

## Building

### Local Development (Fastest)
```bash
./build.sh
# Creates: openlakes-dashboard:local
# Use with: imagePullPolicy: Never
```

### Collaborative Development
```bash
BUILD_ENV=dev ./build.sh
# Creates and pushes: ghcr.io/openlakes/core/openlakes-dashboard:dev
```

### Staging (Release Candidate)
```bash
BUILD_ENV=staging VERSION=1.0.0 ./build.sh
# Creates and pushes:
#   - ghcr.io/openlakes/core/openlakes-dashboard:staging
#   - ghcr.io/openlakes/core/openlakes-dashboard:1.0.0-staging
```

### Production (Automated via CI)
```bash
BUILD_ENV=production VERSION=1.0.0 ./build.sh
# Creates and pushes:
#   - ghcr.io/openlakes/core/openlakes-dashboard:1.0.0
#   - ghcr.io/openlakes/core/openlakes-dashboard:1.0
#   - ghcr.io/openlakes/core/openlakes-dashboard:1
#   - ghcr.io/openlakes/core/openlakes-dashboard:latest
```

## Usage in Layer 01 (Infrastructure)

### Production (values.yaml)
```yaml
dashboard:
  enabled: true
  image:
    repository: ghcr.io/openlakes/core/openlakes-dashboard
    tag: "1.0.0"
    pullPolicy: IfNotPresent
  service:
    type: LoadBalancer
    port: 80
```

### Local Development (values-local.yaml)
```yaml
dashboard:
  image:
    repository: openlakes-dashboard
    tag: "local"
    pullPolicy: Never
```

### Dev Environment (values-dev.yaml)
```yaml
dashboard:
  image:
    repository: ghcr.io/openlakes/core/openlakes-dashboard
    tag: "dev"
    pullPolicy: Always
```

## Accessing the Dashboard

After deployment, access the dashboard at:
```
http://localhost:3000
```

Or find the LoadBalancer IP:
```bash
kubectl get svc infrastructure-dashboard -n openlakes
```

## Architecture

**Multi-stage Docker build**:
1. **Build stage**: Node.js 18 Alpine compiles React app
2. **Production stage**: Nginx Alpine serves static files

**Benefits**:
- Small final image size (~25MB)
- Fast loading with nginx
- Gzip compression enabled
- Security headers configured
- Health check endpoint at `/health`

## Customization

To add or modify services, edit `src/App.js`:

```javascript
const services = [
  {
    name: 'Your Service',
    description: 'Service description',
    url: 'http://localhost:PORT',
    icon: <YourIcon fontSize="large" />,
    category: 'Category',
    color: '#HEX_COLOR',
  },
  // ...
];
```

Then rebuild the image.

## Development

Run locally without Docker:

```bash
cd docker/openlakes-dashboard
npm install
npm start
# Open http://localhost:3000
```

## Testing

Test the Docker image:

```bash
# Build local image
./build.sh

# Run container
docker run --rm -p 3000:80 openlakes-dashboard:local

# Open http://localhost:3000
```

## Versioning

This dashboard follows OpenLakes semantic versioning:

- **PATCH** (1.0.0 → 1.0.1): Bug fixes, minor UI tweaks
- **MINOR** (1.0.0 → 1.1.0): Add new services, UI improvements
- **MAJOR** (1.0.0 → 2.0.0): Breaking changes, major redesign
