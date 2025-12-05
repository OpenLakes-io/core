# OpenLakes Spark with OpenMetadata Agent

Custom Spark Docker image with OpenMetadata lineage agent pre-installed.

## Image Details

- **Base Image:** apache/spark:4.1.0-preview3
- **Registry:** ghcr.io/openlakes/openlakes-core
- **Image Name:** spark-openmetadata
- **Version:** 1.0.0
- **Includes:** openmetadata-spark-agent-1.0-beta.jar (from Maven Central)

## Building the Image

```bash
cd layers/02-compute/docker
chmod +x build-and-push.sh
./build-and-push.sh
```

## Manual Build

```bash
docker build \
  -f Dockerfile.spark-openmetadata \
  -t ghcr.io/openlakes/openlakes-core/spark-openmetadata:1.0.0 \
  .
```

## Pushing to Registry

### Prerequisites

1. GitHub Personal Access Token with `write:packages` scope
2. Docker login to GitHub Container Registry:

```bash
echo $GITHUB_TOKEN | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
```

### Push

```bash
docker push ghcr.io/openlakes/openlakes-core/spark-openmetadata:1.0.0
docker push ghcr.io/openlakes/openlakes-core/spark-openmetadata:latest
```

## Verification

### Verify JAR is present

```bash
docker run --rm ghcr.io/openlakes/openlakes-core/spark-openmetadata:1.0.0 \
  ls -lh /opt/spark/jars/openmetadata-spark-agent-1.0-beta.jar
```

Expected output:
```
-rw-r--r-- 1 root root [SIZE] [DATE] /opt/spark/jars/openmetadata-spark-agent-1.0-beta.jar
```

### Test image runs

```bash
docker run --rm ghcr.io/openlakes/openlakes-core/spark-openmetadata:1.0.0 \
  /opt/spark/bin/spark-submit --version
```

## Updating the Agent

When a new version of openmetadata-spark-agent is released:

1. Update the download URL in `Dockerfile.spark-openmetadata`
2. Update the version tag (e.g., 1.0.1, 1.1.0)
3. Rebuild and push the image
4. Update `layers/02-compute/values.yaml` with new image tag
5. Deploy updated Helm chart

## Image Registry Access

Images are stored in GitHub Container Registry (ghcr.io) under the OpenLakes organization:

- **Public Access:** Images can be pulled without authentication (if repository is public)
- **Private Access:** Requires GitHub PAT for authentication
- **Organization:** openlakes
- **Repository:** openlakes-core

## Troubleshooting

### Build fails: "JAR not found"

- Check internet connectivity during build
- Verify OpenMetadata agent release URL is correct
- Check GitHub rate limiting

### Cannot push to registry

- Verify GitHub token has `write:packages` scope
- Ensure you're logged in: `docker login ghcr.io`
- Check organization permissions

### Image too large

Expected image size: ~1.5-2GB (Spark base + agent JAR)

- Base Spark image: ~1.4GB
- OpenMetadata agent JAR: ~10-50MB
