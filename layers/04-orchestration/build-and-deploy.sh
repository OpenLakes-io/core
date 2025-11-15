#!/bin/bash
set -e

# Configuration
IMAGE_NAME="openlakes-airflow"
IMAGE_TAG="3.1.2-openmetadata-1.6.1"
REGISTRY="${DOCKER_REGISTRY:-ghcr.io/openlakes-io/openlakes-core}"  # Use GHCR by default
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "==========================================="
echo "Building OpenLakes Airflow with OpenMetadata"
echo "==========================================="
echo "Image: ${FULL_IMAGE}"
echo ""

# Step 1: Build the Docker image
echo "Step 1: Building Docker image..."
docker build \
  -t ${IMAGE_NAME}:${IMAGE_TAG} \
  -t ${IMAGE_NAME}:1.0.0 \
  -t ${FULL_IMAGE} \
  -t ${REGISTRY}/${IMAGE_NAME}:1.0.0 \
  .

if [ $? -eq 0 ]; then
  echo "✅ Docker image built successfully"
else
  echo "❌ Docker build failed"
  exit 1
fi
echo ""

# Step 2: Push to registry (optional, skip for local testing)
if [ "$SKIP_PUSH" != "true" ]; then
  echo "Step 2: Pushing image to registry..."
  docker push ${FULL_IMAGE}

  if [ $? -eq 0 ]; then
    echo "✅ Image pushed successfully"
  else
    echo "❌ Push failed"
    exit 1
  fi
else
  echo "Step 2: Skipping push (SKIP_PUSH=true)"
fi
echo ""

# Step 3: Update values.yaml
echo "Step 3: Updating values.yaml..."
cat > values-custom-image.yaml <<EOF
airflow:
  image:
    repository: ${REGISTRY}/${IMAGE_NAME}
    tag: ${IMAGE_TAG}
    pullPolicy: IfNotPresent
EOF

echo "✅ Created values-custom-image.yaml"
echo ""

# Step 4: Deploy to Kubernetes
echo "Step 4: Deploying to Kubernetes..."
read -p "Deploy to Kubernetes now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  helm upgrade openlakes-orchestration . \
    --namespace openlakes \
    --install \
    --values values.yaml \
    --values values-custom-image.yaml

  echo ""
  echo "✅ Deployment complete!"
  echo ""
  echo "Verify installation:"
  echo "  kubectl get pods -n openlakes | grep airflow"
  echo "  kubectl logs deployment/airflow-webserver -n openlakes | grep openmetadata"
  echo ""
  echo "Test OpenMetadata package:"
  echo "  kubectl exec -it deployment/airflow-webserver -n openlakes -- python -c 'import openmetadata_ingestion; print(openmetadata_ingestion.__version__)'"
else
  echo ""
  echo "Deployment skipped. To deploy manually, run:"
  echo "  helm upgrade openlakes-orchestration . --namespace openlakes --install --values values.yaml --values values-custom-image.yaml"
fi
