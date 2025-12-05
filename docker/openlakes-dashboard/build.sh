#!/usr/bin/env bash
# Build script for OpenLakes Dashboard Docker image
#
# Supports four build environments:
#   local      - Build only, no push (default)
#   dev        - Push to GHCR with 'dev' tag
#   staging    - Push to GHCR with 'staging' and '{version}-staging' tags
#   production - Push to GHCR with version tags (automated via CI)

set -euo pipefail

# Configuration
IMAGE_NAME="openlakes-dashboard"
REGISTRY="ghcr.io/openlakes/core"
BUILD_ENV="${BUILD_ENV:-local}"
VERSION="${VERSION:-1.0.0}"

# Get git info for labels
VCS_REF=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "========================================"
echo "Building OpenLakes Dashboard"
echo "========================================"
echo "Environment: $BUILD_ENV"
echo "Version:     $VERSION"
echo "VCS Ref:     $VCS_REF"
echo "Build Date:  $BUILD_DATE"
echo "========================================"

case "$BUILD_ENV" in
  local)
    echo "Building local image: ${IMAGE_NAME}:local"
    docker build \
      --build-arg VERSION="$VERSION" \
      --build-arg BUILD_DATE="$BUILD_DATE" \
      --build-arg VCS_REF="$VCS_REF" \
      --platform linux/amd64 \
      -t "${IMAGE_NAME}:local" \
      .

    echo "✅ Local build complete: ${IMAGE_NAME}:local"
    echo "   Use with: imagePullPolicy: Never"
    ;;

  dev)
    echo "Building dev image for GHCR"

    # Build for amd64 (cluster architecture)
    docker buildx build \
      --platform linux/amd64 \
      --build-arg VERSION="$VERSION" \
      --build-arg BUILD_DATE="$BUILD_DATE" \
      --build-arg VCS_REF="$VCS_REF" \
      -t "${REGISTRY}/${IMAGE_NAME}:dev" \
      --load \
      .

    # Prompt before pushing
    read -p "Push ${REGISTRY}/${IMAGE_NAME}:dev to GHCR? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      echo "Pushing to GHCR..."
      docker push "${REGISTRY}/${IMAGE_NAME}:dev"
      echo "✅ Dev build pushed: ${REGISTRY}/${IMAGE_NAME}:dev"
    else
      echo "❌ Push cancelled"
      exit 1
    fi
    ;;

  staging)
    if [ -z "$VERSION" ]; then
      echo "❌ Error: VERSION must be set for staging builds"
      echo "   Usage: BUILD_ENV=staging VERSION=1.0.0 ./build.sh"
      exit 1
    fi

    echo "Building staging image for GHCR"

    # Build and tag with both staging and version-staging
    docker buildx build \
      --platform linux/amd64 \
      --build-arg VERSION="$VERSION" \
      --build-arg BUILD_DATE="$BUILD_DATE" \
      --build-arg VCS_REF="$VCS_REF" \
      -t "${REGISTRY}/${IMAGE_NAME}:staging" \
      -t "${REGISTRY}/${IMAGE_NAME}:${VERSION}-staging" \
      --load \
      .

    # Prompt before pushing
    read -p "Push staging images to GHCR? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      echo "Pushing to GHCR..."
      docker push "${REGISTRY}/${IMAGE_NAME}:staging"
      docker push "${REGISTRY}/${IMAGE_NAME}:${VERSION}-staging"
      echo "✅ Staging build pushed:"
      echo "   - ${REGISTRY}/${IMAGE_NAME}:staging"
      echo "   - ${REGISTRY}/${IMAGE_NAME}:${VERSION}-staging"
    else
      echo "❌ Push cancelled"
      exit 1
    fi
    ;;

  production)
    if [ -z "$VERSION" ]; then
      echo "❌ Error: VERSION must be set for production builds"
      echo "   Usage: BUILD_ENV=production VERSION=1.0.0 ./build.sh"
      exit 1
    fi

    # Validate semantic version format
    if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "❌ Error: VERSION must be semantic (X.Y.Z)"
      exit 1
    fi

    echo "Building production image for GHCR"
    echo "⚠️  Production builds should be automated via GitHub Actions"
    echo "   Only use this for emergency hotfixes"

    # Parse version
    MAJOR=$(echo "$VERSION" | cut -d. -f1)
    MINOR=$(echo "$VERSION" | cut -d. -f2)

    # Build and tag with all version variants
    docker buildx build \
      --platform linux/amd64 \
      --build-arg VERSION="$VERSION" \
      --build-arg BUILD_DATE="$BUILD_DATE" \
      --build-arg VCS_REF="$VCS_REF" \
      -t "${REGISTRY}/${IMAGE_NAME}:${VERSION}" \
      -t "${REGISTRY}/${IMAGE_NAME}:${MAJOR}.${MINOR}" \
      -t "${REGISTRY}/${IMAGE_NAME}:${MAJOR}" \
      -t "${REGISTRY}/${IMAGE_NAME}:latest" \
      --load \
      .

    # Prompt before pushing
    read -p "Push production images to GHCR? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      echo "Pushing to GHCR..."
      docker push "${REGISTRY}/${IMAGE_NAME}:${VERSION}"
      docker push "${REGISTRY}/${IMAGE_NAME}:${MAJOR}.${MINOR}"
      docker push "${REGISTRY}/${IMAGE_NAME}:${MAJOR}"
      docker push "${REGISTRY}/${IMAGE_NAME}:latest"
      echo "✅ Production build pushed:"
      echo "   - ${REGISTRY}/${IMAGE_NAME}:${VERSION}"
      echo "   - ${REGISTRY}/${IMAGE_NAME}:${MAJOR}.${MINOR}"
      echo "   - ${REGISTRY}/${IMAGE_NAME}:${MAJOR}"
      echo "   - ${REGISTRY}/${IMAGE_NAME}:latest"
    else
      echo "❌ Push cancelled"
      exit 1
    fi
    ;;

  *)
    echo "❌ Error: Invalid BUILD_ENV: $BUILD_ENV"
    echo "   Valid values: local, dev, staging, production"
    exit 1
    ;;
esac

echo ""
echo "Build complete!"
