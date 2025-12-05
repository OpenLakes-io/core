#!/usr/bin/env bash
set -euo pipefail

# ════════════════════════════════════════════════════════════════
# OpenLakes Spark OpenMetadata Image Build Script
# ════════════════════════════════════════════════════════════════
#
# Supports four build environments:
#   - local:      Fast local development (Rancher Desktop)
#   - dev:        Collaborative development (push to GHCR)
#   - staging:    QA/regression testing (push to GHCR)
#   - production: Stable releases (automated via GitHub Actions)
#
# Usage:
#   ./build.sh                          # Local build (default)
#   BUILD_ENV=dev ./build.sh            # Dev environment
#   BUILD_ENV=staging ./build.sh        # Staging environment
#   BUILD_ENV=production VERSION=1.0.1 ./build.sh  # Production
#
# Environment Variables:
#   BUILD_ENV    Build environment (local|dev|staging|production)
#   VERSION      Semantic version (required for staging/production)
#   PUSH         Auto-push to registry (true|false, default: prompt)
#   REGISTRY     Image registry (default: ghcr.io/openlakes/openlakes-core)
#
# ════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="spark"
REGISTRY="${REGISTRY:-ghcr.io/openlakes/core}"
BUILD_ENV="${BUILD_ENV:-local}"
VERSION="${VERSION:-dev}"
PUSH="${PUSH:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${BLUE}ℹ${NC} $*"
}

log_success() {
  echo -e "${GREEN}✓${NC} $*"
}

log_warning() {
  echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
  echo -e "${RED}✗${NC} $*"
}

