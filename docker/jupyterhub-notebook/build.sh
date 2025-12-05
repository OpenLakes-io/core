#!/bin/bash
set -e

# OpenLakes JupyterHub Notebook Image Build Script
# Supports four environments: local, dev, staging, production

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source version from root
if [ -f "$PROJECT_ROOT/VERSION" ]; then
    DEFAULT_VERSION=$(cat "$PROJECT_ROOT/VERSION")
else
    DEFAULT_VERSION="1.0.0"
fi

# Build environment (local, dev, staging, production)
BUILD_ENV="${BUILD_ENV:-local}"
VERSION="${VERSION:-$DEFAULT_VERSION}"
BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
VCS_REF=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

# Image name
IMAGE_NAME="jupyterhub-notebook"
REGISTRY="ghcr.io/openlakes/core"

# Platform detection
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then
    PLATFORM="linux/arm64"
else
    PLATFORM="linux/amd64"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "OpenLakes JupyterHub Notebook Image Builder"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Environment:  $BUILD_ENV"
echo "Version:      $VERSION"
echo "Platform:     $PLATFORM"
echo "VCS Ref:      $VCS_REF"
echo "Build Date:   $BUILD_DATE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Environment-specific tagging
case "$BUILD_ENV" in
    local)
        # Local: single tag, no push
        IMAGE_TAG="$IMAGE_NAME:local"
        echo "Building LOCAL image: $IMAGE_TAG"
        docker build \
            --platform "$PLATFORM" \
            --build-arg VERSION="$VERSION" \
            --build-arg BUILD_DATE="$BUILD_DATE" \
            --build-arg VCS_REF="$VCS_REF" \
            -t "$IMAGE_TAG" \
            -f "$SCRIPT_DIR/Dockerfile" \
            "$SCRIPT_DIR"
        echo "✓ Local build complete: $IMAGE_TAG"
        echo "  Use: imagePullPolicy: Never in values-local.yaml"
        ;;

    dev)
        # Dev: push to GHCR with dev tag
        IMAGE_TAG="$REGISTRY/$IMAGE_NAME:dev"
        echo "Building DEV image: $IMAGE_TAG"
        docker build \
            --platform "$PLATFORM" \
            --build-arg VERSION="$VERSION-dev" \
            --build-arg BUILD_DATE="$BUILD_DATE" \
            --build-arg VCS_REF="$VCS_REF" \
            -t "$IMAGE_TAG" \
            -f "$SCRIPT_DIR/Dockerfile" \
            "$SCRIPT_DIR"

        echo ""
        echo "Push to GHCR? This will make the image available to the team."
        read -p "Push $IMAGE_TAG? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            docker push "$IMAGE_TAG"
            echo "✓ Dev image pushed: $IMAGE_TAG"
        else
            echo "⏭  Push skipped"
        fi
        ;;

    staging)
        # Staging: push with staging tag and version-staging
        IMAGE_TAG_1="$REGISTRY/$IMAGE_NAME:staging"
        IMAGE_TAG_2="$REGISTRY/$IMAGE_NAME:$VERSION-staging"
        echo "Building STAGING image: $IMAGE_TAG_1, $IMAGE_TAG_2"
        docker build \
            --platform "$PLATFORM" \
            --build-arg VERSION="$VERSION-staging" \
            --build-arg BUILD_DATE="$BUILD_DATE" \
            --build-arg VCS_REF="$VCS_REF" \
            -t "$IMAGE_TAG_1" \
            -t "$IMAGE_TAG_2" \
            -f "$SCRIPT_DIR/Dockerfile" \
            "$SCRIPT_DIR"

        echo ""
        echo "Push to GHCR? This will make the staging image available for QA."
        read -p "Push staging tags? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            docker push "$IMAGE_TAG_1"
            docker push "$IMAGE_TAG_2"
            echo "✓ Staging images pushed"
        else
            echo "⏭  Push skipped"
        fi
        ;;

    production)
        # Production: multi-tag (version, major.minor, major, latest)
        MAJOR=$(echo "$VERSION" | cut -d. -f1)
        MINOR=$(echo "$VERSION" | cut -d. -f1-2)

        IMAGE_TAG_VERSION="$REGISTRY/$IMAGE_NAME:$VERSION"
        IMAGE_TAG_MINOR="$REGISTRY/$IMAGE_NAME:$MINOR"
        IMAGE_TAG_MAJOR="$REGISTRY/$IMAGE_NAME:$MAJOR"
        IMAGE_TAG_LATEST="$REGISTRY/$IMAGE_NAME:latest"

        echo "Building PRODUCTION image with tags:"
        echo "  - $IMAGE_TAG_VERSION"
        echo "  - $IMAGE_TAG_MINOR"
        echo "  - $IMAGE_TAG_MAJOR"
        echo "  - $IMAGE_TAG_LATEST"

        docker build \
            --platform "$PLATFORM" \
            --build-arg VERSION="$VERSION" \
            --build-arg BUILD_DATE="$BUILD_DATE" \
            --build-arg VCS_REF="$VCS_REF" \
            -t "$IMAGE_TAG_VERSION" \
            -t "$IMAGE_TAG_MINOR" \
            -t "$IMAGE_TAG_MAJOR" \
            -t "$IMAGE_TAG_LATEST" \
            -f "$SCRIPT_DIR/Dockerfile" \
            "$SCRIPT_DIR"

        echo ""
        echo "⚠️  PRODUCTION BUILD - Push to GHCR?"
        read -p "Push all production tags? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            docker push "$IMAGE_TAG_VERSION"
            docker push "$IMAGE_TAG_MINOR"
            docker push "$IMAGE_TAG_MAJOR"
            docker push "$IMAGE_TAG_LATEST"
            echo "✓ Production images pushed"
        else
            echo "⏭  Push skipped"
        fi
        ;;

    *)
        echo "❌ Unknown BUILD_ENV: $BUILD_ENV"
        echo "Valid options: local, dev, staging, production"
        exit 1
        ;;
esac

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ Build complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