# Validate semantic version format
validate_version() {
  local ver=$1
  if [[ ! "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log_error "Invalid version format: $ver"
    log_error "Version must follow semantic versioning (X.Y.Z)"
    log_error "Example: 1.0.0, 1.2.3, 2.0.0"
    return 1
  fi
  return 0
}

# Get build metadata
get_build_date() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

get_vcs_ref() {
  git rev-parse --short HEAD 2>/dev/null || echo "unknown"
}

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║     OpenLakes Spark OpenMetadata - Image Build            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

case $BUILD_ENV in
  # ──────────────────────────────────────────────────────────────
  # LOCAL: Fast iteration with Rancher Desktop
  # ──────────────────────────────────────────────────────────────
  local)
    TAG="${IMAGE_NAME}:local"

    log_info "Environment:  LOCAL (Rancher Desktop)"
    log_info "Image tag:    $TAG"
    log_info "Purpose:      Rapid local development"
    echo ""

    log_info "Building local image..."
    docker build \
      --build-arg VERSION="${VERSION}" \
      --build-arg BUILD_DATE="$(get_build_date)" \
      --build-arg VCS_REF="$(get_vcs_ref)" \
      -t "$TAG" \
      -f Dockerfile \
      "$SCRIPT_DIR"

    log_success "Local image built: $TAG"
    echo ""
    log_info "Next steps:"
    log_info "  1. Deploy: cd ../.. && ./deploy-openlakes.sh --env local"
    log_info "  2. Or use: helm upgrade ... -f values-local.yaml"
    ;;

  # ──────────────────────────────────────────────────────────────
  # DEV: Collaborative development environment
  # ──────────────────────────────────────────────────────────────
  dev)
    DEV_TAG="${REGISTRY}/${IMAGE_NAME}:dev"
    USER_TAG="${REGISTRY}/${IMAGE_NAME}:dev-${USER}"

    log_info "Environment:  DEV (Collaborative)"
    log_info "Image tags:   $DEV_TAG"
    log_info "              $USER_TAG"
    log_info "Purpose:      Share work-in-progress with team"
    echo ""

    log_info "Building dev image..."
    docker build \
      --build-arg VERSION="dev" \
      --build-arg BUILD_DATE="$(get_build_date)" \
      --build-arg VCS_REF="$(get_vcs_ref)" \
      -t "$DEV_TAG" \
      -t "$USER_TAG" \
      -f Dockerfile \
      "$SCRIPT_DIR"

    log_success "Dev image built"
    echo ""

    # Prompt for push unless PUSH is set
    if [ -z "$PUSH" ]; then
      read -p "Push to registry? [y/N] " -n 1 -r
      echo
      PUSH=$([[ $REPLY =~ ^[Yy]$ ]] && echo "true" || echo "false")
    fi

    if [ "$PUSH" = "true" ]; then
      log_info "Pushing to GitHub Container Registry..."
      docker push "$DEV_TAG"
      docker push "$USER_TAG"
      log_success "Pushed: $DEV_TAG"
      log_success "Pushed: $USER_TAG"
      echo ""
      log_info "Next steps:"
      log_info "  1. Deploy: ./deploy-openlakes.sh --env dev"
      log_info "  2. Test changes on any cluster with dev environment"
    else
      log_info "Skipped push. Image available locally only."
    fi
    ;;

  # ──────────────────────────────────────────────────────────────
  # STAGING: QA and regression testing
  # ──────────────────────────────────────────────────────────────
  staging)
    if ! validate_version "$VERSION"; then
      exit 1
    fi

    STAGING_TAG="${REGISTRY}/${IMAGE_NAME}:staging"
    VERSION_STAGING_TAG="${REGISTRY}/${IMAGE_NAME}:${VERSION}-staging"

    log_info "Environment:  STAGING (QA/Testing)"
    log_info "Version:      $VERSION"
    log_info "Image tags:   $STAGING_TAG"
    log_info "              $VERSION_STAGING_TAG"
    log_info "Purpose:      Full regression testing before production"
    echo ""

    log_warning "Building staging release candidate..."
    docker build \
      --build-arg VERSION="${VERSION}-staging" \
      --build-arg BUILD_DATE="$(get_build_date)" \
      --build-arg VCS_REF="$(get_vcs_ref)" \
      -t "$STAGING_TAG" \
      -t "$VERSION_STAGING_TAG" \
      -f Dockerfile \
      "$SCRIPT_DIR"

    log_success "Staging image built"
    echo ""

    # Prompt for push unless PUSH is set
    if [ -z "$PUSH" ]; then
      read -p "Push to registry for QA testing? [y/N] " -n 1 -r
      echo
      PUSH=$([[ $REPLY =~ ^[Yy]$ ]] && echo "true" || echo "false")
    fi

    if [ "$PUSH" = "true" ]; then
      log_info "Pushing to GitHub Container Registry..."
      docker push "$STAGING_TAG"
      docker push "$VERSION_STAGING_TAG"
      log_success "Pushed: $STAGING_TAG"
      log_success "Pushed: $VERSION_STAGING_TAG"
      echo ""
      log_info "Next steps:"
      log_info "  1. Deploy to staging: ./deploy-openlakes.sh --env staging"
      log_info "  2. Run full regression test suite"
      log_info "  3. Gather customer feedback"
      log_info "  4. If approved, promote to production:"
      log_info "     git tag -a v${VERSION} -m 'Release ${VERSION}'"
      log_info "     git push origin v${VERSION}"
    else
      log_info "Skipped push. Image available locally only."
    fi
    ;;

  # ──────────────────────────────────────────────────────────────
  # PRODUCTION: Stable releases (normally automated via GitHub Actions)
  # ──────────────────────────────────────────────────────────────
  production)
    if ! validate_version "$VERSION"; then
      exit 1
    fi

    FULL_TAG="${REGISTRY}/${IMAGE_NAME}:${VERSION}"
    MINOR_TAG="${REGISTRY}/${IMAGE_NAME}:${VERSION%.*}"
    MAJOR_TAG="${REGISTRY}/${IMAGE_NAME}:${VERSION%%.*}"
    LATEST_TAG="${REGISTRY}/${IMAGE_NAME}:latest"

    log_warning "Environment:  PRODUCTION (Stable Release)"
    log_warning "Version:      $VERSION"
    log_warning "Image tags:   $FULL_TAG"
    log_warning "              $MINOR_TAG"
    log_warning "              $MAJOR_TAG"
    log_warning "              $LATEST_TAG"
    echo ""
    log_warning "⚠️  Production builds should normally be automated via GitHub Actions"
    log_warning "⚠️  Use this only for emergency manual releases"
    echo ""

    read -p "Continue with manual production build? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      log_info "Build cancelled"
      exit 0
    fi

    log_info "Building production image..."
    docker build \
      --build-arg VERSION="${VERSION}" \
      --build-arg BUILD_DATE="$(get_build_date)" \
      --build-arg VCS_REF="$(get_vcs_ref)" \
      -t "$FULL_TAG" \
      -t "$MINOR_TAG" \
      -t "$MAJOR_TAG" \
      -t "$LATEST_TAG" \
      -f Dockerfile \
      "$SCRIPT_DIR"

    log_success "Production image built"
    echo ""

    # Prompt for push unless PUSH is set
    if [ -z "$PUSH" ]; then
      read -p "Push to registry? [y/N] " -n 1 -r
      echo
      PUSH=$([[ $REPLY =~ ^[Yy]$ ]] && echo "true" || echo "false")
    fi

    if [ "$PUSH" = "true" ]; then
      log_info "Pushing to GitHub Container Registry..."
      docker push "$FULL_TAG"
      docker push "$MINOR_TAG"
      docker push "$MAJOR_TAG"
      docker push "$LATEST_TAG"
      log_success "Pushed all tags for version $VERSION"
      echo ""
      log_info "Next steps:"
      log_info "  1. Create GitHub release: gh release create v${VERSION}"
      log_info "  2. Update Chart.yaml versions to match"
      log_info "  3. Deploy to production: ./deploy-openlakes.sh --env production"
    else
      log_info "Skipped push. Image available locally only."
    fi
    ;;

  *)
    log_error "Invalid BUILD_ENV: $BUILD_ENV"
    log_error "Valid values: local, dev, staging, production"
    exit 1
    ;;
esac

echo ""
log_success "Build completed successfully!"
echo ""
