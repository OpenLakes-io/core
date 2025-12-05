#!/usr/bin/env bash

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0

#
# OpenLakes Deployment Script
#
# Features:
# - Idempotent: Can be run multiple times safely
# - Cross-platform: Works on Linux and macOS
# - Validates prerequisites
# - Waits for critical services to be ready
# - Provides detailed progress reporting
# - Integrated multi-node storage configuration wizard
#

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CORE_VERSION="$(cat "${REPO_ROOT}/VERSION" 2>/dev/null || echo "1.0.0")"

# ═══════════════════════════════════════════════════════════════
# Bash Version Check
# ═══════════════════════════════════════════════════════════════

# Check if Bash 4.0+ is available (required for associative arrays in storage wizard)
# Only enforce this if --configure-storage flag is used
check_bash_version() {
  if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    echo ""
    echo -e "${RED}✗ Error: Storage configuration requires Bash 4.0 or later${NC}"
    echo ""
    echo "Current version: $BASH_VERSION"
    echo "Detected on: $(uname -s)"
    echo ""
    echo "Associative arrays (used for node tracking) were introduced in Bash 4.0."
    echo ""

    # Platform-specific installation instructions
    case "$(uname -s)" in
      Darwin*)
        echo "macOS ships with Bash 3.2 for licensing reasons."
        echo ""
        echo "To install Bash 4+ via Homebrew:"
        echo "  1. brew install bash"
        echo "  2. Re-run this script with: /usr/local/bin/bash $0"
        echo ""
        ;;
      Linux*)
        echo "On Linux, update bash:"
        echo "  Ubuntu/Debian: sudo apt-get update && sudo apt-get install bash"
        echo "  RHEL/CentOS:   sudo yum update bash"
        ;;
    esac

    echo ""
    exit 1
  fi
}

# Color output (works on both Linux and macOS)
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  NC='\033[0m' # No Color
else
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  NC=''
fi

# Configuration
NAMESPACE="${NAMESPACE:-openlakes}"
TIMEOUT="${TIMEOUT:-5m}"
DRY_RUN="${DRY_RUN:-false}"
DEPLOY_ENV="${DEPLOY_ENV:-production}"  # local|dev|staging|production
STORAGE_CONFIG=""  # Optional path to storage configuration file
CONFIGURE_STORAGE=false  # Disable interactive storage wizard by default; core-config drives storage
SINGLE_NODE_STORAGE_CLASS="${SINGLE_NODE_STORAGE_CLASS:-local-path}"
KUBE_CONTEXT=""         # Optional kubectl context override
CLUSTER_MODE=""         # single|multi (set at runtime)
NODE_COUNT=0
SKIP_THROUGHPUT_CHECK="${SKIP_THROUGHPUT_CHECK:-false}"
CORE_CONFIG="${CORE_CONFIG:-core-config.yaml}"
LOCAL_EXAMPLES_DIR="${REPO_ROOT}/examples"
LOCAL_EXAMPLES_AVAILABLE="false"
TRAEFIK_ENABLED="true"
TRAEFIK_USE_EXISTING="false"
TRAEFIK_NAMESPACE=""
KUBE_API_IPV4=""
KUBE_API_PORT="443"

# Parsed config defaults
CFG_STORAGE_CLASS=""
CFG_SINGLE_NODE_SC=""
CFG_DOMAIN=""
CFG_INGRESS_CLASS=""
CFG_ENABLE_INGRESS_ROUTES=""
CFG_NODEPORT_FALLBACK=""
CFG_MINIO_ROOT_USER=""
CFG_MINIO_ROOT_PASSWORD=""
CFG_SCHEMA_REGISTRY="true"
CFG_ALLUXIO="false"
TRAEFIK_ENABLED="true"
TRAEFIK_USE_EXISTING="false"
TRAEFIK_NAMESPACE=""
CFG_HELM_TIMEOUT=""
CFG_LOKI_MAX_STREAMS=""
CFG_LOKI_MAX_QUERY_SERIES=""
CFG_LOKI_MAX_QUERY_PARALLELISM=""
CFG_LOKI_RETENTION_PERIOD=""
CFG_PROMTAIL_INOTIFY_INSTANCES=""
CFG_PROMTAIL_INOTIFY_WATCHES=""
CFG_MINIO_PRECREATE_BUCKETS="true"
CFG_MINIO_BUCKET_MAIN="openlakes"
CFG_MINIO_BUCKET_SPARK_PREFIX="spark-history/"
CFG_PROBE_PROFILE="slow"
CFG_LOKI_STORAGE_CLASS=""
CFG_GRAFANA_STORAGE_CLASS=""
CFG_PROMETHEUS_STORAGE_CLASS=""
CFG_POPULATE_EXAMPLES=""
CFG_ANALYTICS_EXAMPLES_ENABLED=""
CFG_ANALYTICS_TOKEN_SECRET=""
CFG_MELTANO_S3_BUCKET=""
CFG_MELTANO_S3_PREFIX="meltano/"
CFG_AIRFLOW_EXTRA_PIP=""
CFG_RESOURCE_PROFILE_OVERRIDE=""
ANALYTICS_EXAMPLES_ENABLED="true"
ANALYTICS_EXAMPLES_TOKEN_SECRET=""
CFG_AIRFLOW_USER=""
CFG_AIRFLOW_PASSWORD=""
CFG_SUPERSET_USER=""
CFG_SUPERSET_PASSWORD=""
CFG_GRAFANA_PASSWORD=""
CFG_OPENMETADATA_USER=""
CFG_OPENMETADATA_PASSWORD=""
CFG_INGRESS_ENABLED=""
CFG_DASHBOARD_PROTOCOL=""
CFG_DASHBOARD_PORT=""
CFG_DASHBOARD_SHOW_CREDS="true"
CFG_DASHBOARD_VERSION=""
DASHBOARD_SERVICES_B64=""
CFG_NOTEBOOK_BUCKET=""
CFG_NOTEBOOK_PREFIX_SHARED="shared"
CFG_NOTEBOOK_PREFIX_WORKSPACE="workspace"
CFG_NOTEBOOK_PREFIX_PUBLISHED="published"
CFG_NOTEBOOK_PREFIX_ARTIFACTS="artifacts"
CFG_NOTEBOOK_SYNC_DOWNLOAD="*/2 * * * *"
CFG_NOTEBOOK_SYNC_UPLOAD="*/5 * * * *"
CFG_NOTEBOOK_SYNC_AIRFLOW="*/3 * * * *"
CFG_NOTEBOOK_VERSIONING="true"
DYNAMIC_AIRFLOW_PASSWORD=""
DASHBOARD_RUNTIME_REFRESHED="false"
INFRA_WAIT_TARGETS="statefulset:infrastructure-postgres,statefulset:infrastructure-kafka,statefulset:infrastructure-minio"

# Capacity detection / resource profile
TOTAL_CPU_MILLICORES=0
TOTAL_MEM_MIB=0
NODE_CPU_MILLICORES=0
NODE_MEM_MIB=0
RESOURCE_PROFILE="full" # compact|small|full|compact-vm
CONTROL_CPU_RESERVE_MILLICORES=0
CONTROL_MEM_RESERVE_MIB=0
DATA_CPU_AVAILABLE_MILLICORES=0
DATA_MEM_AVAILABLE_MIB=0
GPU_MONITORING_ENABLED="false"

CFG_RESOURCE_PROFILE_OVERRIDE=""

# Tier entries (populated from core-config.yaml via yq)
declare -a TIER_HOT=()
declare -a TIER_COLD=()
declare -a TIER_CACHE=()
declare -a TIER_LONGHORN=()

# Load tier entries from core-config.yaml
load_tier_entries() {
  local tier="$1"
  local -n arr_ref=$2
  arr_ref=()
  if ! command_exists yq || [ ! -f "${CORE_CONFIG}" ]; then
    return 0
  fi
  while IFS= read -r line; do
    [ -n "$line" ] && arr_ref+=("$line")
  done < <(yq eval ".storage.tiers.${tier}[] | .node + \":\" + (.paths[])" "${CORE_CONFIG}" 2>/dev/null || true)
}

# Clean up any node-debugger pods left from kubectl debug invocations
cleanup_node_debugger_pods() {
  if ! command_exists kubectl; then
    return
  fi
  kubectl get pods -A --no-headers 2>/dev/null | awk '$2 ~ /^node-debugger/ {print $1" "$2}' | \
    while read ns name; do
      kubectl delete pod "$name" -n "$ns" --ignore-not-found >/dev/null 2>&1 || true
    done
}

# Validate that all paths in a tier are within 5% of each other
validate_tier_sizes() {
  local tier="$1"
  local -n entries_ref=$2
  # Skip host-level size validation in this mode to avoid node-debugger pods/errors.
  if [ ${#entries_ref[@]} -gt 0 ]; then
    log_warning "Skipping host path size validation for tier '${tier}' (host exec disabled)"
  fi
  if [ ${#entries_ref[@]} -le 1 ]; then
    return 0
  fi

  return 0
}

# Create static PVs for MinIO hot tier based on configured hostPath mounts.
# We intentionally leave storageClassName empty so the StatefulSet PVCs bind to these PVs.
create_minio_pvs_from_tiers() {
  if [ ${#TIER_HOT[@]} -eq 0 ]; then
    log_warning "No hot tier entries defined; skipping MinIO PV creation"
    return 0
  fi

  local manifest
  manifest=$(mktemp /tmp/minio-pv-XXXXXX)
  local idx=0

  log_info "Creating MinIO PVs from tiered hostPath configuration..."
  for entry in "${TIER_HOT[@]}"; do
    local node="${entry%%:*}"
    local path="${entry#*:}"

    # Derive size fallback; skip host probing to avoid node-debugger pods
    local size_gib=100

    cat >> "${manifest}" <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: minio-hot-pv-${idx}
  labels:
    app: minio
    tier: hot
spec:
  capacity:
    storage: ${size_gib}Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
  hostPath:
    path: ${path}
    type: DirectoryOrCreate
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - ${node}
---
EOF
    idx=$((idx+1))
  done

  kubectl apply -f "${manifest}" >/dev/null 2>&1 || {
    log_error "Failed to apply MinIO PVs from ${manifest}"
    return 1
  }
  log_success "Applied ${idx} MinIO hot-tier PVs from ${manifest}"
}

# Create static PVs/PVCs for MinIO hot tier using hostPath mounts
prepare_minio_pvs() {
  log_info "Preparing MinIO PersistentVolumes (hot tier)..."
  if [ ${#TIER_HOT[@]} -eq 0 ]; then
    log_warning "No hot tier entries defined; skipping MinIO PV prep"
    return 0
  fi

  local idx=0
  local created=false
  for entry in "${TIER_HOT[@]}"; do
    local node="${entry%%:*}"
    local path="${entry#*:}"

    # Determine size in GiB (floor); fallback to 100Gi
    local size_gib=100

    cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: v1
kind: PersistentVolume
metadata:
  name: minio-hot-pv-${idx}
  labels:
    app: minio
spec:
  capacity:
    storage: ${size_gib}Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
  hostPath:
    path: ${path}
    type: DirectoryOrCreate
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - ${node}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-infrastructure-minio-${idx}
  namespace: ${NAMESPACE}
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: ${size_gib}Gi
  storageClassName: ""
  volumeName: minio-hot-pv-${idx}
EOF
    idx=$((idx+1))
    created=true
  done

  if [ "${created}" = true ]; then
    log_success "MinIO hot-tier PVs/PVCs applied (${idx} volumes)"
  fi
}

# Tier entries pulled from core-config.yaml
declare -a TIER_HOT=()
declare -a TIER_COLD=()
declare -a TIER_CACHE=()
declare -a TIER_LONGHORN=()

# Tier validation helpers
get_tier_entries() {
  local tier="$1"
  if ! command_exists yq || [ ! -f "${CORE_CONFIG}" ]; then
    return 0
  fi
  yq eval ".storage.tiers.${tier}[] | .node + \":\" + (.paths[])" "${CORE_CONFIG}" 2>/dev/null || true
}

validate_tier_sizes() {
  local tier="$1"
  local entries
  entries=$(get_tier_entries "${tier}")
  if [ -z "${entries}" ]; then
    return 0
  fi

  log_warning "Skipping host path size validation for tier '${tier}' (host exec disabled)"
  return 0
}

CFG_RESOURCE_PROFILE_OVERRIDE=""

# Detect OS
OS="$(uname -s)"
case "${OS}" in
  Linux*)     PLATFORM=linux;;
  Darwin*)    PLATFORM=mac;;
  *)          PLATFORM="unknown";;
esac

# ═══════════════════════════════════════════════════════════════
# Storage Wizard Global Variables (requires Bash 4.0+)
# ═══════════════════════════════════════════════════════════════

# Declare associative arrays globally (only if Bash 4.0+)
if [ "${BASH_VERSINFO[0]}" -ge 4 ]; then
  # Node-level tracking
  declare -A NODE_NAMES=()
  declare -A NODE_ARCH=()
  declare -A NODE_STORAGE_BYTES=()
  declare -A NODE_STORAGE_GB=()

  # Drive-level tracking (key format: "node_idx:drive_name")
  declare -A DRIVE_TOTAL_GB=()      # Total capacity per drive
  declare -A DRIVE_ALLOCATED_GB=()  # Allocated capacity per drive (cumulative across components)

  # Drive inventory per node (format: "node_idx:drive_name:size_gb")
  declare -a ALL_DRIVES=()

  # Component-specific drive allocations
  # Longhorn: Array of "node_idx:drive_name:allocated_gb"
  declare -a LONGHORN_DRIVES=()

  # Alluxio: Array of "node_idx:drive_name:cache_gb"
  declare -a ALLUXIO_DRIVES=()

  # MinIO: Array of "node_idx:drive_name:size_gb"
  declare -a MINIO_DRIVES=()
fi

# Helper functions
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

# Convert timeout strings (e.g., 5m/300s) to seconds
parse_timeout_to_seconds() {
  local t="$1"
  if [[ "$t" =~ ^([0-9]+)m$ ]]; then
    echo $((BASH_REMATCH[1] * 60))
  elif [[ "$t" =~ ^([0-9]+)s$ ]]; then
    echo "${BASH_REMATCH[1]}"
  elif [[ "$t" =~ ^[0-9]+$ ]]; then
    echo "$t"
  else
    # Fallback to default 5 minutes if format unknown
    echo 300
  fi
}

# Enforce a maximum timeout of 5 minutes to fail fast on hung installs
enforce_timeout_cap() {
  local max_seconds=300
  local current_seconds
  current_seconds=$(parse_timeout_to_seconds "${TIMEOUT}")
  if [ "${current_seconds}" -gt "${max_seconds}" ]; then
    log_warning "Timeout '${TIMEOUT}' exceeds 5 minutes; capping to 5m"
    TIMEOUT="5m"
  fi
}

# Check if command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Detect CNI plugin in use (best-effort)
detect_cni() {
  local ds_names
  ds_names=$(kubectl get daemonset -n kube-system -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)

  if echo "$ds_names" | grep -qi "cilium"; then
    echo "cilium"
  elif echo "$ds_names" | grep -qi "calico"; then
    echo "calico"
  elif echo "$ds_names" | grep -qi "canal"; then
    echo "canal"
  elif echo "$ds_names" | grep -qi "flannel"; then
    echo "flannel"
  else
    echo "unknown"
  fi
}

# Detect cluster node count and derive mode
detect_cluster_mode() {
  NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo "0")
  if [ -z "$NODE_COUNT" ]; then
    NODE_COUNT=0
  fi

  if [ "$NODE_COUNT" -lt 2 ]; then
    CLUSTER_MODE="single"
  else
    CLUSTER_MODE="multi"
  fi
}

# Detect total/avg allocatable CPU+memory for profiling
detect_cluster_capacity() {
  if ! command_exists kubectl || ! command_exists python3; then
    log_warning "kubectl/python3 not available; skipping capacity detection"
    return
  fi

  local json
  json=$(kubectl get nodes -o json 2>/dev/null || echo "")
  if [ -z "${json}" ]; then
    log_warning "Unable to read node capacity; skipping"
    return
  fi

  read -r TOTAL_CPU_MILLICORES TOTAL_MEM_MIB <<EOF
$(python3 - <<'PY' "${json}"
import json,sys,re
data=json.loads(sys.argv[1])
cpu_total=0
mem_total=0
def cpu_to_m(cpu):
    if cpu.endswith("m"):
        return int(cpu[:-1])
    return int(float(cpu)*1000)
def mem_to_mib(mem):
    # handle Ki, Mi, Gi
    m=re.match(r"(\d+)([KMG]i)?", mem)
    if not m:
        return 0
    val=int(m.group(1))
    unit=m.group(2)
    if unit=="Ki":
        return val//1024
    if unit=="Gi":
        return val*1024
    if unit=="Mi" or unit is None:
        return val
    return 0
for item in data.get("items", []):
    alloc=item.get("status",{}).get("allocatable",{})
    cpu_total+=cpu_to_m(alloc.get("cpu","0"))
    mem_total+=mem_to_mib(alloc.get("memory","0"))
print(cpu_total, mem_total)
PY
)
EOF

  if [ "$NODE_COUNT" -gt 0 ]; then
    NODE_CPU_MILLICORES=$((TOTAL_CPU_MILLICORES / NODE_COUNT))
    NODE_MEM_MIB=$((TOTAL_MEM_MIB / NODE_COUNT))
  fi

  log_info "Cluster allocatable: CPU=${TOTAL_CPU_MILLICORES}m, Mem=${TOTAL_MEM_MIB}Mi across ${NODE_COUNT} node(s)"
}

# Choose resource profile based on cluster size
set_resource_profile() {
  # Ensure node count populated
  detect_cluster_mode
  detect_cluster_capacity

  # If capacity detection succeeded but node count is zero, derive from totals
  if [ "${NODE_COUNT}" -le 0 ] && [ "${TOTAL_CPU_MILLICORES}" -gt 0 ]; then
    NODE_COUNT=1
  fi

  # VM-aware adjustment: if running on mac (Virtualization.framework) and single node → compact-vm
  local vm_hint="false"
  if [ "${PLATFORM}" = "mac" ] && [ "${NODE_COUNT}" -le 1 ]; then
    vm_hint="true"
  fi

  # Defaults
  RESOURCE_PROFILE="small"

  # Profile logic:
  # - compact-vm: mac single-node (emulation/virtualization)
  # - compact: single-node non-VM
  # - small: single-node <=10 cores or <=18Gi
  # - full: multi-node with >24 cores AND >128Gi total
  local total_cpu_cores=$((TOTAL_CPU_MILLICORES / 1000))
  local total_mem_gib=$((TOTAL_MEM_MIB / 1024))
  local per_cpu_cores=$((NODE_CPU_MILLICORES / 1000))
  local per_mem_gib=$((NODE_MEM_MIB / 1024))

  if [ -n "${CFG_RESOURCE_PROFILE_OVERRIDE}" ] && [ "${CFG_RESOURCE_PROFILE_OVERRIDE}" != "null" ]; then
    RESOURCE_PROFILE="${CFG_RESOURCE_PROFILE_OVERRIDE}"
  elif [ "${vm_hint}" = "true" ]; then
    RESOURCE_PROFILE="compact-vm"
  elif [ "${NODE_COUNT}" -le 1 ]; then
    if [ "${per_cpu_cores}" -le 10 ] || [ "${per_mem_gib}" -le 18 ]; then
      RESOURCE_PROFILE="small"
    else
      RESOURCE_PROFILE="full"
    fi
  else
    if [ "${total_cpu_cores}" -gt 24 ] && [ "${total_mem_gib}" -gt 128 ]; then
      RESOURCE_PROFILE="full"
    else
      RESOURCE_PROFILE="small"
    fi
  fi

  case "${RESOURCE_PROFILE}" in
    compact-vm)
      CONTROL_CPU_RESERVE_MILLICORES=4500
      CONTROL_MEM_RESERVE_MIB=$((10 * 1024))
      ;;
    small)
      CONTROL_CPU_RESERVE_MILLICORES=7000
      CONTROL_MEM_RESERVE_MIB=$((14 * 1024))
      ;;
    full|*)
      CONTROL_CPU_RESERVE_MILLICORES=12000
      CONTROL_MEM_RESERVE_MIB=$((24 * 1024))
      ;;
  esac

  DATA_CPU_AVAILABLE_MILLICORES=$((TOTAL_CPU_MILLICORES - CONTROL_CPU_RESERVE_MILLICORES))
  DATA_MEM_AVAILABLE_MIB=$((TOTAL_MEM_MIB - CONTROL_MEM_RESERVE_MIB))
  if [ "${DATA_CPU_AVAILABLE_MILLICORES}" -lt 0 ]; then DATA_CPU_AVAILABLE_MILLICORES=0; fi
  if [ "${DATA_MEM_AVAILABLE_MIB}" -lt 0 ]; then DATA_MEM_AVAILABLE_MIB=0; fi

  log_info "Resource profile: ${RESOURCE_PROFILE}"
  log_info "Control plane reservation (estimated): ${CONTROL_CPU_RESERVE_MILLICORES}m CPU, $((CONTROL_MEM_RESERVE_MIB/1024))Gi memory"
  log_info "Approx available for user data workloads: ${DATA_CPU_AVAILABLE_MILLICORES}m CPU, $((DATA_MEM_AVAILABLE_MIB/1024))Gi memory"
}

# Enforce hard minimum resources (total allocatable) before deploying (VM contexts only)
enforce_minimum_resources() {
  local min_cpu_cores=10
  local min_mem_gib=18
  local total_cpu_cores=$((TOTAL_CPU_MILLICORES / 1000))
  local total_mem_gib=$((TOTAL_MEM_MIB / 1024))

  # Only enforce on VM/virtualization hints (mac single-node)
  local vm_hint="false"
  if [ "${PLATFORM}" = "mac" ] && [ "${NODE_COUNT}" -le 1 ]; then
    vm_hint="true"
  fi
  if [ "${vm_hint}" != "true" ]; then
    return
  fi

  if [ "${total_cpu_cores}" -lt "${min_cpu_cores}" ] || [ "${total_mem_gib}" -lt "${min_mem_gib}" ]; then
    log_error "Cluster allocatable resources too low for OpenLakes in VM context: CPU=${total_cpu_cores} cores, Mem=${total_mem_gib}Gi (min ${min_cpu_cores} cores, ${min_mem_gib}Gi)"
    exit 1
  fi
}

# Detect if a Traefik controller already exists in the cluster.
# If found, skip deploying the bundled Traefik chart but still allow ingress routes to be created.
detect_existing_traefik() {
  if ! command_exists kubectl; then
    return
  fi

  # If a non-default ingressClass is requested, deploy bundled Traefik regardless
  if [ -n "${CFG_INGRESS_CLASS}" ] && [ "${CFG_INGRESS_CLASS}" != "traefik" ]; then
    TRAEFIK_ENABLED="true"
    TRAEFIK_USE_EXISTING="false"
    return
  fi

  local found_ns=""

  # Check for a Helm release named 'traefik'
  local helm_line
  helm_line=$(helm list -A 2>/dev/null | awk '$1=="traefik"{print $2}')
  if [ -n "$helm_line" ]; then
    found_ns="$helm_line"
  else
    # Fallback: look for any Traefik deployment/daemonset
    local ns
    ns=$(kubectl get deploy,daemonset -A -o jsonpath='{range .items[*]}{@.metadata.namespace}{"|"}{@.metadata.name}{"\n"}{end}' 2>/dev/null | grep -i 'traefik' | head -n1 | cut -d'|' -f1)
    if [ -n "$ns" ]; then
      found_ns="$ns"
    fi
  fi

  if [ -n "$found_ns" ]; then
    TRAEFIK_ENABLED="false"
    TRAEFIK_USE_EXISTING="true"
    TRAEFIK_NAMESPACE="$found_ns"
    log_info "Detected existing Traefik installation in namespace '${found_ns}' - will reuse it and skip deploying bundled Traefik"
  else
    TRAEFIK_ENABLED="true"
    TRAEFIK_USE_EXISTING="false"
  fi
}

# Configure Longhorn disks from core-config.yaml (storage.tiers.longhorn)
# Ensures disks are registered so volumes can be scheduled.
configure_longhorn_disks() {
  if ! command_exists kubectl; then
    return
  fi
  if [ ${#TIER_LONGHORN[@]} -eq 0 ]; then
    log_warning "No longhorn tier paths defined; Longhorn will have no schedulable disks"
    return
  fi

  # Verify Longhorn CRDs exist
  if ! kubectl get nodes.longhorn.io -n longhorn-system >/dev/null 2>&1; then
    log_warning "Longhorn CRDs not ready; skipping disk configuration"
    return
  fi

  for entry in "${TIER_LONGHORN[@]}"; do
    local node="${entry%%:*}"
    local path="${entry#*:}"
    local node_json existing_paths
    node_json=$(kubectl get nodes.longhorn.io "${node}" -n longhorn-system -o json 2>/dev/null || echo "")
    if [ -z "${node_json}" ]; then
      log_warning "Longhorn node resource not found for '${node}', skipping disk ${path}"
      continue
    fi
    existing_paths=$(echo "${node_json}" | jq -r '.spec.disks | to_entries[]? | .value.path' 2>/dev/null || true)
    if echo "${existing_paths}" | grep -qx "${path}"; then
      log_info "Longhorn disk already registered on ${node}: ${path}"
      continue
    fi

    # Disk name derived from path
    local disk_name
    disk_name=$(echo "${path}" | sed 's|^/||; s|/|-|g; s|[^a-zA-Z0-9_-]|-|g')
    log_info "Registering Longhorn disk ${path} on node ${node}"
    kubectl -n longhorn-system patch nodes.longhorn.io "${node}" --type='json' \
      -p="[{\"op\":\"add\",\"path\":\"/spec/disks/${disk_name}\",\"value\":{\"path\":\"${path}\",\"allowScheduling\":true,\"evictionRequested\":false,\"storageReserved\":0}}]" \
      >/dev/null 2>&1 || log_warning "Failed to register Longhorn disk ${path} on ${node}"
  done
}

# Load core-config.yaml if present
load_core_config() {
  if [ -f "${CORE_CONFIG}" ]; then
    if ! command_exists yq; then
      log_warning "core-config.yaml found but yq is not installed; skipping config load"
      return
    fi
    log_info "Loading core configuration from ${CORE_CONFIG}"

    CFG_STORAGE_CLASS=$(yq eval '.cluster.storageClass' "${CORE_CONFIG}" 2>/dev/null || echo "")
    CFG_SINGLE_NODE_SC=$(yq eval '.cluster.singleNodeStorageClass' "${CORE_CONFIG}" 2>/dev/null || echo "")
    CFG_DOMAIN=$(yq eval '.networking.domain' "${CORE_CONFIG}" 2>/dev/null || echo "")
    CFG_INGRESS_CLASS=$(yq eval '.networking.ingressClass' "${CORE_CONFIG}" 2>/dev/null || echo "")
    CFG_ENABLE_INGRESS_ROUTES=$(yq eval '.networking.enableIngressRoutes' "${CORE_CONFIG}" 2>/dev/null || echo "")
    CFG_NODEPORT_FALLBACK=$(yq eval '.networking.useNodePortFallback' "${CORE_CONFIG}" 2>/dev/null || echo "")

    CFG_MINIO_ROOT_USER=$(yq eval '.credentials.minio.rootUser' "${CORE_CONFIG}" 2>/dev/null || echo "")
    CFG_MINIO_ROOT_PASSWORD=$(yq eval '.credentials.minio.rootPassword' "${CORE_CONFIG}" 2>/dev/null || echo "")
    CFG_AIRFLOW_USER=$(yq eval '.credentials.airflow.user' "${CORE_CONFIG}" 2>/dev/null || echo "")
    CFG_AIRFLOW_PASSWORD=$(yq eval '.credentials.airflow.password' "${CORE_CONFIG}" 2>/dev/null || echo "")
    CFG_SUPERSET_USER=$(yq eval '.credentials.superset.user' "${CORE_CONFIG}" 2>/dev/null || echo "")
    CFG_SUPERSET_PASSWORD=$(yq eval '.credentials.superset.password' "${CORE_CONFIG}" 2>/dev/null || echo "")
    CFG_GRAFANA_PASSWORD=$(yq eval '.credentials.grafana.password' "${CORE_CONFIG}" 2>/dev/null || echo "")
    CFG_OPENMETADATA_USER=$(yq eval '.credentials.openmetadata.user' "${CORE_CONFIG}" 2>/dev/null || echo "")
    CFG_OPENMETADATA_PASSWORD=$(yq eval '.credentials.openmetadata.password' "${CORE_CONFIG}" 2>/dev/null || echo "")

    CFG_SCHEMA_REGISTRY=$(yq eval '.components.schemaRegistry' "${CORE_CONFIG}" 2>/dev/null || echo "true")
    CFG_ALLUXIO=$(yq eval '.components.alluxio' "${CORE_CONFIG}" 2>/dev/null || echo "false")
    CFG_HELM_TIMEOUT=$(yq eval '.timeouts.helm' "${CORE_CONFIG}" 2>/dev/null || echo "")
    CFG_INGRESS_ENABLED=$(yq eval '.ingress.enabled' "${CORE_CONFIG}" 2>/dev/null || echo "true")
    CFG_DASHBOARD_PROTOCOL=$(yq eval '.dashboard.protocol' "${CORE_CONFIG}" 2>/dev/null || echo "")
    CFG_DASHBOARD_PORT=$(yq eval '.dashboard.port' "${CORE_CONFIG}" 2>/dev/null || echo "")
    CFG_DASHBOARD_SHOW_CREDS=$(yq eval '.dashboard.showCredentials' "${CORE_CONFIG}" 2>/dev/null || echo "true")
    CFG_DASHBOARD_VERSION=$(yq eval '.dashboard.version' "${CORE_CONFIG}" 2>/dev/null || echo "")

    CFG_LOKI_MAX_STREAMS=$(yq eval '.observability.loki.limits.maxStreamsPerUser' "${CORE_CONFIG}" 2>/dev/null || echo "")
    CFG_LOKI_MAX_QUERY_SERIES=$(yq eval '.observability.loki.limits.maxQuerySeries' "${CORE_CONFIG}" 2>/dev/null || echo "")
    CFG_LOKI_MAX_QUERY_PARALLELISM=$(yq eval '.observability.loki.limits.maxQueryParallelism' "${CORE_CONFIG}" 2>/dev/null || echo "")
    CFG_LOKI_RETENTION_PERIOD=$(yq eval '.observability.loki.limits.retentionPeriod' "${CORE_CONFIG}" 2>/dev/null || echo "")
    CFG_PROMTAIL_INOTIFY_INSTANCES=$(yq eval '.observability.promtail.inotify.maxUserInstances' "${CORE_CONFIG}" 2>/dev/null || echo "")
    CFG_PROMTAIL_INOTIFY_WATCHES=$(yq eval '.observability.promtail.inotify.maxUserWatches' "${CORE_CONFIG}" 2>/dev/null || echo "")
    CFG_LOKI_STORAGE_CLASS=$(yq eval '.observability.loki.storageClass' "${CORE_CONFIG}" 2>/dev/null || echo "")
    CFG_GRAFANA_STORAGE_CLASS=$(yq eval '.observability.grafana.storageClass' "${CORE_CONFIG}" 2>/dev/null || echo "")
    CFG_PROMETHEUS_STORAGE_CLASS=$(yq eval '.observability.prometheus.storageClass' "${CORE_CONFIG}" 2>/dev/null || echo "")
    CFG_POPULATE_EXAMPLES=$(yq eval '.components.populateExamples' "${CORE_CONFIG}" 2>/dev/null || echo "")

    CFG_MINIO_PRECREATE_BUCKETS=$(yq eval '.storage.minio.precreateBuckets' "${CORE_CONFIG}" 2>/dev/null || echo "true")
    CFG_MINIO_BUCKET_MAIN=$(yq eval '.storage.minio.buckets.main' "${CORE_CONFIG}" 2>/dev/null || echo "openlakes")
    CFG_MINIO_BUCKET_SPARK_PREFIX=$(yq eval '.storage.minio.buckets.sparkHistoryPrefix' "${CORE_CONFIG}" 2>/dev/null || echo "spark-history/")
    CFG_MELTANO_S3_BUCKET=$(yq eval '.meltano.s3.bucket' "${CORE_CONFIG}" 2>/dev/null || echo "")
    CFG_MELTANO_S3_PREFIX=$(yq eval '.meltano.s3.prefix' "${CORE_CONFIG}" 2>/dev/null || echo "meltano/")
    CFG_PROBE_PROFILE=$(yq eval '.timeouts.probes.profile' "${CORE_CONFIG}" 2>/dev/null || echo "slow")
    CFG_AIRFLOW_EXTRA_PIP=$(yq eval -o=json '.airflow.extraPipPackages' "${CORE_CONFIG}" 2>/dev/null | tr -d '\n' || echo "")
    CFG_NOTEBOOK_BUCKET=$(yq eval '.notebooks.bucket' "${CORE_CONFIG}" 2>/dev/null || echo "")
    CFG_NOTEBOOK_PREFIX_SHARED=$(yq eval '.notebooks.prefixes.shared' "${CORE_CONFIG}" 2>/dev/null || echo "shared")
    CFG_NOTEBOOK_PREFIX_WORKSPACE=$(yq eval '.notebooks.prefixes.workspace' "${CORE_CONFIG}" 2>/dev/null || echo "workspace")
    CFG_NOTEBOOK_PREFIX_PUBLISHED=$(yq eval '.notebooks.prefixes.published' "${CORE_CONFIG}" 2>/dev/null || echo "published")
    CFG_NOTEBOOK_PREFIX_ARTIFACTS=$(yq eval '.notebooks.prefixes.artifacts' "${CORE_CONFIG}" 2>/dev/null || echo "artifacts")
    CFG_NOTEBOOK_SYNC_DOWNLOAD=$(yq eval '.notebooks.sync.downloadSchedule' "${CORE_CONFIG}" 2>/dev/null || echo "*/2 * * * *")
    CFG_NOTEBOOK_SYNC_UPLOAD=$(yq eval '.notebooks.sync.uploadSchedule' "${CORE_CONFIG}" 2>/dev/null || echo "*/5 * * * *")
    CFG_NOTEBOOK_SYNC_AIRFLOW=$(yq eval '.notebooks.sync.airflowSchedule' "${CORE_CONFIG}" 2>/dev/null || echo "*/3 * * * *")
    CFG_NOTEBOOK_VERSIONING=$(yq eval '.notebooks.versioning' "${CORE_CONFIG}" 2>/dev/null || echo "true")

    # Apply overrides if provided
    if [ -n "${CFG_STORAGE_CLASS}" ]; then
      STORAGE_CONFIG="core-config.yaml"  # keep for merge; values will be applied via set flags
    fi
    if [ -n "${CFG_SINGLE_NODE_SC}" ]; then
      SINGLE_NODE_STORAGE_CLASS="${CFG_SINGLE_NODE_SC}"
    fi
    if [ -n "${CFG_HELM_TIMEOUT}" ]; then
      TIMEOUT="${CFG_HELM_TIMEOUT}"
    fi

    if [ -z "${CFG_DASHBOARD_PROTOCOL}" ] || [ "${CFG_DASHBOARD_PROTOCOL}" = "null" ]; then
      CFG_DASHBOARD_PROTOCOL="https"
    fi
    local ingress_enabled_flag
    ingress_enabled_flag=$(echo "${CFG_INGRESS_ENABLED}" | tr '[:upper:]' '[:lower:]')
    if [ -z "${CFG_DASHBOARD_PORT}" ] || [ "${CFG_DASHBOARD_PORT}" = "null" ]; then
      if [ "${ingress_enabled_flag}" = "true" ]; then
        CFG_DASHBOARD_PORT="443"
      else
        CFG_DASHBOARD_PORT="30443"
      fi
    fi
    if [ -z "${CFG_DASHBOARD_SHOW_CREDS}" ] || [ "${CFG_DASHBOARD_SHOW_CREDS}" = "null" ]; then
      CFG_DASHBOARD_SHOW_CREDS="true"
    fi
    if [ -z "${CFG_DASHBOARD_VERSION}" ] || [ "${CFG_DASHBOARD_VERSION}" = "null" ]; then
      CFG_DASHBOARD_VERSION="v${CORE_VERSION}"
    fi
    if [ -z "${CFG_NOTEBOOK_BUCKET}" ] || [ "${CFG_NOTEBOOK_BUCKET}" = "null" ]; then
      CFG_NOTEBOOK_BUCKET="openlakes-notebooks"
    fi
    if [ -z "${CFG_NOTEBOOK_PREFIX_SHARED}" ] || [ "${CFG_NOTEBOOK_PREFIX_SHARED}" = "null" ]; then
      CFG_NOTEBOOK_PREFIX_SHARED="shared"
    fi
    if [ -z "${CFG_NOTEBOOK_PREFIX_WORKSPACE}" ] || [ "${CFG_NOTEBOOK_PREFIX_WORKSPACE}" = "null" ]; then
      CFG_NOTEBOOK_PREFIX_WORKSPACE="workspace"
    fi
    if [ -z "${CFG_NOTEBOOK_PREFIX_PUBLISHED}" ] || [ "${CFG_NOTEBOOK_PREFIX_PUBLISHED}" = "null" ]; then
      CFG_NOTEBOOK_PREFIX_PUBLISHED="published"
    fi
    if [ -z "${CFG_NOTEBOOK_PREFIX_ARTIFACTS}" ] || [ "${CFG_NOTEBOOK_PREFIX_ARTIFACTS}" = "null" ]; then
      CFG_NOTEBOOK_PREFIX_ARTIFACTS="artifacts"
    fi
    if [ -z "${CFG_NOTEBOOK_SYNC_DOWNLOAD}" ] || [ "${CFG_NOTEBOOK_SYNC_DOWNLOAD}" = "null" ]; then
      CFG_NOTEBOOK_SYNC_DOWNLOAD="*/2 * * * *"
    fi
    if [ -z "${CFG_NOTEBOOK_SYNC_UPLOAD}" ] || [ "${CFG_NOTEBOOK_SYNC_UPLOAD}" = "null" ]; then
      CFG_NOTEBOOK_SYNC_UPLOAD="*/5 * * * *"
    fi
    if [ -z "${CFG_NOTEBOOK_SYNC_AIRFLOW}" ] || [ "${CFG_NOTEBOOK_SYNC_AIRFLOW}" = "null" ]; then
      CFG_NOTEBOOK_SYNC_AIRFLOW="*/3 * * * *"
    fi
    if [ -z "${CFG_NOTEBOOK_VERSIONING}" ] || [ "${CFG_NOTEBOOK_VERSIONING}" = "null" ]; then
      CFG_NOTEBOOK_VERSIONING="true"
    fi

  else
    log_info "No core-config.yaml found; using defaults/env overrides"
  fi
  build_dashboard_services_payload
}
# Clean up Released PVs in target namespace (prevents Longhorn attach errors) without data loss
cleanup_released_pvs() {
  log_info "Cleaning up Released PVs in namespace '${NAMESPACE}'..."
  local pvs
  pvs=$(kubectl get pv --no-headers 2>/dev/null | awk -v ns="${NAMESPACE}" '$4=="Retain" && $5=="Released" && $6~ns {print $1}')
  if [ -z "$pvs" ]; then
    log_info "No Released PVs to clean"
    return 0
  fi
  echo "$pvs" | while read -r pv; do
    if [ -n "$pv" ]; then
      local claim_name claim_ns
      claim_name=$(kubectl get pv "$pv" -o jsonpath='{.spec.claimRef.name}' 2>/dev/null || echo "")
      claim_ns=$(kubectl get pv "$pv" -o jsonpath='{.spec.claimRef.namespace}' 2>/dev/null || echo "")

      log_warning "Making Released PV available again: $pv"
      if [ -n "$claim_name" ]; then
        kubectl label pv "$pv" \
          openlakes.io/original-claim="${claim_name}" \
          openlakes.io/original-namespace="${claim_ns}" \
          --overwrite >/dev/null 2>&1 || true
      fi
      kubectl patch pv "$pv" -p '{"spec":{"claimRef": null}}' >/dev/null 2>&1 || true
      kubectl patch pv "$pv" -p '{"metadata":{"annotations":{"longhorn.io/volume-scheduling-error":null}}}' >/dev/null 2>&1 || true
    fi
  done
}

# Pre-bind retained PVs back to their original PVC names to avoid cross-binding
rebind_retained_pvs() {
  log_info "Rebinding retained PVs for namespace '${NAMESPACE}'..."
  local pvs
  pvs=$(kubectl get pv -l openlakes.io/original-namespace="${NAMESPACE}" --no-headers 2>/dev/null | awk '$5=="Available" {print $1}')

  if [ -z "$pvs" ]; then
    log_info "No retained PVs need rebinding"
    return 0
  fi

  echo "$pvs" | while read -r pv; do
    [ -n "$pv" ] || continue
    local claim_name capacity access_mode sc
    claim_name=$(kubectl get pv "$pv" -o jsonpath='{.metadata.labels.openlakes\.io/original-claim}' 2>/dev/null || echo "")
    capacity=$(kubectl get pv "$pv" -o jsonpath='{.spec.capacity.storage}' 2>/dev/null || echo "")
    access_mode=$(kubectl get pv "$pv" -o jsonpath='{.spec.accessModes[0]}' 2>/dev/null || echo "")
    sc=$(kubectl get pv "$pv" -o jsonpath='{.spec.storageClassName}' 2>/dev/null || echo "")

    if [ -z "$claim_name" ]; then
      log_warning "Skipping PV ${pv} - missing original claim label"
      continue
    fi

    if kubectl get pvc "${claim_name}" -n "${NAMESPACE}" >/dev/null 2>&1; then
      log_info "PVC ${claim_name} already exists - skipping prebind for ${pv}"
      continue
    fi

    # Default release name for infrastructure-owned PVCs
    local release_name="01-infrastructure"

    cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${claim_name}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/managed-by: Helm
    app: openlakes-pv-reuse
  annotations:
    meta.helm.sh/release-name: ${release_name}
    meta.helm.sh/release-namespace: ${NAMESPACE}
spec:
  accessModes:
  - ${access_mode:-ReadWriteOnce}
  resources:
    requests:
      storage: ${capacity:-1Gi}
  storageClassName: ${sc}
  volumeName: ${pv}
EOF

    if kubectl get pvc "${claim_name}" -n "${NAMESPACE}" >/dev/null 2>&1; then
      log_success "Rebound PV ${pv} to PVC ${claim_name}"
    else
      log_warning "Failed to rebind PV ${pv} to PVC ${claim_name}"
    fi
  done
}

# Remove existing analytics examples Job to avoid immutable spec conflicts on redeploy
reset_analytics_examples_job() {
  local enabled
  enabled=$(echo "${ANALYTICS_EXAMPLES_ENABLED}" | tr '[:upper:]' '[:lower:]')
  if [ "${enabled}" != "true" ]; then
    return 0
  fi

  if kubectl get job analytics-jupyter-populate-examples -n "${NAMESPACE}" >/dev/null 2>&1; then
    log_info "Resetting analytics examples Job before redeploying analytics layer..."
    kubectl delete job analytics-jupyter-populate-examples -n "${NAMESPACE}" --ignore-not-found >/dev/null 2>&1 || true
  fi
}

# Warn if examples are enabled but the required Git credentials secret is missing
validate_analytics_examples_secret() {
  local enabled
  enabled=$(echo "${ANALYTICS_EXAMPLES_ENABLED}" | tr '[:upper:]' '[:lower:]')
  if [ "${enabled}" != "true" ]; then
    return 0
  fi

  if [ -z "${ANALYTICS_EXAMPLES_TOKEN_SECRET}" ]; then
    log_info "Analytics examples enabled without a tokenSecret; assuming repository is publicly readable"
    return 0
  fi

  if ! kubectl get secret "${ANALYTICS_EXAMPLES_TOKEN_SECRET}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    log_warning "tokenSecret '${ANALYTICS_EXAMPLES_TOKEN_SECRET}' for analytics examples not found in namespace '${NAMESPACE}'. Create it to enable private repo access."
  fi
}

# Check inter-node throughput for multi-node clusters
check_network_throughput() {
  # Skip when requested or not applicable
  local node_count
  node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo "0")

  if [ "$node_count" -lt 2 ]; then
    log_info "Single-node cluster detected - skipping inter-node throughput check"
    return 0
  fi

  if [ "${DRY_RUN}" = "true" ]; then
    log_info "Dry-run mode: skipping inter-node throughput check"
    return 0
  fi

  if ! command_exists python3; then
    log_warning "python3 is required to parse iperf3 JSON output; skipping throughput check"
    return 0
  fi

  log_info "Measuring inter-node network throughput (multi-node preflight)..."
  if [ "${SKIP_THROUGHPUT_CHECK}" = "true" ]; then
    log_info "Skipping throughput check (requested via --skip-throughput-check)"
    return 0
  fi

  # Choose two nodes to test between
  local node_list
  read -r -a node_list <<<"$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)"
  local node_a="${node_list[0]}"
  local node_b="${node_list[1]}"

  local cni
  cni=$(detect_cni)
  log_info "Detected CNI: ${cni}"

  local server_pod="net-test-server"
  local client_name="net-test-client"

  # Clean up any previous test pods
  kubectl delete pod "${server_pod}" -n default --ignore-not-found=true >/dev/null 2>&1 || true
  kubectl delete pod "${client_name}" -n default --ignore-not-found=true >/dev/null 2>&1 || true

  # Start iperf3 server pinned to node A
  cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: ${server_pod}
  namespace: default
  labels:
    app: net-test
spec:
  nodeName: ${node_a}
  restartPolicy: Never
  containers:
  - name: server
    image: networkstatic/iperf3:latest
    args: ["-s"]
    ports:
    - containerPort: 5201
EOF

  if ! kubectl wait --for=condition=Ready pod/${server_pod} -n default --timeout=60s >/dev/null 2>&1; then
    log_warning "Unable to start iperf3 server pod for throughput test; skipping check"
    kubectl delete pod "${server_pod}" -n default --ignore-not-found=true >/dev/null 2>&1 || true
    return 0
  fi

  local server_ip
  server_ip=$(kubectl get pod "${server_pod}" -n default -o jsonpath='{.status.podIP}' 2>/dev/null || echo "")
  if [ -z "${server_ip}" ]; then
    log_warning "Could not determine iperf3 server IP; skipping throughput check"
    kubectl delete pod "${server_pod}" -n default --ignore-not-found=true >/dev/null 2>&1 || true
    return 0
  fi

  log_info "Running iperf3 client on ${node_b} against ${node_a} (${server_ip})..."

  local client_output
  if ! client_output=$(kubectl run "${client_name}" \
    --rm -i --restart=Never \
    --image=networkstatic/iperf3:latest \
    --namespace default \
    --overrides="{\"spec\":{\"nodeName\":\"${node_b}\"}}" \
    --command -- iperf3 -c "${server_ip}" -t 3 -P 2 -J 2>/dev/null); then
    log_warning "iperf3 client test failed; skipping throughput check"
    kubectl delete pod "${server_pod}" -n default --ignore-not-found=true >/dev/null 2>&1 || true
    return 0
  fi

  # Clean up server
  kubectl delete pod "${server_pod}" -n default --ignore-not-found=true >/dev/null 2>&1 || true

  local throughput_bps
  throughput_bps=$(echo "${client_output}" | python3 - <<'PY'
import json, sys
try:
    data = json.load(sys.stdin)
    bps = (
        data.get("end", {})
            .get("sum_received", {})
            .get("bits_per_second")
    )
    if not bps:
        bps = (
            data.get("end", {})
                .get("sum", {})
                .get("received_bits_per_second")
        )
    if bps:
        print(int(bps))
except Exception:
    pass
PY
)

  if [ -z "${throughput_bps}" ]; then
    log_warning "Could not parse iperf3 throughput results"
    return 0
  fi

  local throughput_mbps throughput_gbps
  throughput_mbps=$(python3 - <<PY
bps=${throughput_bps:-0}
print(int(bps/1e6))
PY
)
  throughput_gbps=$(python3 - <<PY
bps=${throughput_bps:-0}
print(f"{bps/1e9:.2f}")
PY
)

  if [ "${throughput_mbps}" -ge 1000 ]; then
    log_success "Inter-node throughput: ${throughput_gbps} Gbps between ${node_a} and ${node_b}"
  else
    log_warning "Inter-node throughput below 1 Gbps: ${throughput_mbps} Mbps between ${node_a} and ${node_b}"
    if [ "${cni}" != "cilium" ]; then
      log_warning "CNI '${cni}' detected; for higher throughput on RKE2, install Cilium or another high-performance CNI"
    else
      log_warning "Cilium detected; investigate node/network configuration to improve throughput"
    fi
  fi
}


# Validate prerequisites
validate_prerequisites() {
  log_info "Validating prerequisites..."

  local missing=0

  # Check if kubectl is installed
  if ! command_exists kubectl; then
    log_error "kubectl is not installed"
    missing=1
  else
    # Verify kubectl is working
    if ! kubectl version --client >/dev/null 2>&1; then
      log_error "kubectl is installed but not working properly"
      missing=1
    fi
  fi

  # Check if helm is installed
  if ! command_exists helm; then
    log_error "helm is not installed"
    missing=1
  else
    # Verify helm is working
    if ! helm version >/dev/null 2>&1; then
      log_error "helm is installed but not working properly"
      missing=1
    fi
  fi

  # Check if jq is installed (needed for storage wizard)
  if [ "${CONFIGURE_STORAGE}" = "true" ]; then
    if ! command_exists jq; then
      log_error "jq is required for storage configuration but not installed"
      missing=1
    fi
  fi

  # Check if yq is installed (needed for MinIO topology configuration)
  if [ -n "${STORAGE_CONFIG}" ] && [ -f "${STORAGE_CONFIG}" ]; then
    if ! command_exists yq; then
      log_warning "yq is not installed - advanced storage topology features will be unavailable"
      log_info "Install yq for MinIO multi-drive topology support:"
      case "${PLATFORM}" in
        mac)
          log_info "  brew install yq"
          ;;
        linux)
          log_info "  wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
          log_info "  chmod +x /usr/local/bin/yq"
          ;;
      esac
    fi
  fi

  if [ $missing -eq 1 ]; then
    log_error "Please install missing prerequisites"
    exit 1
  fi

  # Check Kubernetes connectivity
  if ! kubectl cluster-info >/dev/null 2>&1; then
    log_error "Cannot connect to Kubernetes cluster"
    exit 1
  fi

  # Determine cluster mode early (single vs multi)
  detect_cluster_mode
  log_info "Detected cluster: ${NODE_COUNT} node(s) -> ${CLUSTER_MODE}-node mode"

  # Longhorn will be installed for multi-node; skip NFS client preflight
  log_info "Skipping NFS client preflight (Longhorn will handle RWX mounts)"

  log_success "Prerequisites validated (Platform: ${PLATFORM})"
}

# Check for existing deployments in cluster
check_cluster_state() {
  log_info "Checking cluster state..."

  # System namespaces that should be ignored
  local system_namespaces="kube-system kube-public kube-node-lease kube-node-lease default local-path-storage"

  # Get all namespaces except system ones
  local user_namespaces=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep -v -E "^($(echo $system_namespaces | tr ' ' '|'))$" || echo "")

  if [ -z "$user_namespaces" ]; then
    log_success "Cluster appears clean (only system namespaces found)"
    return 0
  fi

  # Check for existing deployments/statefulsets/daemonsets in non-system namespaces
  local has_workloads=0
  local workload_summary=""

  for ns in $user_namespaces; do
    # Skip the openlakes namespace if it's the one we're deploying to
    if [ "$ns" = "${NAMESPACE}" ]; then
      continue
    fi

    # Count workloads in this namespace
    local deployments=$(kubectl get deployments -n "$ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    local statefulsets=$(kubectl get statefulsets -n "$ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    local daemonsets=$(kubectl get daemonsets -n "$ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    local total=$((deployments + statefulsets + daemonsets))

    if [ $total -gt 0 ]; then
      has_workloads=1
      workload_summary="${workload_summary}\n  - ${ns}: ${deployments} deployments, ${statefulsets} statefulsets, ${daemonsets} daemonsets"
    fi
  done

  # Check for helm releases in non-system namespaces
  local helm_releases=$(helm list --all-namespaces -q 2>/dev/null | grep -v "^$" | wc -l | tr -d ' ')

  if [ $has_workloads -eq 1 ] || [ "$helm_releases" -gt 0 ]; then
    echo ""
    log_warning "╔════════════════════════════════════════════════════════════╗"
    log_warning "║  WARNING: Cluster contains existing deployments!          ║"
    log_warning "╚════════════════════════════════════════════════════════════╝"
    echo ""

    if [ $has_workloads -eq 1 ]; then
      echo -e "${YELLOW}Found workloads in non-system namespaces:${NC}"
      echo -e "$workload_summary"
      echo ""
    fi

    if [ "$helm_releases" -gt 0 ]; then
      echo -e "${YELLOW}Found ${helm_releases} existing Helm releases:${NC}"
      helm list --all-namespaces
      echo ""
    fi

    # In dry-run mode, just warn and continue
    if [ "${DRY_RUN}" = "true" ]; then
      log_warning "Dry-run mode: Would ask for confirmation before deploying"
      return 0
    fi

    # Check if running in non-interactive mode (CI/CD)
    if [ ! -t 0 ]; then
      log_warning "Non-interactive terminal detected (CI/CD mode)"
      log_warning "Automatically continuing deployment on non-clean cluster"
      log_info "Set DRY_RUN=true to prevent automatic deployment"
      return 0
    fi

    # Ask for confirmation (interactive mode only)
    echo -e "${YELLOW}This cluster does not appear to be clean.${NC}"
    echo -e "${YELLOW}Deploying OpenLakes may affect existing workloads.${NC}"
    echo ""
    echo -n "Do you want to continue? [y/N]: "
    read -r response

    case "$response" in
      [yY][eE][sS]|[yY])
        log_info "User confirmed deployment on non-clean cluster"
        ;;
      *)
        log_info "Deployment cancelled by user"
        exit 0
        ;;
    esac
  else
    log_success "Cluster appears clean (no user workloads found)"
  fi
}

# Create namespace if it doesn't exist
ensure_namespace() {
  log_info "Ensuring namespace '${NAMESPACE}' exists..."

  if kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
    log_success "Namespace '${NAMESPACE}' already exists"
  else
    if [ "${DRY_RUN}" = "true" ]; then
      log_info "Would create namespace '${NAMESPACE}'"
    else
      kubectl create namespace "${NAMESPACE}"
      log_success "Created namespace '${NAMESPACE}'"
    fi
  fi
}

# Wait for a deployment to be ready
wait_for_deployment() {
  local deployment=$1
  local namespace=$2
  local timeout=${3:-300}

  log_info "Waiting for deployment '${deployment}' to be ready..."

  if [ "${DRY_RUN}" = "true" ]; then
    log_info "Would wait for deployment '${deployment}'"
    return 0
  fi

  if kubectl wait --for=condition=available \
    --timeout="${timeout}s" \
    "deployment/${deployment}" \
    -n "${namespace}" >/dev/null 2>&1; then
    log_success "Deployment '${deployment}' is ready"
    return 0
  else
    log_warning "Deployment '${deployment}' did not become ready within ${timeout}s (continuing anyway)"
    return 0
  fi
}

# Wait for a statefulset to be ready
wait_for_statefulset() {
  local statefulset=$1
  local namespace=$2
  local timeout=${3:-300}

  log_info "Waiting for statefulset '${statefulset}' to be ready..."

  if [ "${DRY_RUN}" = "true" ]; then
    log_info "Would wait for statefulset '${statefulset}'"
    return 0
  fi

  local end_time=$(($(date +%s) + timeout))

  while [ $(date +%s) -lt $end_time ]; do
    if kubectl get statefulset "${statefulset}" -n "${namespace}" >/dev/null 2>&1; then
      local ready=$(kubectl get statefulset "${statefulset}" -n "${namespace}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
      local desired=$(kubectl get statefulset "${statefulset}" -n "${namespace}" -o jsonpath='{.status.replicas}' 2>/dev/null || echo "1")

      if [ "${ready}" = "${desired}" ] && [ "${ready}" != "0" ]; then
        log_success "StatefulSet '${statefulset}' is ready (${ready}/${desired})"
        return 0
      fi
    fi
    sleep 5
  done

  log_warning "StatefulSet '${statefulset}' did not become ready within ${timeout}s (continuing anyway)"
  return 0
}

# Deploy a Helm release
deploy_layer() {
  local layer_num=$1
  local layer_name=$2
  local release_name=$3
  local wait_for=$4

  echo ""
  log_info "═══════════════════════════════════════════════════════════"
  log_info "Deploying Layer ${layer_num}: ${layer_name} (${DEPLOY_ENV})"
  log_info "═══════════════════════════════════════════════════════════"

  local layer_path="./layers/${layer_num}-${layer_name}"

  if [ ! -d "${layer_path}" ]; then
    log_error "Layer directory not found: ${layer_path}"
    return 1
  fi

  # Build Helm values file arguments
  local values_args=()

  # Always use base values.yaml
  if [ -f "${layer_path}/values.yaml" ]; then
    values_args+=("-f" "${layer_path}/values.yaml")
  fi

  # Add environment-specific values file if not production
  if [ "${DEPLOY_ENV}" != "production" ]; then
    local env_values="${layer_path}/values-${DEPLOY_ENV}.yaml"
    if [ -f "${env_values}" ]; then
      log_info "Using ${DEPLOY_ENV} environment overrides"
      values_args+=("-f" "${env_values}")
    fi
  fi

  # Apply core-config.yaml so user overrides take precedence over defaults
  if [ -f "${CORE_CONFIG}" ]; then
    values_args+=("-f" "${CORE_CONFIG}")
  fi

  # Add storage configuration if provided (highest precedence for storage layout)
  if [ -n "${STORAGE_CONFIG}" ] && [ -f "${STORAGE_CONFIG}" ]; then
    values_args+=("-f" "${STORAGE_CONFIG}")
  fi

  # Common overrides derived from core-config
  local overrides=()
  if [ -n "${CFG_STORAGE_CLASS}" ]; then
    overrides+=("--set" "global.storageClass=${CFG_STORAGE_CLASS}")
  fi
  if [ -n "${CFG_DOMAIN}" ]; then
    overrides+=("--set" "global.networking.domain=${CFG_DOMAIN}")
  fi
  if [ -n "${CFG_INGRESS_CLASS}" ]; then
    overrides+=("--set" "global.networking.ingressClass=${CFG_INGRESS_CLASS}")
  fi
  if [ -n "${CFG_ENABLE_INGRESS_ROUTES}" ]; then
    overrides+=("--set" "global.networking.enableIngressRoutes=${CFG_ENABLE_INGRESS_ROUTES}")
  fi
  overrides+=("--set-string" "global.minio.endpoint=http://infrastructure-minio:9000")
  if [ -n "${CFG_MINIO_ROOT_USER}" ]; then
    overrides+=("--set" "minio.auth.rootUser=${CFG_MINIO_ROOT_USER}")
    overrides+=("--set" "global.minio.rootUser=${CFG_MINIO_ROOT_USER}")
  fi
  if [ -n "${CFG_MINIO_ROOT_PASSWORD}" ]; then
    overrides+=("--set" "minio.auth.rootPassword=${CFG_MINIO_ROOT_PASSWORD}")
    overrides+=("--set" "global.minio.rootPassword=${CFG_MINIO_ROOT_PASSWORD}")
  fi
  if [ -n "${CFG_SCHEMA_REGISTRY}" ]; then
    overrides+=("--set" "schemaRegistry.enabled=${CFG_SCHEMA_REGISTRY}")
  fi
  if [ -n "${CFG_ALLUXIO}" ]; then
    overrides+=("--set" "alluxio.enabled=${CFG_ALLUXIO}")
  fi
  # Traefik handling: reuse existing controller if detected
  if [ "${TRAEFIK_USE_EXISTING}" = "true" ]; then
    overrides+=("--set" "traefik.enabled=false")
    overrides+=("--set" "traefik.useExisting=true")
    overrides+=("--set" "global.networking.ingressClass=${CFG_INGRESS_CLASS:-traefik}")
  fi

  # Layer-specific overrides
  case "${layer_name}" in
    orchestration)
      local airflow_pip_json="${CFG_AIRFLOW_EXTRA_PIP}"
      if [ -z "${airflow_pip_json}" ] || [ "${airflow_pip_json}" = "null" ]; then
        airflow_pip_json='["apache-airflow-providers-papermill==3.8.1","apache-airflow-providers-apache-spark==5.4.0","papermill==2.6.0","trino==0.328.0","kafka-python==2.0.2"]'
      fi
      overrides+=("--set-json" "airflow.extraPipPackages=${airflow_pip_json}")
      if [ -n "${CFG_NOTEBOOK_BUCKET}" ]; then
        overrides+=("--set-string" "notebooks.bucket=${CFG_NOTEBOOK_BUCKET}")
      fi
      overrides+=("--set-string" "notebooks.prefixes.shared=${CFG_NOTEBOOK_PREFIX_SHARED}")
      overrides+=("--set-string" "notebooks.prefixes.published=${CFG_NOTEBOOK_PREFIX_PUBLISHED}")
      overrides+=("--set-string" "notebooks.sync.airflowSchedule=${CFG_NOTEBOOK_SYNC_AIRFLOW}")
      if [ -n "${CFG_AIRFLOW_USER}" ]; then
        overrides+=("--set-string" "airflow.auth.adminUser=${CFG_AIRFLOW_USER}")
        overrides+=("--set-string" "airflow.auth.adminEmail=${CFG_AIRFLOW_USER}@openlakes.local")
      fi
      if [ -n "${CFG_AIRFLOW_PASSWORD}" ]; then
        overrides+=("--set-string" "airflow.auth.adminPassword=${CFG_AIRFLOW_PASSWORD}")
      fi
      ;;
    compute)
      if [ -n "${CFG_PROBE_PROFILE}" ]; then
        overrides+=("--set" "spark.historyServer.probeProfile=${CFG_PROBE_PROFILE}")
      fi
      if [ -n "${CFG_MINIO_BUCKET_MAIN}" ]; then
        overrides+=("--set" "spark.historyServer.eventLogDir=s3a://${CFG_MINIO_BUCKET_MAIN}/${CFG_MINIO_BUCKET_SPARK_PREFIX}")
      fi
      # Trino resource tuning by profile
      case "${RESOURCE_PROFILE}" in
        compact)
          overrides+=("--set" "trino.coordinator.resources.requests.cpu=500m")
          overrides+=("--set" "trino.coordinator.resources.requests.memory=768Mi")
          overrides+=("--set" "trino.coordinator.resources.limits.cpu=2")
          overrides+=("--set" "trino.coordinator.resources.limits.memory=2Gi")
          overrides+=("--set" "trino.worker.resources.requests.cpu=500m")
          overrides+=("--set" "trino.worker.resources.requests.memory=768Mi")
          overrides+=("--set" "trino.worker.resources.limits.cpu=2")
          overrides+=("--set" "trino.worker.resources.limits.memory=2Gi")
          ;;
        small)
          overrides+=("--set" "trino.coordinator.resources.requests.cpu=1")
          overrides+=("--set" "trino.coordinator.resources.requests.memory=2Gi")
          overrides+=("--set" "trino.coordinator.resources.limits.cpu=3")
          overrides+=("--set" "trino.coordinator.resources.limits.memory=4Gi")
          overrides+=("--set" "trino.worker.resources.requests.cpu=1")
          overrides+=("--set" "trino.worker.resources.requests.memory=2Gi")
          overrides+=("--set" "trino.worker.resources.limits.cpu=3")
          overrides+=("--set" "trino.worker.resources.limits.memory=4Gi")
          ;;
      esac
      ;;
    ingestion)
      local meltano_bucket="${CFG_MELTANO_S3_BUCKET:-$CFG_MINIO_BUCKET_MAIN}"
      if [ -n "${meltano_bucket}" ]; then
        overrides+=("--set" "meltano.s3.bucket=${meltano_bucket}")
      fi
      if [ -n "${CFG_MELTANO_S3_PREFIX}" ]; then
        overrides+=("--set-string" "meltano.s3.prefix=${CFG_MELTANO_S3_PREFIX}")
      fi
      case "${RESOURCE_PROFILE}" in
        compact)
          overrides+=("--set" "meltano.resources.requests.cpu=150m")
          overrides+=("--set" "meltano.resources.requests.memory=384Mi")
          overrides+=("--set" "meltano.resources.limits.cpu=600m")
          overrides+=("--set" "meltano.resources.limits.memory=1.2Gi")
          ;;
        small)
          overrides+=("--set" "meltano.resources.requests.cpu=250m")
          overrides+=("--set" "meltano.resources.requests.memory=640Mi")
          overrides+=("--set" "meltano.resources.limits.cpu=1.2")
          overrides+=("--set" "meltano.resources.limits.memory=1.5Gi")
          ;;
      esac
      # Debezium tuning on compact/small to reduce CPU/memory footprint
      case "${RESOURCE_PROFILE}" in
        compact)
          overrides+=("--set" "debezium.resources.requests.cpu=200m")
          overrides+=("--set" "debezium.resources.requests.memory=512Mi")
          overrides+=("--set" "debezium.resources.limits.cpu=700m")
          overrides+=("--set" "debezium.resources.limits.memory=900Mi")
          ;;
        small)
          overrides+=("--set" "debezium.resources.requests.cpu=300m")
          overrides+=("--set" "debezium.resources.requests.memory=768Mi")
          overrides+=("--set" "debezium.resources.limits.cpu=1000m")
          overrides+=("--set" "debezium.resources.limits.memory=1.2Gi")
          ;;
      esac
      ;;
    analytics)
      local effective_examples_flag="${ANALYTICS_EXAMPLES_ENABLED:-true}"
      if [ "${effective_examples_flag}" != "false" ] && [ -d "${LOCAL_EXAMPLES_DIR}" ]; then
        LOCAL_EXAMPLES_AVAILABLE="true"
        effective_examples_flag="false"
        log_info "Local examples detected at ${LOCAL_EXAMPLES_DIR}; disabling remote Git fetch."
      fi
      overrides+=("--set" "analyticsExamples.enabled=${effective_examples_flag}")
      # Ensure JupyterHub can reach the K8s API (avoid NP/dual-stack timeouts)
      overrides+=("--set" "jupyterhub.hub.networkPolicy.enabled=false")
      if [ -n "${KUBE_API_IPV4}" ]; then
        overrides+=("--set-string" "jupyterhub.hub.extraEnv.KUBERNETES_SERVICE_HOST=${KUBE_API_IPV4}")
        overrides+=("--set-string" "jupyterhub.hub.extraEnv.KUBERNETES_SERVICE_PORT=${KUBE_API_PORT}")
        overrides+=("--set-string" "jupyterhub.hub.extraEnv.KUBERNETES_SERVICE_PORT_HTTPS=${KUBE_API_PORT}")
      fi
      case "${RESOURCE_PROFILE}" in
        compact)
          overrides+=("--set" "superset.resources.requests.cpu=200m")
          overrides+=("--set" "superset.resources.requests.memory=512Mi")
          overrides+=("--set" "superset.resources.limits.cpu=400m")
          overrides+=("--set" "superset.resources.limits.memory=900Mi")
          ;;
        small)
          overrides+=("--set" "superset.resources.requests.cpu=300m")
          overrides+=("--set" "superset.resources.requests.memory=768Mi")
          overrides+=("--set" "superset.resources.limits.cpu=700m")
          overrides+=("--set" "superset.resources.limits.memory=1.5Gi")
          ;;
      esac
      if [ -n "${CFG_NOTEBOOK_BUCKET}" ]; then
        overrides+=("--set-string" "notebooks.bucket=${CFG_NOTEBOOK_BUCKET}")
      fi
      overrides+=("--set-string" "notebooks.prefixes.shared=${CFG_NOTEBOOK_PREFIX_SHARED}")
      overrides+=("--set-string" "notebooks.prefixes.workspace=${CFG_NOTEBOOK_PREFIX_WORKSPACE}")
      overrides+=("--set-string" "notebooks.prefixes.published=${CFG_NOTEBOOK_PREFIX_PUBLISHED}")
      overrides+=("--set-string" "notebooks.sync.downloadSchedule=${CFG_NOTEBOOK_SYNC_DOWNLOAD}")
      overrides+=("--set-string" "notebooks.sync.uploadSchedule=${CFG_NOTEBOOK_SYNC_UPLOAD}")
      overrides+=("--set-string" "jupyterhub.singleuser.extraEnv.OPENLAKES_NOTEBOOK_BUCKET=${CFG_NOTEBOOK_BUCKET}")
      overrides+=("--set-string" "jupyterhub.singleuser.extraEnv.OPENLAKES_NOTEBOOK_SHARED_PREFIX=${CFG_NOTEBOOK_PREFIX_SHARED}")
      overrides+=("--set-string" "jupyterhub.singleuser.extraEnv.OPENLAKES_NOTEBOOK_WORKSPACE_PREFIX=${CFG_NOTEBOOK_PREFIX_WORKSPACE}")
      overrides+=("--set-string" "jupyterhub.singleuser.extraEnv.OPENLAKES_NOTEBOOK_PUBLISHED_PREFIX=${CFG_NOTEBOOK_PREFIX_PUBLISHED}")
      overrides+=("--set-string" "jupyterhub.singleuser.extraEnv.OPENLAKES_NOTEBOOK_ARTIFACT_PREFIX=${CFG_NOTEBOOK_PREFIX_ARTIFACTS}")
      overrides+=("--set-string" "jupyterhub.singleuser.extraEnv.OPENLAKES_MINIO_ENDPOINT=http://infrastructure-minio:9000")
      overrides+=("--set-string" "jupyterhub.singleuser.extraEnv.OPENLAKES_MINIO_ACCESS_KEY=${CFG_MINIO_ROOT_USER}")
      overrides+=("--set-string" "jupyterhub.singleuser.extraEnv.OPENLAKES_MINIO_SECRET_KEY=${CFG_MINIO_ROOT_PASSWORD}")
      ;;
    catalog)
      if [ -n "${CFG_PROBE_PROFILE}" ]; then
        overrides+=("--set" "openmetadata.probeProfile=${CFG_PROBE_PROFILE}")
      fi
      case "${RESOURCE_PROFILE}" in
        compact)
          overrides+=("--set" "openmetadata.resources.requests.cpu=500m")
          overrides+=("--set" "openmetadata.resources.requests.memory=900Mi")
          overrides+=("--set" "openmetadata.resources.limits.cpu=1")
          overrides+=("--set" "openmetadata.resources.limits.memory=1500Mi")
          overrides+=("--set" "ingestion.webserver.resources.requests.cpu=200m")
          overrides+=("--set" "ingestion.webserver.resources.requests.memory=400Mi")
          overrides+=("--set" "ingestion.webserver.resources.limits.cpu=800m")
          overrides+=("--set" "ingestion.webserver.resources.limits.memory=1250Mi")
          overrides+=("--set" "ingestion.scheduler.resources.requests.cpu=300m")
          overrides+=("--set" "ingestion.scheduler.resources.requests.memory=600Mi")
          overrides+=("--set" "ingestion.scheduler.resources.limits.cpu=800m")
          overrides+=("--set" "ingestion.scheduler.resources.limits.memory=1300Mi")
          ;;
        small)
          overrides+=("--set" "openmetadata.resources.requests.cpu=700m")
          overrides+=("--set" "openmetadata.resources.requests.memory=1.5Gi")
          overrides+=("--set" "openmetadata.resources.limits.cpu=2")
          overrides+=("--set" "openmetadata.resources.limits.memory=3Gi")
          overrides+=("--set" "ingestion.webserver.resources.requests.cpu=400m")
          overrides+=("--set" "ingestion.webserver.resources.requests.memory=768Mi")
          overrides+=("--set" "ingestion.webserver.resources.limits.cpu=1")
          overrides+=("--set" "ingestion.webserver.resources.limits.memory=1.5Gi")
          overrides+=("--set" "ingestion.scheduler.resources.requests.cpu=400m")
          overrides+=("--set" "ingestion.scheduler.resources.requests.memory=768Mi")
          overrides+=("--set" "ingestion.scheduler.resources.limits.cpu=1")
          overrides+=("--set" "ingestion.scheduler.resources.limits.memory=1.5Gi")
          ;;
      esac
      ;;
    infrastructure)
      if [ -n "${CFG_PROBE_PROFILE}" ]; then
        overrides+=("--set" "schemaRegistry.startupProbe.profile=${CFG_PROBE_PROFILE}")
      fi
      if [ -n "${CFG_NOTEBOOK_BUCKET}" ]; then
        overrides+=("--set-string" "notebooks.bucket=${CFG_NOTEBOOK_BUCKET}")
      fi
      overrides+=("--set-string" "notebooks.prefixes.shared=${CFG_NOTEBOOK_PREFIX_SHARED}")
      overrides+=("--set-string" "notebooks.prefixes.workspace=${CFG_NOTEBOOK_PREFIX_WORKSPACE}")
      overrides+=("--set-string" "notebooks.prefixes.published=${CFG_NOTEBOOK_PREFIX_PUBLISHED}")
      overrides+=("--set-string" "notebooks.prefixes.artifacts=${CFG_NOTEBOOK_PREFIX_ARTIFACTS}")
      overrides+=("--set-string" "notebooks.versioning=${CFG_NOTEBOOK_VERSIONING}")
      case "${RESOURCE_PROFILE}" in
        compact)
          overrides+=("--set" "opensearch.resources.requests.cpu=400m")
          overrides+=("--set" "opensearch.resources.requests.memory=1Gi")
          overrides+=("--set" "opensearch.resources.limits.cpu=1.5")
          overrides+=("--set" "opensearch.resources.limits.memory=2Gi")
          overrides+=("--set" "opensearch.javaOpts=-Xms1024m -Xmx1024m")
          ;;
        small)
          overrides+=("--set" "opensearch.resources.requests.cpu=800m")
          overrides+=("--set" "opensearch.resources.requests.memory=2Gi")
          overrides+=("--set" "opensearch.resources.limits.cpu=2.5")
          overrides+=("--set" "opensearch.resources.limits.memory=4Gi")
          overrides+=("--set" "opensearch.javaOpts=-Xms3g -Xmx3g")
          ;;
      esac
      if [ -n "${CFG_DASHBOARD_PROTOCOL}" ]; then
        overrides+=("--set-string" "dashboard.env.protocol=${CFG_DASHBOARD_PROTOCOL}")
      fi
      if [ -n "${CFG_DOMAIN}" ]; then
        overrides+=("--set-string" "dashboard.env.domain=${CFG_DOMAIN}")
      fi
      if [ -n "${CFG_DASHBOARD_PORT}" ]; then
        overrides+=("--set-string" "dashboard.env.port=${CFG_DASHBOARD_PORT}")
      fi
      if [ -n "${CFG_DASHBOARD_SHOW_CREDS}" ]; then
        overrides+=("--set-string" "dashboard.env.showCredentials=${CFG_DASHBOARD_SHOW_CREDS}")
      fi
      if [ -n "${CFG_DASHBOARD_VERSION}" ]; then
        overrides+=("--set-string" "dashboard.env.version=${CFG_DASHBOARD_VERSION}")
      fi
      if [ -n "${DASHBOARD_SERVICES_B64}" ]; then
        overrides+=("--set-string" "dashboard.env.servicesB64=${DASHBOARD_SERVICES_B64}")
      fi
      ;;
    monitoring)
      overrides+=("--set" "dcgmExporter.enabled=${GPU_MONITORING_ENABLED}")
      if [ -n "${CFG_LOKI_MAX_STREAMS}" ]; then
        overrides+=("--set" "loki.limits_config.max_streams_per_user=${CFG_LOKI_MAX_STREAMS}")
      elif [ "${RESOURCE_PROFILE}" = "compact" ]; then
        overrides+=("--set" "loki.limits_config.max_streams_per_user=20000")
      fi
      if [ -n "${CFG_LOKI_MAX_QUERY_SERIES}" ]; then
        overrides+=("--set" "loki.limits_config.max_query_series=${CFG_LOKI_MAX_QUERY_SERIES}")
      fi
      if [ -n "${CFG_LOKI_MAX_QUERY_PARALLELISM}" ]; then
        overrides+=("--set" "loki.limits_config.max_query_parallelism=${CFG_LOKI_MAX_QUERY_PARALLELISM}")
      fi
      if [ -n "${CFG_LOKI_RETENTION_PERIOD}" ]; then
        overrides+=("--set" "loki.limits_config.retention_period=${CFG_LOKI_RETENTION_PERIOD}")
      fi
      if [ -n "${CFG_PROMTAIL_INOTIFY_INSTANCES}" ]; then
        overrides+=("--set" "promtail.inotify.maxUserInstances=${CFG_PROMTAIL_INOTIFY_INSTANCES}")
      fi
      if [ -n "${CFG_PROMTAIL_INOTIFY_WATCHES}" ]; then
        overrides+=("--set" "promtail.inotify.maxUserWatches=${CFG_PROMTAIL_INOTIFY_WATCHES}")
      fi
      local loki_sc="${CFG_LOKI_STORAGE_CLASS:-$CFG_STORAGE_CLASS}"
      local grafana_sc="${CFG_GRAFANA_STORAGE_CLASS:-$CFG_STORAGE_CLASS}"
      local prom_sc="${CFG_PROMETHEUS_STORAGE_CLASS:-$CFG_STORAGE_CLASS}"
      if [ -n "${loki_sc}" ]; then
        overrides+=("--set" "loki.singleBinary.persistence.storageClass=${loki_sc}")
      fi
      if [ -n "${grafana_sc}" ]; then
        overrides+=("--set" "kube-prometheus-stack.grafana.persistence.storageClassName=${grafana_sc}")
      fi
      if [ -n "${prom_sc}" ]; then
        overrides+=("--set" "kube-prometheus-stack.prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=${prom_sc}")
      fi
      # Apply lighter retention on compact/small profiles
      case "${RESOURCE_PROFILE}" in
        compact)
          overrides+=("--set" "kube-prometheus-stack.prometheus.prometheusSpec.retention=1d")
          overrides+=("--set" "kube-prometheus-stack.prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=10Gi")
          ;;
        small)
          overrides+=("--set" "kube-prometheus-stack.prometheus.prometheusSpec.retention=7d")
          overrides+=("--set" "kube-prometheus-stack.prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=30Gi")
          ;;
      esac
      ;;
  esac

  if [ "${DRY_RUN}" = "true" ]; then
    log_info "Would deploy: helm upgrade --install ${release_name} ${layer_path} ${values_args[*]}"
    return 0
  fi

  # If a previous attempt is stuck in a pending state, clean it up first
  if helm status "${release_name}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    local status_line
    status_line=$(helm status "${release_name}" -n "${NAMESPACE}" 2>/dev/null | grep "^STATUS:" || true)
    if echo "${status_line}" | grep -q "pending"; then
      log_warning "Helm release '${release_name}' is in a pending state (${status_line}). Cleaning it up before redeploying..."
      helm uninstall "${release_name}" -n "${NAMESPACE}" >/dev/null 2>&1 || true
      # Remove any leftover Helm secrets to avoid stuck state
      kubectl delete secret -n "${NAMESPACE}" -l "owner=helm,name=${release_name}" --ignore-not-found >/dev/null 2>&1 || true
    fi
  fi

  if helm upgrade --install "${release_name}" "${layer_path}" \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    --timeout "${TIMEOUT}" \
    "${values_args[@]}" \
    "${overrides[@]}"; then
    log_success "Layer ${layer_num} (${layer_name}) deployed successfully"
  else
    log_error "Failed to deploy layer ${layer_num} (${layer_name})"
    return 1
  fi

  # Wait for specific resources if specified
  if [ -n "${wait_for}" ]; then
    IFS=',' read -ra RESOURCES <<< "${wait_for}"
    for resource in "${RESOURCES[@]}"; do
      local type="${resource%%:*}"
      local name="${resource##*:}"

      case "${type}" in
        statefulset)
          wait_for_statefulset "${name}" "${NAMESPACE}" 300
          ;;
        deployment)
          wait_for_deployment "${name}" "${NAMESPACE}" 300
          ;;
      esac
    done
  fi
}

# Detect if GPUs are present in the cluster
detect_gpus() {
  log_info "Detecting GPU resources in cluster..."

  # Check if any nodes have nvidia.com/gpu capacity
  local gpu_nodes
  gpu_nodes=$(kubectl get nodes -o json 2>/dev/null | grep -c '"nvidia.com/gpu"' || echo "0")
  gpu_nodes=${gpu_nodes:-0}

  if [ "$gpu_nodes" -gt 0 ] 2>/dev/null; then
    local total_gpus=$(kubectl get nodes -o json 2>/dev/null | \
      grep -o '"nvidia.com/gpu": "[0-9]*"' | \
      grep -o '[0-9]*' | \
      awk '{sum+=$1} END {print sum}')

    log_success "Detected ${total_gpus} GPU(s) across ${gpu_nodes} node(s)"
    return 0
  else
    log_info "No GPUs detected in cluster"
    return 1
  fi
}

# Detect Kubernetes service IPv4/port to force IPv4 for clients that misbehave on dual-stack
detect_kube_api_ipv4() {
  # Prefer the Service ClusterIP (always IPv4 in single-stack clusters)
  local ep_host
  ep_host=$(kubectl -n default get svc kubernetes -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
  if [ -z "${ep_host}" ]; then
    # Fallback to Endpoint (first address)
    ep_host=$(kubectl -n default get endpoints kubernetes -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null)
  fi
  local ep_port
  ep_port=$(kubectl -n default get svc kubernetes -o jsonpath='{.spec.ports[?(@.name=="https")].port}' 2>/dev/null)
  [ -z "${ep_port}" ] && ep_port="443"

  if [ -n "${ep_host}" ]; then
    KUBE_API_IPV4="${ep_host}"
    KUBE_API_PORT="${ep_port}"
    log_info "Detected Kubernetes API IPv4 endpoint: ${KUBE_API_IPV4}:${KUBE_API_PORT}"
  else
    log_warning "Could not detect Kubernetes API IPv4 endpoint; skipping IPv4 override for JupyterHub"
  fi
}

sync_local_examples_to_pvc() {
  if [ "${LOCAL_EXAMPLES_AVAILABLE}" != "true" ]; then
    return 0
  fi
  if [ ! -d "${LOCAL_EXAMPLES_DIR}" ]; then
    log_warning "Local examples directory not found: ${LOCAL_EXAMPLES_DIR}"
    return 0
  fi
  if ! command_exists kubectl; then
    log_warning "kubectl not available; cannot sync local examples"
    return 0
  fi

  local loader_pod="analytics-examples-loader"
  log_info "Syncing analytics examples from local repository (${LOCAL_EXAMPLES_DIR})..."
  cat <<EOF | kubectl -n "${NAMESPACE}" apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${loader_pod}
  labels:
    app: jupyterhub
    component: load-examples
spec:
  restartPolicy: Never
  containers:
  - name: loader
    image: minio/mc:latest
    env:
    - name: MINIO_ENDPOINT
      value: "http://infrastructure-minio:9000"
    - name: MINIO_ROOT_USER
      value: "${CFG_MINIO_ROOT_USER:-admin}"
    - name: MINIO_ROOT_PASSWORD
      value: "${CFG_MINIO_ROOT_PASSWORD:-admin123}"
    - name: NOTEBOOK_BUCKET
      value: "${CFG_NOTEBOOK_BUCKET}"
    - name: NOTEBOOK_SHARED_PREFIX
      value: "${CFG_NOTEBOOK_PREFIX_SHARED}"
    command: ["/bin/sh","-c","sleep 3600"]
    volumeMounts:
    - mountPath: /examples
      name: examples
  volumes:
  - name: examples
    persistentVolumeClaim:
      claimName: analytics-jupyter-examples
EOF

  if ! kubectl -n "${NAMESPACE}" wait --for=condition=Ready "pod/${loader_pod}" --timeout=120s >/dev/null 2>&1; then
    log_warning "Examples loader pod did not become ready"
    kubectl -n "${NAMESPACE}" delete pod "${loader_pod}" --ignore-not-found >/dev/null 2>&1 || true
    return 1
  fi

  kubectl -n "${NAMESPACE}" exec "${loader_pod}" -- sh -c "rm -rf /examples/*" >/dev/null 2>&1 || true
  if ! kubectl -n "${NAMESPACE}" cp "${LOCAL_EXAMPLES_DIR}/." "${loader_pod}:/examples" >/dev/null 2>&1; then
    log_warning "Failed to copy local examples into PVC"
    kubectl -n "${NAMESPACE}" delete pod "${loader_pod}" --ignore-not-found >/dev/null 2>&1 || true
    return 1
  fi

  kubectl -n "${NAMESPACE}" exec "${loader_pod}" -- sh -c "find /examples -type f -name '*.ipynb' -exec chmod 644 {} +" >/dev/null 2>&1 || true
  kubectl -n "${NAMESPACE}" exec "${loader_pod}" -- sh -c '
    set -euo pipefail
    alias mc="/usr/bin/mc --quiet"
    mc alias set minio "${MINIO_ENDPOINT}" "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}" >/dev/null
    mc mirror --overwrite /examples "minio/${NOTEBOOK_BUCKET}/${NOTEBOOK_SHARED_PREFIX}"
  ' >/dev/null 2>&1 || log_warning "Unable to mirror notebooks to MinIO bucket ${CFG_NOTEBOOK_BUCKET}"
  kubectl -n "${NAMESPACE}" delete pod "${loader_pod}" --ignore-not-found >/dev/null 2>&1 || true
  log_success "Local analytics examples synced to PVC"
  return 0
}

build_dashboard_services_payload() {
  if ! command_exists jq; then
    log_warning "jq not available; dashboard services list will fall back to container defaults"
    DASHBOARD_SERVICES_B64=""
    return
  fi

  local airflow_pass_value="${DYNAMIC_AIRFLOW_PASSWORD}"
  if [ -z "${airflow_pass_value}" ] || [ "${airflow_pass_value}" = "null" ]; then
    airflow_pass_value="${CFG_AIRFLOW_PASSWORD}"
  fi

  local json_payload
  json_payload=$(jq -n \
    --arg minio_user "${CFG_MINIO_ROOT_USER:-}" \
    --arg minio_pass "${CFG_MINIO_ROOT_PASSWORD:-}" \
    --arg airflow_user "${CFG_AIRFLOW_USER:-}" \
    --arg airflow_pass "${airflow_pass_value:-}" \
    --arg superset_user "${CFG_SUPERSET_USER:-}" \
    --arg superset_pass "${CFG_SUPERSET_PASSWORD:-}" \
    --arg grafana_pass "${CFG_GRAFANA_PASSWORD:-}" \
    --arg metadata_user "${CFG_OPENMETADATA_USER:-}" \
    --arg metadata_pass "${CFG_OPENMETADATA_PASSWORD:-}" \
    'def cred($u; $p):
       if (($u // "") | length) > 0 and (($p // "") | length) > 0 then
         {username: $u, password: $p}
       else
         null
       end;
     [
       {
         name: "MinIO Object Storage",
         description: "S3-compatible object storage for data lake",
         subdomain: "minio",
         category: "Infrastructure",
         color: "#C72C48",
         icon: "storage",
         credentials: cred($minio_user; $minio_pass)
       },
       {
         name: "Alluxio Web UI",
         description: "Distributed cache and filesystem monitoring",
         subdomain: "alluxio",
         category: "Infrastructure",
         color: "#0081CB",
         icon: "speed",
         credentials: null
       },
       {
         name: "Nessie Catalog",
         description: "Git-like data catalog for Iceberg tables",
         subdomain: "nessie",
         category: "Infrastructure",
         color: "#00A67D",
         icon: "accountTree",
         credentials: null
       },
       {
         name: "Schema Registry",
         description: "Apicurio-backed schema registry for Kafka workloads",
         subdomain: "schema-registry",
         category: "Infrastructure",
         color: "#8E24AA",
         icon: "dataObject",
         credentials: null
       },
       {
         name: "Traefik Dashboard",
         description: "Ingress controller and routing dashboard",
         subdomain: "traefik",
         path: "/dashboard/",
         category: "Infrastructure",
         color: "#37ABC8",
         icon: "lan",
         credentials: null
       },
       {
         name: "Spark Master UI",
         description: "Apache Spark cluster monitoring",
         subdomain: "spark",
         category: "Compute",
         color: "#E25A1C",
         icon: "dataObject",
         credentials: null
       },
       {
         name: "Spark History",
         description: "Historical Spark application runs",
         subdomain: "spark-history",
         category: "Compute",
         color: "#FF7043",
         icon: "analytics",
         credentials: null
       },
       {
         name: "Trino Web UI",
         description: "Distributed SQL query engine",
         subdomain: "trino",
         category: "Compute",
         color: "#DD00A1",
         icon: "summarize",
         credentials: null
       },
       {
         name: "Airflow",
         description: "Workflow orchestration and scheduling",
         subdomain: "airflow",
         category: "Orchestration",
         color: "#017CEE",
         icon: "widgets",
         credentials: cred($airflow_user; $airflow_pass)
       },
       {
         name: "Superset",
         description: "Data exploration and visualization",
         subdomain: "superset",
         category: "Analytics",
         color: "#20A7C9",
         icon: "insertChart",
         credentials: cred($superset_user; $superset_pass)
       },
       {
         name: "JupyterHub",
         description: "Multi-user Jupyter notebook environment",
         subdomain: "jupyter",
         category: "Analytics",
         color: "#F37726",
         icon: "code",
         credentials: null
       },
       {
         name: "Debezium",
         description: "CDC and change data capture",
         subdomain: "debezium",
         category: "Ingestion",
         color: "#FF6600",
         icon: "analytics",
         credentials: null
       },
       {
         name: "OpenMetadata",
         description: "Data catalog and lineage tracking",
         subdomain: "metadata",
         category: "Catalog",
         color: "#6366F1",
         icon: "viewModule",
         credentials: cred($metadata_user; $metadata_pass)
       },
       {
         name: "OpenMetadata Ingestion",
         description: "Airflow deployment dedicated to metadata ingestion",
         subdomain: "ingestion",
         category: "Catalog",
         color: "#5C6BC0",
         icon: "widgets",
         credentials: null
       },
       {
         name: "Grafana",
         description: "Monitoring dashboards and alerts",
         subdomain: "grafana",
         category: "Monitoring",
         color: "#F46800",
         icon: "dashboard",
         credentials: cred("admin"; $grafana_pass)
       },
       {
         name: "Prometheus",
         description: "Metrics collection and time-series database",
         subdomain: "prometheus",
         category: "Monitoring",
         color: "#E6522C",
         icon: "showChart",
         credentials: null
       },
       {
         name: "Alertmanager",
         description: "Alert routing and notification management",
         subdomain: "alertmanager",
         category: "Monitoring",
         color: "#E6522C",
         icon: "notifications",
         credentials: null
       }
     ]')

  DASHBOARD_SERVICES_B64=$(printf '%s' "${json_payload}" | base64 | tr -d '\n')
}

fetch_airflow_generated_password() {
  if ! command_exists kubectl; then
    return 1
  fi

  local pod
  pod=$(kubectl get pods -n "${NAMESPACE}" -l app=airflow,component=webserver -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [ -z "${pod}" ]; then
    return 1
  fi

  if ! kubectl -n "${NAMESPACE}" wait --for=condition=Ready "pod/${pod}" --timeout=180s >/dev/null 2>&1; then
    return 1
  fi

  local username="${CFG_AIRFLOW_USER:-admin}"
  local password
  password=$(kubectl exec -i -n "${NAMESPACE}" "${pod}" -- python3 - "$username" <<'PY' 2>/dev/null
import json, sys, pathlib
path = pathlib.Path("/opt/airflow/simple_auth_manager_passwords.json.generated")
if not path.exists():
    sys.exit(1)
data = json.loads(path.read_text())
value = data.get(sys.argv[1], "")
print(value)
PY
)
  password=$(echo "${password}" | tr -d '\r\n')
  if [ -n "${password}" ]; then
    DYNAMIC_AIRFLOW_PASSWORD="${password}"
    return 0
  fi
  return 1
}

refresh_dashboard_runtime_credentials() {
  if [ "${DASHBOARD_RUNTIME_REFRESHED}" = "true" ]; then
    return
  fi

  if ! fetch_airflow_generated_password; then
    return
  fi

  local previous="${DASHBOARD_SERVICES_B64}"
  build_dashboard_services_payload

  if [ "${DASHBOARD_SERVICES_B64}" != "${previous}" ]; then
    log_info "Applying updated dashboard credentials from runtime services..."
    if deploy_layer "01" "infrastructure" "01-infrastructure" "${INFRA_WAIT_TARGETS}"; then
      DASHBOARD_RUNTIME_REFRESHED="true"
    else
      log_warning "Failed to refresh dashboard deployment with runtime credentials"
    fi
  fi
}

sync_airflow_dags_from_repo() {
  if [ "${DRY_RUN}" = "true" ]; then
    log_info "Dry-run: skipping Airflow DAG sync"
    return 0
  fi

  local dag_source="${LOCAL_EXAMPLES_DIR}/dags"
  if [ ! -d "${dag_source}" ]; then
    log_warning "Airflow DAG source directory not found (${dag_source}); skipping DAG sync"
    return 0
  fi

  if ! command_exists kubectl; then
    log_warning "kubectl not available; cannot sync Airflow DAGs"
    return 0
  fi

  local airflow_pod
  airflow_pod=$(kubectl get pods -n "${NAMESPACE}" -l app=airflow,component=webserver -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  if [ -z "${airflow_pod}" ]; then
    log_warning "Airflow webserver pod not found; skipping DAG sync"
    return 0
  fi

  if ! kubectl -n "${NAMESPACE}" wait --for=condition=Ready "pod/${airflow_pod}" --timeout=180s >/dev/null 2>&1; then
    log_warning "Airflow webserver pod ${airflow_pod} not ready; skipping DAG sync"
    return 0
  fi

  log_info "Syncing Airflow DAGs from ${dag_source} into shared PVC..."
  kubectl -n "${NAMESPACE}" exec "${airflow_pod}" -- sh -c 'set -euo pipefail; mkdir -p /opt/airflow/dags' >/dev/null 2>&1 || true

  kubectl -n "${NAMESPACE}" exec "${airflow_pod}" -- sh -c '
    set -euo pipefail
    if [ -f /opt/airflow/dags/.openlakes-managed ]; then
      while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        rm -f "/opt/airflow/dags/$rel" || true
      done < /opt/airflow/dags/.openlakes-managed
    fi
  ' >/dev/null 2>&1 || true

  if ! tar -C "${dag_source}" -cf - . | kubectl exec -i -n "${NAMESPACE}" "${airflow_pod}" -- tar -C /opt/airflow/dags -xf - >/dev/null 2>&1; then
    log_warning "Failed to copy DAG definitions into Airflow PVC"
    return 1
  fi

  local manifest_file
  manifest_file=$(mktemp)
  (cd "${dag_source}" && find . -type f -print | sed 's#^\./##') > "${manifest_file}"
  kubectl -n "${NAMESPACE}" cp "${manifest_file}" "${airflow_pod}:/opt/airflow/dags/.openlakes-managed" >/dev/null 2>&1 || true
  rm -f "${manifest_file}"

  kubectl -n "${NAMESPACE}" exec "${airflow_pod}" -- sh -c 'chown -R 50000:0 /opt/airflow/dags && chmod -R g+rwX /opt/airflow/dags' >/dev/null 2>&1 || true
  log_success "Airflow DAGs synced to PVC"
}

# Verify metrics-server is installed and running
verify_metrics_server() {
  log_info "Verifying metrics-server installation..."

  if [ "${DRY_RUN}" = "true" ]; then
    log_info "Would verify metrics-server is installed"
    return 0
  fi

  # Check if metrics-server deployment exists
  if ! kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; then
    log_warning "metrics-server not found in cluster"
    log_info "Installing metrics-server (required for resource metrics)..."

    # Install metrics-server using latest manifest
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml >/dev/null 2>&1

    # Wait for metrics-server to be ready
    log_info "Waiting for metrics-server to be ready..."
    kubectl wait --for=condition=available --timeout=60s deployment/metrics-server -n kube-system >/dev/null 2>&1 || {
      log_warning "metrics-server did not become ready within 60s (continuing anyway)"
      return 0
    }

    log_success "metrics-server installed successfully"
  else
    # Check if metrics-server is running
    local ready=$(kubectl get deployment metrics-server -n kube-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")

    if [ "$ready" -gt 0 ]; then
      log_success "metrics-server is already running"
    else
      log_warning "metrics-server is installed but not ready (continuing anyway)"
    fi
  fi

  return 0
}

# Get deployment status
get_deployment_status() {
  log_info "Checking deployment status..."
  echo ""

  local releases=$(helm list -n "${NAMESPACE}" -q 2>/dev/null || echo "")

  if [ -z "${releases}" ]; then
    log_warning "No Helm releases found in namespace '${NAMESPACE}'"
    return
  fi

  echo "Helm Releases:"
  helm list -n "${NAMESPACE}"
  echo ""

  echo "Pod Status:"
  kubectl get pods -n "${NAMESPACE}" --sort-by=.metadata.name | head -30
  echo ""

  echo "Service Endpoints (NodePort):"
  kubectl get services -n "${NAMESPACE}" -o custom-columns=\
NAME:.metadata.name,\
TYPE:.spec.type,\
PORTS:.spec.ports[*].port,\
NODEPORT:.spec.ports[*].nodePort \
    | grep NodePort || echo "No NodePort services found"
}

# Summarize pod health and fail fast if anything is not Running/Completed
summarize_pod_health() {
  log_info "Validating pod health in namespace '${NAMESPACE}'..."
  local -a not_ready=()
  mapfile -t not_ready < <(kubectl get pods -n "${NAMESPACE}" --no-headers 2>/dev/null | awk '{
    ready=$2; status=$3;
    split(ready,a,"/");
    if (status=="Completed" || status=="Succeeded") {next}
    if (a[1]!=a[2]) {printf "%s (ready %s, status %s)\n", $1, ready, status}
  }')

  if [ ${#not_ready[@]} -eq 0 ]; then
    log_success "All pods are Running or Completed in namespace '${NAMESPACE}'"
    return 0
  fi

  log_warning "Pods not ready yet; waiting up to 60s..."
  local end=$(( $(date +%s) + 60 ))
  while [ $(date +%s) -lt "${end}" ]; do
    sleep 5
    mapfile -t not_ready < <(kubectl get pods -n "${NAMESPACE}" --no-headers 2>/dev/null | awk '{
      ready=$2; status=$3;
      split(ready,a,"/");
      if (status=="Completed" || status=="Succeeded") {next}
      if (a[1]!=a[2]) {printf "%s (ready %s, status %s)\n", $1, ready, status}
    }')
    if [ ${#not_ready[@]} -eq 0 ]; then
      log_success "All pods are Running or Completed in namespace '${NAMESPACE}'"
      return 0
    fi
  done

  log_error "Found unhealthy pods:"
  printf '%s\n' "${not_ready[@]}"
  return 1
}

# Capture a CPU/memory snapshot (nodes + top pods) for diagnostics
capture_resource_snapshot() {
  if ! command_exists kubectl; then
    return 0
  fi

  if ! kubectl top nodes >/dev/null 2>&1; then
    log_warning "metrics-server not ready; skipping resource snapshot"
    return 0
  fi

  local snapshot_file="deploy-resource-snapshot-$(date +%Y%m%d%H%M%S).log"
  {
    echo "==== Resource Snapshot $(date -Iseconds) ===="
    echo "Nodes (CPU/memory):"
    kubectl top nodes || true
    echo
    echo "Top pods by CPU:"
    kubectl top pods -A --sort-by=cpu | head -n 40 || true
    echo
    echo "Top pods by Memory:"
    kubectl top pods -A --sort-by=memory | head -n 40 || true
  } > "${snapshot_file}" 2>/dev/null || true

  log_info "Captured resource snapshot -> ${snapshot_file}"
}

# ═══════════════════════════════════════════════════════════════
# Storage Configuration Wizard Functions
# ═══════════════════════════════════════════════════════════════

# Detect cluster nodes and storage capacity
detect_cluster_nodes() {
  log_info "Detecting cluster nodes and storage capacity..."

  # Get all nodes with details
  NODES_JSON=$(kubectl get nodes -o json)
  NODE_COUNT=$(echo "$NODES_JSON" | jq -r '.items | length')

  if [ "$NODE_COUNT" -le 1 ]; then
    log_info "Single-node cluster detected - multi-node storage configuration not needed"
    echo ""
    log_info "For single-node clusters, default storage configuration will be used:"
    log_info "  - Longhorn: Not recommended (single point of failure)"
    log_info "  - MinIO: Use single-node mode (no erasure coding)"
    log_info "  - Storage Class: local-path (default)"
    echo ""
    return 1
  fi

  log_success "Detected $NODE_COUNT nodes - multi-node cluster"

  # Parse node information
  local idx=0
  while IFS= read -r line; do
    NODE_NAMES[$idx]=$(echo "$line" | awk '{print $1}')
    NODE_ARCH[$idx]=$(echo "$line" | awk '{print $2}')
    local storage_bytes=$(echo "$line" | awk '{print $3}')

    # Convert bytes to GB (1GB = 1073741824 bytes)
    local storage_gb=$((storage_bytes / 1073741824))

    NODE_STORAGE_BYTES[$idx]=$storage_bytes
    NODE_STORAGE_GB[$idx]=$storage_gb

    idx=$((idx + 1))
  done < <(echo "$NODES_JSON" | jq -r '.items[] | "\(.metadata.name) \(.status.nodeInfo.architecture) \(.status.allocatable."ephemeral-storage" // "0")"')

  export NODE_COUNT NODE_NAMES NODE_ARCH NODE_STORAGE_BYTES NODE_STORAGE_GB
  return 0
}

# Display node information
display_nodes() {
  local show_remaining="${1:-false}"

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if [ "$show_remaining" = "true" ]; then
    printf "${BLUE}%-20s %-10s %-15s %-15s${NC}\n" "NODE" "ARCH" "TOTAL STORAGE" "REMAINING"
  else
    printf "${BLUE}%-20s %-10s %-15s${NC}\n" "NODE" "ARCH" "AVAILABLE STORAGE"
  fi

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  for ((i=0; i<NODE_COUNT; i++)); do
    local allocated="${NODE_ALLOCATED_GB[$i]:-0}"
    local remaining=$((NODE_STORAGE_GB[$i] - allocated))

    if [ "$show_remaining" = "true" ] && [ "$allocated" -gt 0 ]; then
      printf "%-20s %-10s %15s GB %15s GB\n" \
        "${NODE_NAMES[$i]}" \
        "${NODE_ARCH[$i]}" \
        "${NODE_STORAGE_GB[$i]}" \
        "${remaining}"
    else
      printf "%-20s %-10s %15s GB\n" \
        "${NODE_NAMES[$i]}" \
        "${NODE_ARCH[$i]}" \
        "${NODE_STORAGE_GB[$i]}"
    fi
  done

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
}

# Detect physical drives on a node
detect_node_drives() {
  local node_name="$1"

  log_info "Detecting physical drives on node: $node_name..."

  # Use kubectl debug to run lsblk on the node
  local drives_output
  drives_output=$(kubectl debug node/"$node_name" -it --image=busybox:latest -- \
    chroot /host lsblk -b -n -d -o NAME,SIZE,TYPE 2>/dev/null | grep "disk" || echo "")

  if [ -z "$drives_output" ]; then
    log_warning "Could not detect drives on $node_name (may require debug permissions)"
    return 1
  fi

  # Parse drive information: NAME SIZE TYPE
  # Convert SIZE from bytes to GB
  echo "$drives_output" | while read -r name size type; do
    local size_gb=$((size / 1073741824))
    echo "/dev/$name:${size_gb}GB"
  done
}

# Detect all drives across all nodes and populate global tracking
# ═══════════════════════════════════════════════════════════════
# Simplified Storage Configuration
# ═══════════════════════════════════════════════════════════════
# Uses fixed directory paths on all nodes:
# - /alluxio  - Alluxio cache (replicated across nodes)
# - /longhorn - Longhorn storage (mirrored across nodes)
# - /minio    - MinIO hot tier (erasure coded)
# - /cold     - MinIO cold tier (mirrored, compressed)

# Expected storage directories on all nodes
ALLUXIO_PATH="/alluxio"
LONGHORN_PATH="/longhorn"
MINIO_PATH="/minio"
COLD_PATH="/cold"

# Detect storage capacity across cluster nodes
detect_storage_capacity() {
  log_warning "Skipping storage capacity detection (host exec disabled)"
  return 0
  log_info "Detecting storage capacity across cluster nodes..."
  echo ""

  # Get all nodes
  local nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
  local node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')

  if [ -z "$nodes" ] || [ "$node_count" -lt 1 ]; then
    log_error "Cannot detect cluster nodes. Is kubectl configured correctly?"
    exit 1
  fi

  if [ "$node_count" -lt 2 ]; then
    log_warning "OpenLakes is optimized for 2+ nodes for redundancy"
    log_warning "Current nodes: $node_count"
    log_warning "Continuing with single-node configuration..."
  fi

  log_success "Found $node_count nodes: $nodes"
  echo ""

  # Track sizes per node per directory for validation
  declare -A alluxio_sizes
  declare -A longhorn_sizes
  declare -A minio_sizes
  declare -A cold_sizes

  local total_alluxio=0
  local total_longhorn=0
  local total_minio=0
  local total_cold=0

  local missing_dirs=""
  local has_errors=false

  for node in $nodes; do
    log_info "Checking storage on node: $node"

    # Check each directory using df
    for dir in "$ALLUXIO_PATH" "$LONGHORN_PATH" "$MINIO_PATH" "$COLD_PATH"; do
      # Try to get available space (in GB)
      local size=$(kubectl debug node/$node -it --image=busybox -- sh -c "df -BG '$dir' 2>/dev/null | awk 'NR==2 {print \$4}'" 2>/dev/null | sed 's/G$//' | tr -d '\r' || echo "0")

      # Clean up and validate
      size=$(echo "$size" | tr -cd '0-9' | head -c 10)
      size=${size:-0}

      # Store per-node sizes
      case "$dir" in
        "$ALLUXIO_PATH")
          alluxio_sizes[$node]=$size
          total_alluxio=$((total_alluxio + size))
          ;;
        "$LONGHORN_PATH")
          longhorn_sizes[$node]=$size
          total_longhorn=$((total_longhorn + size))
          ;;
        "$MINIO_PATH")
          minio_sizes[$node]=$size
          total_minio=$((total_minio + size))
          ;;
        "$COLD_PATH")
          cold_sizes[$node]=$size
          total_cold=$((total_cold + size))
          ;;
      esac

      if [ "$size" -gt 0 ]; then
        echo "  ✓ $dir: ${size}GB available"
      else
        log_error "  ✗ $dir: NOT FOUND or empty on $node"
        missing_dirs="$missing_dirs\n  - $node:$dir"
        has_errors=true
      fi
    done
    echo ""
  done

  # Validate: All required directories must exist on all nodes
  if [ "$has_errors" = true ]; then
    echo ""
    log_error "╔════════════════════════════════════════════════════════════╗"
    log_error "║  MISSING STORAGE DIRECTORIES DETECTED                     ║"
    log_error "╚════════════════════════════════════════════════════════════╝"
    echo ""
    log_error "The following directories are missing or empty:"
    echo -e "$missing_dirs"
    echo ""
    log_error "OpenLakes requires these directories on ALL nodes:"
    log_error "  - $ALLUXIO_PATH  (Alluxio cache)"
    log_error "  - $LONGHORN_PATH (Longhorn block storage)"
    log_error "  - $MINIO_PATH    (MinIO hot tier)"
    log_error "  - $COLD_PATH     (MinIO cold tier)"
    echo ""
    log_error "Please create the missing directories on each node:"
    log_error "  sudo mkdir -p $ALLUXIO_PATH $LONGHORN_PATH $MINIO_PATH $COLD_PATH"
    log_error "  sudo chown -R 1000:1000 $ALLUXIO_PATH $LONGHORN_PATH $MINIO_PATH $COLD_PATH"
    echo ""
    exit 1
  fi

  # Validate: Check for size consistency across nodes (warn if >20% variance)
  echo ""
  log_info "Validating storage consistency across nodes..."
  echo ""

  check_size_consistency() {
    local dir_name=$1
    shift
    local -n sizes=$1

    local min_size=999999
    local max_size=0

    for node in "${!sizes[@]}"; do
      local size=${sizes[$node]}
      [ $size -gt 0 ] && [ $size -lt $min_size ] && min_size=$size
      [ $size -gt $max_size ] && max_size=$size
    done

    if [ $max_size -gt 0 ] && [ $min_size -lt 999999 ]; then
      local variance=$(( (max_size - min_size) * 100 / max_size ))

      if [ $variance -gt 5 ]; then
        log_error "  ✗ $dir_name: Size varies by ${variance}% across nodes (${min_size}GB - ${max_size}GB)"
        log_error "    Maximum allowed variance is 5%"
        return 1
      else
        log_success "  ✓ $dir_name: Consistent sizing (${min_size}GB - ${max_size}GB, ${variance}% variance)"
        return 0
      fi
    fi
  }

  local consistency_errors=false

  check_size_consistency "Alluxio  " alluxio_sizes || consistency_errors=true
  check_size_consistency "Longhorn " longhorn_sizes || consistency_errors=true
  check_size_consistency "MinIO Hot" minio_sizes || consistency_errors=true
  check_size_consistency "MinIO Cold" cold_sizes || consistency_errors=true

  if [ "$consistency_errors" = true ]; then
    echo ""
    log_error "╔════════════════════════════════════════════════════════════╗"
    log_error "║  STORAGE SIZE MISMATCH DETECTED                           ║"
    log_error "╚════════════════════════════════════════════════════════════╝"
    echo ""
    log_error "Storage directory sizes vary by more than 5% across nodes."
    log_error "Please ensure storage sizes are consistent across all nodes."
    echo ""
    exit 1
  fi

  echo ""

  # Export totals
  export NODE_COUNT=$node_count
  export TOTAL_ALLUXIO_GB=$total_alluxio
  export TOTAL_LONGHORN_GB=$total_longhorn
  export TOTAL_MINIO_GB=$total_minio
  export TOTAL_COLD_GB=$total_cold

  return 0
}

# Show storage summary and get confirmation
show_storage_summary() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║                                                            ║"
  echo "║           OpenLakes Storage Configuration                 ║"
  echo "║                                                            ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo ""

  log_info "Cluster: $NODE_COUNT nodes"
  echo ""

  # Calculate effective capacities based on redundancy
  local alluxio_effective=$TOTAL_ALLUXIO_GB
  local longhorn_effective=$((TOTAL_LONGHORN_GB / 2))  # Mirrored (2x redundancy)
  local minio_effective=$((TOTAL_MINIO_GB / 2))        # Erasure (2:2, 50% overhead)
  local cold_effective=$((TOTAL_COLD_GB / 2))          # Mirrored

  if [ "$NODE_COUNT" -gt 1 ]; then
    alluxio_effective=$((TOTAL_ALLUXIO_GB / NODE_COUNT))  # Replicated
  fi

  echo "┌─────────────────────────────────────────────────────────────┐"
  echo "│ Service   │ Raw Storage │ Redundancy   │ Usable Storage   │"
  echo "├─────────────────────────────────────────────────────────────┤"
  printf "│ %-9s │ %8s GB │ %-12s │ %13s GB │\n" "Alluxio" "$TOTAL_ALLUXIO_GB" "Replicated" "$alluxio_effective"
  printf "│ %-9s │ %8s GB │ %-12s │ %13s GB │\n" "Longhorn" "$TOTAL_LONGHORN_GB" "Mirrored" "$longhorn_effective"
  printf "│ %-9s │ %8s GB │ %-12s │ %13s GB │\n" "MinIO Hot" "$TOTAL_MINIO_GB" "Erasure 2:2" "$minio_effective"
  printf "│ %-9s │ %8s GB │ %-12s │ %13s GB │\n" "MinIO Cold" "$TOTAL_COLD_GB" "Mirrored" "$cold_effective"
  echo "└─────────────────────────────────────────────────────────────┘"
  echo ""

  echo "Redundancy Details:"
  echo ""
  echo "  • Alluxio Cache:"
  echo "    - Full replication across all $NODE_COUNT nodes"
  echo "    - Same cache data available on every node"
  if [ "$NODE_COUNT" -gt 1 ]; then
    echo "    - No data loss if $(($NODE_COUNT - 1)) node(s) fail"
  fi
  echo "    - Path: $ALLUXIO_PATH on each node"
  echo ""
  echo "  • Longhorn Block Storage:"
  echo "    - 2-way mirroring (replica count = 2)"
  echo "    - No data loss if 1 node fails"
  echo "    - 50% storage efficiency"
  echo "    - Path: $LONGHORN_PATH on each node"
  echo ""
  echo "  • MinIO Object Storage (Hot Tier):"
  echo "    - Erasure coding: EC:2 (2 data + 2 parity shards)"
  echo "    - No data loss if up to 2 nodes fail"
  echo "    - 50% storage efficiency"
  echo "    - Path: $MINIO_PATH on each node"
  echo ""
  echo "  • MinIO Object Storage (Cold Tier):"
  echo "    - Mirrored across nodes for safety"
  echo "    - Maximum compression enabled"
  echo "    - Auto-tiering: Data moves to cold after 30 days of no access"
  echo "    - Path: $COLD_PATH on each node"
  echo ""

  # Skip confirmation if in non-interactive mode
  if [ "${DRY_RUN}" = "true" ] || [ ! -t 0 ]; then
    log_info "Non-interactive mode detected, proceeding with deployment"
    return 0
  fi

  # Confirmation
  read -p "Deploy OpenLakes with this configuration? (yes/no): " confirm
  if [[ "$confirm" != "yes" ]]; then
    log_warning "Deployment cancelled by user"
    exit 0
  fi

  log_success "Configuration confirmed!"
  echo ""
  return 0
}

# Generate Helm values for simplified storage
generate_simplified_storage_values() {
  local output_file="/tmp/openlakes-storage-config.yaml"

  cat > "$output_file" <<EOF
# OpenLakes Simplified Storage Configuration
# Generated: $(date)
#
# Fixed paths on all nodes:
# - $ALLUXIO_PATH  (cache, replicated)
# - $LONGHORN_PATH (block storage, mirrored)
# - $MINIO_PATH    (object storage hot, erasure coded)
# - $COLD_PATH     (object storage cold, mirrored + compressed)

global:
  storageClass: longhorn
  namespace: openlakes

# ═══════════════════════════════════════════════════════════════
# Longhorn - Distributed Block Storage
# ═══════════════════════════════════════════════════════════════
longhorn:
  enabled: true

  defaultSettings:
    defaultDataPath: $LONGHORN_PATH
    defaultReplicaCount: 2  # Full mirror across nodes
    storageMinimalAvailablePercentage: 10
    guaranteedInstanceManagerCPU: 0
    storageOverProvisioningPercentage: 100

  persistence:
    defaultClass: true
    defaultClassReplicaCount: 2
    reclaimPolicy: Retain

  ingress:
    enabled: true
    host: longhorn.openlakes.local
    ingressClassName: traefik

# ═══════════════════════════════════════════════════════════════
# Alluxio - Distributed Caching Layer
# ═══════════════════════════════════════════════════════════════
alluxio:
  enabled: true

  # Replication across all nodes
  properties:
    alluxio.user.file.replication.min: "$NODE_COUNT"
    alluxio.user.file.replication.max: "$NODE_COUNT"

  # Tiered storage using $ALLUXIO_PATH
  tieredstore:
    levels:
    - level: 0
      alias: MEM
      mediumtype: MEM
      path: /dev/shm
      type: emptyDir
      quota: 1Gi
      high: 0.95
      low: 0.7
    - level: 1
      alias: SSD
      mediumtype: SSD
      path: $ALLUXIO_PATH
      type: hostPath
      quota: $(($TOTAL_ALLUXIO_GB > 0 && $NODE_COUNT > 0 ? $TOTAL_ALLUXIO_GB / $NODE_COUNT : 10))Gi
      high: 0.95
      low: 0.7

# ═══════════════════════════════════════════════════════════════
# MinIO - Distributed Object Storage
# ═══════════════════════════════════════════════════════════════
minio:
  enabled: true
  mode: distributed
  replicas: $(($NODE_COUNT >= 4 ? 4 : $NODE_COUNT * 2))

  # Hot tier storage using $MINIO_PATH
  # Uses custom StorageClass 'minio-hot' with pre-created PVs
  persistence:
    enabled: true
    storageClass: minio-hot
    size: $(($TOTAL_MINIO_GB > 0 && $NODE_COUNT > 0 ? $TOTAL_MINIO_GB / $NODE_COUNT : 100))Gi

  # Erasure coding configuration
  drivesPerNode: 1

  # Environment variables for compression and cold tier
  environment:
    MINIO_COMPRESSION_ENABLE: "on"
    MINIO_COMPRESSION_EXTENSIONS: ".txt,.log,.csv,.json,.xml,.parquet,.orc,.avro"
    MINIO_COMPRESSION_MIME_TYPES: "text/*,application/json,application/xml"

# NOTE: MinIO cold tier configuration
# Cold tier uses separate PVs (minio-cold StorageClass) and is configured
# via MinIO lifecycle policies after deployment. The /cold directory will be
# used for data that hasn't been accessed in 30+ days, with maximum compression

EOF

  log_success "Generated storage configuration: $output_file"
  export STORAGE_CONFIG="$output_file"
  return 0
}

# Discover mounts on a node
discover_node_mounts() {
  local node=$1
  local pod_name="mount-discover-${node}"

  # Clean up any existing pod
  kubectl delete pod -n default ${pod_name} --ignore-not-found=true >/dev/null 2>&1

  # Create discovery pod
  cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: ${pod_name}
  namespace: default
  labels:
    app: mount-discover
spec:
  nodeSelector:
    kubernetes.io/hostname: ${node}
  hostNetwork: true
  hostPID: true
  containers:
  - name: discoverer
    image: alpine:latest
    command: ["/bin/sh", "-c", "nsenter -t 1 -m -u -i -n df -BG -x tmpfs -x devtmpfs 2>/dev/null | grep '^/'"]
    securityContext:
      privileged: true
  restartPolicy: Never
EOF

  # Wait for pod to complete
  kubectl wait --for=condition=Ready pod/${pod_name} -n default --timeout=15s >/dev/null 2>&1 || true
  sleep 2

  # Get mount info
  local mounts=$(kubectl logs ${pod_name} -n default 2>/dev/null || echo "")

  # Clean up
  kubectl delete pod -n default ${pod_name} --ignore-not-found=true >/dev/null 2>&1

  echo "$mounts"
}

# Interactive storage configuration wizard
run_storage_configuration() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║    OpenLakes Interactive Storage Configuration Wizard     ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo ""

  # Get all nodes
  local nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
  local node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')

  if [ "$node_count" -lt 1 ]; then
    log_error "Failed to detect cluster nodes. Is kubectl configured?"
    return 1
  fi

  log_info "Detected $node_count node(s): $nodes"
  echo ""

  # Storage assignments
  declare -A node_alluxio_path
  declare -A node_alluxio_size
  declare -A node_longhorn_path
  declare -A node_longhorn_size
  declare -A node_cold_path
  declare -A node_cold_size
  declare -a minio_drives
  declare -a minio_nodes
  declare -a minio_sizes

  # Discover and configure storage for each node
  for node in $nodes; do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Discovering storage on node: $node"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    log_info "Scanning mount points..."
    local mounts=$(discover_node_mounts "$node")

    if [ -z "$mounts" ]; then
      log_error "Failed to discover mounts on $node"
      continue
    fi

    echo ""
    echo "Available mount points on $node:"
    echo ""
    printf "%-30s %10s %10s %10s\n" "MOUNT POINT" "SIZE" "USED" "AVAILABLE"
    echo "────────────────────────────────────────────────────────────"
    echo "$mounts" | while read line; do
      filesystem=$(echo "$line" | awk '{print $1}')
      size=$(echo "$line" | awk '{print $2}')
      used=$(echo "$line" | awk '{print $3}')
      avail=$(echo "$line" | awk '{print $4}')
      mount=$(echo "$line" | awk '{print $6}')
      printf "%-30s %10s %10s %10s\n" "$mount" "$size" "$used" "$avail"
    done
    echo ""

    # Ask for Alluxio path
    read -p "Enter mount point for Alluxio cache on $node (e.g., /alluxio): " alluxio_input
    if [ -n "$alluxio_input" ]; then
      local alluxio_size=$(echo "$mounts" | grep " ${alluxio_input}\$" | awk '{print $4}' | sed 's/G$//' | tr -cd '0-9')
      if [ -n "$alluxio_size" ] && [ "$alluxio_size" -gt 0 ]; then
        node_alluxio_path[$node]="$alluxio_input"
        node_alluxio_size[$node]="$alluxio_size"
        log_success "Alluxio: $alluxio_input (${alluxio_size}GB available)"
      else
        log_warning "Could not determine size for $alluxio_input, skipping"
      fi
    fi
    echo ""

    # Ask for Longhorn path
    read -p "Enter mount point for Longhorn storage on $node (e.g., /longhorn): " longhorn_input
    if [ -n "$longhorn_input" ]; then
      local longhorn_size=$(echo "$mounts" | grep " ${longhorn_input}\$" | awk '{print $4}' | sed 's/G$//' | tr -cd '0-9')
      if [ -n "$longhorn_size" ] && [ "$longhorn_size" -gt 0 ]; then
        node_longhorn_path[$node]="$longhorn_input"
        node_longhorn_size[$node]="$longhorn_size"
        log_success "Longhorn: $longhorn_input (${longhorn_size}GB available)"
      else
        log_warning "Could not determine size for $longhorn_input, skipping"
      fi
    fi
    echo ""

    # Ask for MinIO hot tier drives (can be multiple per node)
    log_info "MinIO distributed mode requires at least 4 drives total across all nodes"
    log_info "You can assign multiple drives per node (e.g., /minio1, /minio2)"
    echo ""

    local drive_num=1
    while true; do
      read -p "Enter MinIO hot tier drive #$drive_num on $node (or press Enter to finish): " minio_input
      if [ -z "$minio_input" ]; then
        break
      fi

      local minio_size=$(echo "$mounts" | grep " ${minio_input}\$" | awk '{print $4}' | sed 's/G$//' | tr -cd '0-9')
      if [ -n "$minio_size" ] && [ "$minio_size" -gt 0 ]; then
        minio_drives+=("$minio_input")
        minio_nodes+=("$node")
        minio_sizes+=("$minio_size")
        log_success "MinIO drive $drive_num: $minio_input (${minio_size}GB available)"
        drive_num=$((drive_num + 1))
      else
        log_warning "Could not determine size for $minio_input, skipping"
      fi
    done
    echo ""

    # Ask for Cold tier path
    read -p "Enter mount point for MinIO cold tier on $node (e.g., /cold): " cold_input
    if [ -n "$cold_input" ]; then
      local cold_size=$(echo "$mounts" | grep " ${cold_input}\$" | awk '{print $4}' | sed 's/G$//' | tr -cd '0-9')
      if [ -n "$cold_size" ] && [ "$cold_size" -gt 0 ]; then
        node_cold_path[$node]="$cold_input"
        node_cold_size[$node]="$cold_size"
        log_success "Cold tier: $cold_input (${cold_size}GB available)"
      else
        log_warning "Could not determine size for $cold_input, skipping"
      fi
    fi
    echo ""
  done

  # Clean up discovery pods
  kubectl delete pod -n default -l app=mount-discover --ignore-not-found=true >/dev/null 2>&1

  # Validate MinIO drive count
  local total_minio_drives=${#minio_drives[@]}
  if [ "$total_minio_drives" -lt 4 ]; then
    echo ""
    log_error "MinIO distributed mode requires at least 4 drives"
    log_error "You only assigned $total_minio_drives drive(s)"
    log_error "Please re-run the wizard and assign at least 4 drives total"
    return 1
  fi

  echo ""
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║              Configuration Summary                         ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo ""

  # Display summary
  for node in $nodes; do
    echo "Node: $node"
    if [ -n "${node_alluxio_path[$node]}" ]; then
      echo "  Alluxio:  ${node_alluxio_path[$node]} (${node_alluxio_size[$node]}GB)"
    fi
    if [ -n "${node_longhorn_path[$node]}" ]; then
      echo "  Longhorn: ${node_longhorn_path[$node]} (${node_longhorn_size[$node]}GB)"
    fi
    if [ -n "${node_cold_path[$node]}" ]; then
      echo "  Cold:     ${node_cold_path[$node]} (${node_cold_size[$node]}GB)"
    fi
    echo ""
  done

  echo "MinIO Hot Tier Drives (Distributed):"
  local total_minio_capacity=0
  for i in "${!minio_drives[@]}"; do
    echo "  Drive $((i+1)): ${minio_nodes[$i]}:${minio_drives[$i]} (${minio_sizes[$i]}GB)"
    total_minio_capacity=$((total_minio_capacity + ${minio_sizes[$i]}))
  done
  echo "  Total: ${total_minio_capacity}GB across $total_minio_drives drives"
  echo ""

  # Calculate totals
  local total_alluxio=0
  local total_longhorn=0
  local total_cold=0
  for node in $nodes; do
    total_alluxio=$((total_alluxio + ${node_alluxio_size[$node]:-0}))
    total_longhorn=$((total_longhorn + ${node_longhorn_size[$node]:-0}))
    total_cold=$((total_cold + ${node_cold_size[$node]:-0}))
  done

  echo "Cluster Totals:"
  echo "  Alluxio Cache:   ${total_alluxio}GB"
  echo "  Longhorn Storage: ${total_longhorn}GB"
  echo "  MinIO Hot:        ${total_minio_capacity}GB (${total_minio_drives} drives)"
  echo "  MinIO Cold:       ${total_cold}GB"
  echo ""

  # Generate topology YAML
  local output_file=".openlakes-storage-config.yaml"
  log_info "Generating storage configuration: $output_file"

  cat > "$output_file" <<EOF
# OpenLakes Storage Configuration - Auto-Generated
# Generated: $(date)

global:
  storageClass: longhorn
  namespace: openlakes

# Temporarily disable Schema Registry pending fix for leader election
schemaRegistry:
  enabled: true

longhorn:
  enabled: true
  defaultSettings:
    defaultDataPath: ${node_longhorn_path[$(echo $nodes | awk '{print $1}')]}
    defaultReplicaCount: 2
    storageMinimalAvailablePercentage: 10
    guaranteedInstanceManagerCPU: 0
    storageOverProvisioningPercentage: 100
  persistence:
    defaultClass: true
    defaultClassReplicaCount: 2
    reclaimPolicy: Retain
  ingress:
    enabled: true
    host: longhorn.openlakes.local
    ingressClassName: traefik

alluxio:
  enabled: true
  properties:
    alluxio.user.file.replication.min: "2"
    alluxio.user.file.replication.max: "2"
  tieredstore:
    levels:
    - level: 0
      alias: MEM
      mediumtype: MEM
      path: /dev/shm
      type: emptyDir
      quota: 1Gi
      high: 0.95
      low: 0.7
    - level: 1
      alias: SSD
      mediumtype: SSD
      path: ${node_alluxio_path[$(echo $nodes | awk '{print $1}')]}
      type: hostPath
      quota: ${node_alluxio_size[$(echo $nodes | awk '{print $1}')]}Gi
      high: 0.95
      low: 0.7

minio:
  enabled: true
  mode: distributed
  replicas: $total_minio_drives
  persistence:
    enabled: true
    storageClass: minio-hot
    size: ${minio_sizes[0]}Gi
  environment:
    MINIO_COMPRESSION_ENABLE: "on"
    MINIO_COMPRESSION_EXTENSIONS: ".txt,.log,.csv,.json,.xml,.parquet,.orc,.avro"
    MINIO_COMPRESSION_MIME_TYPES: "text/*,application/json,application/xml"
  topology:
    nodes:
EOF

  # Generate topology nodes section
  declare -A node_drives_written
  for i in "${!minio_drives[@]}"; do
    local node="${minio_nodes[$i]}"
    local drive="${minio_drives[$i]}"
    local size="${minio_sizes[$i]}"

    # Check if we've started this node's section
    if [ -z "${node_drives_written[$node]}" ]; then
      cat >> "$output_file" <<EOF
      - name: $node
        drives:
EOF
      node_drives_written[$node]=1
    fi

    # Add this drive
    cat >> "$output_file" <<EOF
          - path: $drive
            size: ${size}Gi
            storageClass: minio-hot
EOF
  done

  # Add cold tier configuration
  cat >> "$output_file" <<EOF

# MinIO Cold Tier Configuration
# Cold storage with maximum compression for long-term data archival
coldTier:
  enabled: true
  compression: max
  lifecycle:
    transitionDays: 30  # Move objects to cold tier after 30 days of no access
  persistence:
    storageClass: minio-cold
EOF

  # Add cold tier paths per node
  for node in $nodes; do
    if [ -n "${node_cold_path[$node]}" ]; then
      cat >> "$output_file" <<EOF
    ${node}:
      path: ${node_cold_path[$node]}
      size: ${node_cold_size[$node]}Gi
EOF
    fi
  done

  log_success "Configuration generated successfully!"
  echo ""
  log_info "Configuration saved to: $output_file"
  echo ""

  # Show what will happen
  log_info "This configuration will deploy:"
  echo "  • Longhorn distributed storage with 2-way replication"
  echo "  • Alluxio distributed caching using full capacity of assigned mounts"
  echo "  • MinIO distributed mode with $total_minio_drives drives (erasure coded)"
  echo "  • MinIO cold tier with maximum compression"
  echo ""

  read -p "Proceed with deployment using this configuration? (y/N): " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log_warning "Deployment cancelled by user"
    return 1
  fi

  export STORAGE_CONFIG="$output_file"
  return 0
}

# ═══════════════════════════════════════════════════════════════
# MinIO Multi-Drive Topology Support
# ═══════════════════════════════════════════════════════════════
# Supports multiple drives per node for distributed MinIO deployments
# Validates topology meets MinIO's distributed mode requirements (min 4 drives)

# Validate MinIO topology configuration
validate_minio_topology() {
  local storage_config="$1"

  # Check if yq is available
  if ! command_exists yq; then
    log_error "yq is required for topology validation but not installed"
    return 1
  fi

  # Check if topology is defined in storage config
  if ! yq eval '.minio.topology.nodes' "$storage_config" &>/dev/null; then
    log_error "MinIO topology not defined in storage configuration"
    log_info "For distributed MinIO, specify drive topology in your storage config:"
    log_info "  minio.topology.nodes[].name (node name)"
    log_info "  minio.topology.nodes[].drives[].path (mount path)"
    log_info "  minio.topology.nodes[].drives[].size (PV size)"
    return 1
  fi

  # Count total drives across all nodes
  local total_drives=0
  local node_count=$(yq eval '.minio.topology.nodes | length' "$storage_config")

  for ((i=0; i<node_count; i++)); do
    local node_name=$(yq eval ".minio.topology.nodes[$i].name" "$storage_config")
    local drive_count=$(yq eval ".minio.topology.nodes[$i].drives | length" "$storage_config")
    total_drives=$((total_drives + drive_count))

    log_info "Node '$node_name': $drive_count drive(s)"

    # Verify node exists in cluster
    if ! kubectl get node "$node_name" &>/dev/null; then
      log_error "Node '$node_name' not found in cluster"
      return 1
    fi
  done

  # Validate MinIO distributed mode requirements
  local minio_replicas=$(yq eval '.minio.replicas' "$storage_config")

  if [ "$total_drives" -lt 4 ]; then
    log_error "MinIO distributed mode requires at least 4 drives"
    log_error "Current configuration has $total_drives drive(s)"
    log_info "Valid configurations: 4×1, 2×2, 3×2, 4×2, etc."
    return 1
  fi

  if [ "$total_drives" -ne "$minio_replicas" ]; then
    log_error "Mismatch: minio.replicas=$minio_replicas but topology defines $total_drives drives"
    log_info "Set minio.replicas=$total_drives to match your drive topology"
    return 1
  fi

  log_success "MinIO topology validated: $total_drives drives across $node_count node(s)"
  return 0
}

# Release PVs that are in Released state (from old deployments)
release_old_pvs() {
  log_info "Checking for Released PVs that need to be made Available..."

  local released_pvs=$(kubectl get pv -o json | jq -r '.items[] | select(.status.phase=="Released" and (.spec.storageClassName=="minio-hot" or .spec.storageClassName=="minio-cold")) | .metadata.name')

  if [ -z "$released_pvs" ]; then
    log_info "No Released PVs found - skipping"
    return 0
  fi

  local count=0
  while IFS= read -r pv; do
    if [ -n "$pv" ]; then
      log_info "Releasing PV: $pv"
      kubectl patch pv "$pv" -p '{"spec":{"claimRef": null}}' >/dev/null 2>&1
      count=$((count + 1))
    fi
  done <<< "$released_pvs"

  log_success "Released $count PV(s) - now Available for binding"
  echo ""
}

# Clean old MinIO metadata from drives
clean_minio_data() {
  local storage_config="$1"

  log_warning "═══════════════════════════════════════════════════════════"
  log_warning "MinIO Data Cleanup Required"
  log_warning "═══════════════════════════════════════════════════════════"
  echo ""
  log_warning "Re-deployment detected. Old MinIO metadata can cause 'inconsistent drive' errors."
  log_warning "All data in MinIO drives will be DELETED."
  echo ""

  read -p "Clean MinIO data directories before re-deployment? (y/N): " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log_info "Skipping data cleanup - proceeding with existing data"
    echo ""
    return 0
  fi

  log_info "Cleaning MinIO data directories..."
  echo ""

  # Get topology configuration
  local node_count=$(yq eval '.minio.topology.nodes | length' "$storage_config")

  # Clean up any existing cleanup pods
  kubectl delete pod -n default -l app=minio-cleanup --ignore-not-found=true >/dev/null 2>&1

  # Create cleanup pods for each drive
  for ((i=0; i<node_count; i++)); do
    local node_name=$(yq eval ".minio.topology.nodes[$i].name" "$storage_config")
    local drive_count=$(yq eval ".minio.topology.nodes[$i].drives | length" "$storage_config")

    for ((j=0; j<drive_count; j++)); do
      local drive_path=$(yq eval ".minio.topology.nodes[$i].drives[$j].path" "$storage_config")
      local pod_name="cleanup-minio-${node_name}-${j}"

      log_info "Creating cleanup pod for ${node_name}:${drive_path}"

      cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: ${pod_name}
  namespace: default
  labels:
    app: minio-cleanup
    node: ${node_name}
spec:
  nodeSelector:
    kubernetes.io/hostname: ${node_name}
  hostNetwork: true
  hostPID: true
  containers:
  - name: cleaner
    image: alpine:latest
    command: ["/bin/sh", "-c", "nsenter -t 1 -m -u -i -n rm -rf ${drive_path}/.minio.sys ${drive_path}/* && echo 'Cleaned ${drive_path}'"]
    securityContext:
      privileged: true
  restartPolicy: Never
EOF
    done
  done

  # Wait for cleanup to complete
  log_info "Waiting for cleanup to complete..."
  sleep 5

  local cleanup_pods=$(kubectl get pods -n default -l app=minio-cleanup --no-headers | wc -l | tr -d ' ')
  kubectl wait --for=condition=Ready pod -l app=minio-cleanup -n default --timeout=30s >/dev/null 2>&1 || true
  sleep 3

  # Verify cleanup
  local completed=$(kubectl get pods -n default -l app=minio-cleanup --no-headers 2>/dev/null | grep -c Completed || echo 0)
  log_success "Cleaned $completed drive(s)"

  # Clean up cleanup pods
  kubectl delete pod -n default -l app=minio-cleanup --ignore-not-found=true >/dev/null 2>&1

  echo ""
}

# Create MinIO PVs from topology configuration
create_minio_pvs_from_topology() {
  local storage_config="$1"

  log_info "═══════════════════════════════════════════════════════════"
  log_info "Creating MinIO Storage Volumes from Topology"
  log_info "═══════════════════════════════════════════════════════════"

  # Check if MinIO is already deployed
  if kubectl get statefulset -n openlakes infrastructure-minio >/dev/null 2>&1; then
    log_warning "MinIO StatefulSet already exists - re-deployment detected"
    echo ""

    # Offer to clean old data
    clean_minio_data "$storage_config"

    # Release old PVs
    release_old_pvs
  fi

  # Create StorageClasses first
  log_info "Creating MinIO StorageClasses..."
  cat <<'EOF' | kubectl apply -f - >/dev/null 2>&1
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: minio-hot
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: minio-cold
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
EOF
  log_success "Created StorageClasses: minio-hot, minio-cold"
  echo ""

  # Validate topology first
  if ! validate_minio_topology "$storage_config"; then
    log_error "MinIO topology validation failed"
    return 1
  fi

  local node_count=$(yq eval '.minio.topology.nodes | length' "$storage_config")
  local pv_index=0
  local pv_manifest="/tmp/openlakes-minio-topology-pvs.yaml"

  # Generate PV manifest header
  cat > "$pv_manifest" <<'EOF_HEADER'
# MinIO PersistentVolumes - Generated from Topology Configuration
# Each PV corresponds to a specific drive on a specific node
---
EOF_HEADER

  # Generate PVs for each drive in topology
  for ((i=0; i<node_count; i++)); do
    local node_name=$(yq eval ".minio.topology.nodes[$i].name" "$storage_config")
    local drive_count=$(yq eval ".minio.topology.nodes[$i].drives | length" "$storage_config")

    for ((j=0; j<drive_count; j++)); do
      local drive_path=$(yq eval ".minio.topology.nodes[$i].drives[$j].path" "$storage_config")
      local drive_size=$(yq eval ".minio.topology.nodes[$i].drives[$j].size" "$storage_config")

      log_info "Creating PV #$pv_index: ${node_name}:${drive_path} (${drive_size})"

      # Create PV manifest
      cat >> "$pv_manifest" <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: minio-hot-pv-${pv_index}
  labels:
    type: local
    app: minio
    tier: hot
    node: ${node_name}
    drive-index: "${pv_index}"
spec:
  capacity:
    storage: ${drive_size}
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: minio-hot
  hostPath:
    path: ${drive_path}
    type: DirectoryOrCreate
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - ${node_name}
---
EOF

      pv_index=$((pv_index + 1))
    done
  done

  # Apply PV manifests
  if [ "${DRY_RUN}" != "true" ]; then
    log_info "Applying MinIO PersistentVolume manifests..."
    if kubectl apply -f "$pv_manifest"; then
      log_success "Created $pv_index MinIO PVs from topology"

      # Show created PVs
      echo ""
      log_info "MinIO PersistentVolumes:"
      kubectl get pv -l app=minio --sort-by=.metadata.name | grep minio-hot || true
      echo ""
    else
      log_error "Failed to create MinIO PersistentVolumes"
      return 1
    fi
  else
    log_info "Would create PVs from: $pv_manifest"
    log_info "Preview of PV manifest:"
    head -50 "$pv_manifest"
  fi

  return 0
}

# Interactive MinIO topology configuration wizard
configure_minio_topology_interactive() {
  echo ""
  log_info "═══════════════════════════════════════════════════════════"
  log_info "MinIO Drive Topology Configuration"
  log_info "═══════════════════════════════════════════════════════════"
  echo ""

  # Get available nodes
  local nodes=($(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'))
  local node_count=${#nodes[@]}

  log_info "Available nodes: ${nodes[*]}"
  echo ""

  # Initialize topology configuration
  local topology_file="/tmp/minio-topology.yaml"
  cat > "$topology_file" <<EOF
# MinIO Topology Configuration
# Generated: $(date)

minio:
  enabled: true
  mode: distributed
  replicas: 0  # Will be updated based on total drives
  persistence:
    enabled: true
    storageClass: minio-hot

  topology:
    nodes:
EOF

  local total_drives=0

  # Configure drives for each node
  for node in "${nodes[@]}"; do
    echo ""
    echo -e "${BLUE}Configuring node: $node${NC}"

    while true; do
      read -p "How many drives on node '$node'? (0-4): " drive_count
      if [[ "$drive_count" =~ ^[0-4]$ ]]; then
        break
      fi
      log_error "Please enter a number between 0 and 4"
    done

    if [ "$drive_count" -eq 0 ]; then
      log_warning "Skipping node '$node' (no drives configured)"
      continue
    fi

    # Add node to topology
    cat >> "$topology_file" <<EOF
      - name: $node
        drives:
EOF

    for ((i=1; i<=drive_count; i++)); do
      echo ""
      read -p "  Drive $i path on $node (e.g., /minio$i): " drive_path

      while true; do
        read -p "  Drive $i size (e.g., 400Gi): " drive_size
        if [[ "$drive_size" =~ ^[0-9]+Gi$ ]]; then
          break
        fi
        log_error "Please enter size in format: <number>Gi (e.g., 400Gi)"
      done

      cat >> "$topology_file" <<EOF
          - path: $drive_path
            size: $drive_size
EOF

      total_drives=$((total_drives + 1))
      log_success "  Configured ${node}:${drive_path} (${drive_size})"
    done
  done

  echo ""

  # Validate minimum drive count
  if [ "$total_drives" -lt 4 ]; then
    echo ""
    log_error "╔════════════════════════════════════════════════════════════╗"
    log_error "║  INSUFFICIENT DRIVES FOR DISTRIBUTED MODE                 ║"
    log_error "╚════════════════════════════════════════════════════════════╝"
    echo ""
    log_error "MinIO distributed mode requires at least 4 drives"
    log_error "Current configuration: $total_drives drive(s)"
    log_info "Valid configurations: 4×1, 2×2, 3×2, 4×2, etc."
    echo ""
    log_error "Please run the wizard again and configure at least 4 drives"
    return 1
  fi

  # Update replicas count in topology file
  if command_exists yq; then
    yq eval -i ".minio.replicas = $total_drives" "$topology_file"
  else
    # Fallback: use sed
    sed -i.bak "s/replicas: 0/replicas: $total_drives/" "$topology_file"
    rm -f "${topology_file}.bak"
  fi

  echo ""
  log_success "╔════════════════════════════════════════════════════════════╗"
  log_success "║  Topology Configuration Complete                          ║"
  log_success "╚════════════════════════════════════════════════════════════╝"
  echo ""
  log_info "Total drives configured: $total_drives"
  log_info "MinIO replicas: $total_drives"
  echo ""
  log_success "Topology configuration saved to: $topology_file"
  echo ""
  log_info "Configuration summary:"
  cat "$topology_file"
  echo ""

  # Export the topology file path
  export MINIO_TOPOLOGY_CONFIG="$topology_file"

  return 0
}

# ═══════════════════════════════════════════════════════════════
# Create PersistentVolumes for MinIO Storage (Legacy Single-Drive)
# ═══════════════════════════════════════════════════════════════
# MinIO requires specific PVs with hostPath pointing to /minio and /cold
# This function creates PVs before MinIO deployment to ensure proper
# directory mounting

create_minio_persistent_volumes() {
  log_info "Creating PersistentVolumes for MinIO storage..."
  echo ""

  # Get list of nodes
  local nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
  local node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')

  if [ -z "$nodes" ] || [ "$node_count" -lt 1 ]; then
    log_error "Cannot detect cluster nodes"
    return 1
  fi

  # Calculate MinIO replicas (same logic as in Helm values)
  local minio_replicas=$(($node_count >= 4 ? 4 : $node_count * 2))

  # Calculate storage size per replica
  local size_per_replica_gb=$(($TOTAL_MINIO_GB > 0 && $node_count > 0 ? $TOTAL_MINIO_GB / $node_count : 100))
  local cold_size_per_replica_gb=$(($TOTAL_COLD_GB > 0 && $node_count > 0 ? $TOTAL_COLD_GB / $node_count : 50))

  log_info "MinIO configuration:"
  log_info "  - Replicas: $minio_replicas"
  log_info "  - Hot tier size per replica: ${size_per_replica_gb}Gi"
  log_info "  - Cold tier size per replica: ${cold_size_per_replica_gb}Gi"
  echo ""

  # Create array of nodes for distribution
  local nodes_array=($nodes)
  local pv_manifest="/tmp/openlakes-minio-pvs.yaml"

  # Generate PV manifests
  cat > "$pv_manifest" <<'EOF_HEADER'
# MinIO PersistentVolumes - Generated by OpenLakes
# These PVs use hostPath to mount /minio (hot tier) and /cold (cold tier)
# directories from cluster nodes
---
EOF_HEADER

  # Create PVs for MinIO hot tier (distributed across nodes)
  for i in $(seq 0 $(($minio_replicas - 1))); do
    # Distribute replicas across nodes (round-robin)
    local node_index=$(($i % $node_count))
    local node_name="${nodes_array[$node_index]}"

    cat >> "$pv_manifest" <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: minio-hot-pv-${i}
  labels:
    type: local
    app: minio
    tier: hot
spec:
  capacity:
    storage: ${size_per_replica_gb}Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: minio-hot
  hostPath:
    path: $MINIO_PATH
    type: DirectoryOrCreate
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - ${node_name}
---
EOF
  done

  # Create PVs for MinIO cold tier (one per node, mirrored)
  for i in $(seq 0 $(($node_count - 1))); do
    local node_name="${nodes_array[$i]}"

    cat >> "$pv_manifest" <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: minio-cold-pv-${i}
  labels:
    type: local
    app: minio
    tier: cold
spec:
  capacity:
    storage: ${cold_size_per_replica_gb}Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: minio-cold
  hostPath:
    path: $COLD_PATH
    type: DirectoryOrCreate
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - ${node_name}
---
EOF
  done

  # Apply PV manifests
  if [ "${DRY_RUN}" != "true" ]; then
    log_info "Applying MinIO PersistentVolume manifests..."
    if kubectl apply -f "$pv_manifest"; then
      log_success "Created $minio_replicas hot tier PVs and $node_count cold tier PVs"

      # Show created PVs
      echo ""
      log_info "MinIO PersistentVolumes:"
      kubectl get pv -l app=minio --no-headers 2>/dev/null | while read -r line; do
        echo "  $line"
      done
      echo ""
    else
      log_error "Failed to create MinIO PersistentVolumes"
      return 1
    fi
  else
    log_info "Would create PVs from: $pv_manifest"
    log_info "Preview of PV manifest:"
    head -50 "$pv_manifest"
  fi

  return 0
}

# Generate a minimal overlay for single-node clusters
prepare_single_node_overrides() {
  local output_file="/tmp/openlakes-single-node-overrides.yaml"

  cat > "${output_file}" <<EOF
# Auto-generated single-node overrides (standalone MinIO, local-path storage)
# Generated: $(date)
global:
  namespace: ${NAMESPACE}
  storageClass: ${SINGLE_NODE_STORAGE_CLASS:-local-path}

traefik:
  enabled: false
  persistence:
    storageClass: ${SINGLE_NODE_STORAGE_CLASS:-local-path}

postgresql:
  persistence:
    storageClass: ${SINGLE_NODE_STORAGE_CLASS:-local-path}

redis:
  persistence:
    storageClass: ${SINGLE_NODE_STORAGE_CLASS:-local-path}

minio:
  replicas: 1
  persistence:
    storageClass: ${SINGLE_NODE_STORAGE_CLASS:-local-path}

kafka:
  persistence:
    storageClass: ${SINGLE_NODE_STORAGE_CLASS:-local-path}

airflow:
  persistence:
    storageClass: ${SINGLE_NODE_STORAGE_CLASS:-local-path}
    accessMode: ReadWriteOnce

dashboard:
  service:
    type: ClusterIP

longhorn:
  enabled: false

opensearch:
  storageClass: ${SINGLE_NODE_STORAGE_CLASS:-local-path}

alluxio:
  enabled: false

loki:
  singleBinary:
    persistence:
      storageClass: ${SINGLE_NODE_STORAGE_CLASS:-local-path}

schemaRegistry:
  enabled: true

jupyterhub:
  hub:
    db:
      pvc:
        storageClassName: ${SINGLE_NODE_STORAGE_CLASS:-local-path}
  singleuser:
    storage:
      dynamic:
        storageClass: ${SINGLE_NODE_STORAGE_CLASS:-local-path}
      extraVolumes: []
      extraVolumeMounts: []

analyticsSharedExamplesEnabled: true

prometheus:
  enabled: true

kube-prometheus-stack:
  grafana:
    persistence:
      storageClassName: ${SINGLE_NODE_STORAGE_CLASS:-local-path}
  alertmanager:
    alertmanagerSpec:
      storage:
        volumeClaimTemplate:
          spec:
            storageClassName: ${SINGLE_NODE_STORAGE_CLASS:-local-path}
  prometheus:
    prometheusSpec:
      storageSpec:
        volumeClaimTemplate:
          spec:
            storageClassName: ${SINGLE_NODE_STORAGE_CLASS:-local-path}

loki:
  singleBinary:
    persistence:
      storageClass: ${SINGLE_NODE_STORAGE_CLASS:-local-path}
EOF

  STORAGE_CONFIG="${output_file}"
  log_success "Single-node overrides generated: ${output_file}"
  log_info "MinIO set to standalone mode with storageClass='${SINGLE_NODE_STORAGE_CLASS:-local-path}'"
}

# Main deployment function
main() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║           OpenLakes Deployment Script                      ║"
  echo "║           Cross-platform & Idempotent                      ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo ""

  # Load central config if present
  load_core_config

  # Ensure timeouts never exceed 5 minutes
  enforce_timeout_cap

  # Set resource profile and log capacity
  set_resource_profile
  # Enforce VM minimums (if applicable)
  enforce_minimum_resources
  # Load tier entries and validate size alignment (within 5%)
  load_tier_entries "hot" TIER_HOT
  load_tier_entries "cold" TIER_COLD
  load_tier_entries "cache" TIER_CACHE
  load_tier_entries "longhorn" TIER_LONGHORN
  validate_tier_sizes "hot" TIER_HOT
  validate_tier_sizes "cold" TIER_COLD
  validate_tier_sizes "cache" TIER_CACHE
  validate_tier_sizes "longhorn" TIER_LONGHORN
  cleanup_node_debugger_pods

  # Derive analytics examples toggle from config (analyticsExamples.enabled takes precedence)
  if [ -n "${CFG_ANALYTICS_EXAMPLES_ENABLED}" ]; then
    ANALYTICS_EXAMPLES_ENABLED="${CFG_ANALYTICS_EXAMPLES_ENABLED}"
  elif [ -n "${CFG_POPULATE_EXAMPLES}" ]; then
    ANALYTICS_EXAMPLES_ENABLED="${CFG_POPULATE_EXAMPLES}"
  fi
  if [ -n "${CFG_RESOURCE_PROFILE_OVERRIDE}" ] && [ "${CFG_RESOURCE_PROFILE_OVERRIDE}" != "null" ]; then
    RESOURCE_PROFILE="${CFG_RESOURCE_PROFILE_OVERRIDE}"
  fi

  if [ "${DRY_RUN}" = "true" ]; then
    log_warning "DRY RUN MODE - No changes will be made"
    echo ""
  fi

  log_info "Platform: ${PLATFORM}"
  log_info "Namespace: ${NAMESPACE}"
  log_info "Environment: ${DEPLOY_ENV}"
  log_info "Timeout: ${TIMEOUT}"
  echo ""

  # Switch kubectl context if provided
  if [ -n "${KUBE_CONTEXT}" ]; then
    if ! command_exists kubectl; then
      log_error "kubectl is required to switch context (--context flag)"
      exit 1
    fi
    log_info "Switching kubectl context to '${KUBE_CONTEXT}'..."
    if ! kubectl config use-context "${KUBE_CONTEXT}" >/dev/null 2>&1; then
      log_error "Failed to switch kubectl context to '${KUBE_CONTEXT}'"
      exit 1
    fi
  else
    if command_exists kubectl; then
      current_ctx=$(kubectl config current-context 2>/dev/null || echo "unknown")
      log_info "Using current kubectl context: ${current_ctx}"
    fi
  fi

  # Validate prerequisites
  validate_prerequisites

  log_info "Cluster mode detected: ${CLUSTER_MODE:-unknown} (${NODE_COUNT:-0} node(s))"
  # Force storage class to single-node default when applicable
  if [ "${CLUSTER_MODE}" = "single" ]; then
    CFG_STORAGE_CLASS="${SINGLE_NODE_STORAGE_CLASS:-local-path}"
  fi

  # Detect existing Traefik (skip deploying bundled controller if present)
  detect_existing_traefik

  # Check inter-node network performance (multi-node only)
  check_network_throughput

  # Single-node convenience: skip storage wizard and apply overrides
  if [ "${CLUSTER_MODE}" = "single" ]; then
    log_info "Single-node cluster detected - skipping storage wizard and using standalone MinIO config"
    CONFIGURE_STORAGE=false
    prepare_single_node_overrides
  fi

  # Run storage configuration wizard (enabled by default for multi-node)
  if [ "${CONFIGURE_STORAGE}" = "true" ]; then
    # Check if storage config already exists - skip wizard if it does
    if [ -f ".openlakes-storage-config.yaml" ]; then
      log_info "Found existing storage configuration: .openlakes-storage-config.yaml"
      log_info "Skipping wizard - using existing configuration"
      log_info "(Delete .openlakes-storage-config.yaml to reconfigure storage)"
      STORAGE_CONFIG=".openlakes-storage-config.yaml"
    else
      # No existing config - wizard is required
      log_info "No storage configuration found - wizard is required for first-time setup"

      # Verify we have an interactive terminal for the wizard
      if [ ! -t 0 ]; then
        log_error "Storage configuration wizard requires an interactive terminal"
        log_error "Current terminal is not interactive (stdin is not a TTY)"
        log_error ""
        log_error "Solutions:"
        log_error "  1. Run the script directly in an interactive terminal for first-time setup"
        log_error "  2. Create .openlakes-storage-config.yaml manually, then re-run"
        log_error "  3. Use --storage-config to provide a config file path"
        exit 1
      fi

      # Check bash version for storage wizard
      check_bash_version

      log_info "Running storage configuration wizard..."
      log_info "(Automatically detects multi-node clusters and configures Longhorn/Alluxio/MinIO)"
      echo ""
      if run_storage_configuration; then
        # The wizard exports STORAGE_CONFIG with the generated file path
        log_success "Storage configuration complete - will be used in deployment"
        log_info "Configuration file: ${STORAGE_CONFIG}"
      else
        log_warning "Storage wizard failed or was cancelled"
        log_info "Continuing with default storage configuration..."
      fi
    fi
  fi

  # Load storage configuration if provided
  if [ -n "${STORAGE_CONFIG}" ] && [ -f "${STORAGE_CONFIG}" ]; then
    log_success "Using storage configuration: ${STORAGE_CONFIG}"
    # Storage config will be merged with layer values during deployment
  fi

  # Check cluster state only if openlakes namespace doesn't exist
  if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
    check_cluster_state
  else
    log_info "Namespace '${NAMESPACE}' already exists, skipping cluster cleanliness check"
  fi

  # Ensure namespace exists
  ensure_namespace
  # Clean up Released PVs to avoid attach errors on reruns
  cleanup_released_pvs
  # Rebind retained PVs to their original claims to preserve data across redeploys
  rebind_retained_pvs

  # Create MinIO PersistentVolumes before deploying Layer 01
  # This ensures /minio and /cold directories are properly mounted
  if [ "${CLUSTER_MODE}" = "single" ]; then
    log_info "Single-node cluster: skipping MinIO PV pre-creation (standalone mode)"
  elif [ ${#TIER_HOT[@]} -gt 0 ]; then
    create_minio_pvs_from_tiers || exit 1
  elif [ -n "${TOTAL_MINIO_GB}" ] && [ "${TOTAL_MINIO_GB}" -gt 0 ]; then
    # Legacy wizard-based path
    echo ""
    log_info "═══════════════════════════════════════════════════════════"
    log_info "Creating MinIO Storage Volumes"
    log_info "═══════════════════════════════════════════════════════════"

    # Check if topology-based configuration is provided
    if [ -n "${STORAGE_CONFIG}" ] && [ -f "${STORAGE_CONFIG}" ] && command_exists yq; then
      # Check if topology is defined in storage config
      if yq eval '.minio.topology.nodes' "${STORAGE_CONFIG}" &>/dev/null && \
         [ "$(yq eval '.minio.topology.nodes | length' "${STORAGE_CONFIG}" 2>/dev/null || echo 0)" -gt 0 ]; then
        log_info "Detected MinIO topology configuration - using multi-drive layout"
        create_minio_pvs_from_topology "${STORAGE_CONFIG}" || {
          log_error "Failed to create MinIO PersistentVolumes from topology"
          exit 1
        }
      else
        # No topology defined - use traditional simple layout
        create_minio_persistent_volumes || {
          log_error "Failed to create MinIO PersistentVolumes"
          exit 1
        }
      fi
    else
      # No storage config or yq not available - use traditional simple layout
      create_minio_persistent_volumes || {
        log_error "Failed to create MinIO PersistentVolumes"
        exit 1
      }
    fi
  else
    log_info "Skipping MinIO PV creation (storage not configured)"
  fi

  # Deploy layers in order
  # Longhorn storage is deployed FIRST (above) to provide storage foundation for all other layers
  # Layer 06 uses 'layer06-ingestion' to avoid Kubernetes DNS naming issues (can't start with number)

  # ═══════════════════════════════════════════════════════════
  # Longhorn prerequisite check (multi-node only)
  # ═══════════════════════════════════════════════════════════
  if [ "${CLUSTER_MODE}" = "single" ]; then
    log_info "Single-node cluster: skipping Longhorn prerequisite (using storageClass='${SINGLE_NODE_STORAGE_CLASS:-local-path}')"
  else
    if ! kubectl get storageclass longhorn &>/dev/null; then
      log_error "Longhorn StorageClass 'longhorn' not found. Install and ready Longhorn before running this script."
      exit 1
    fi
    log_success "Longhorn StorageClass detected; proceeding without installing Longhorn"
    configure_longhorn_disks
  fi

  # ═══════════════════════════════════════════════════════════
  # Layer 01 - Infrastructure (requires Longhorn storage)
  # ═══════════════════════════════════════════════════════════
  # Detect IPv4 API endpoint for components that need explicit IPv4 (e.g., JupyterHub)
  detect_kube_api_ipv4

  deploy_layer "01" "infrastructure" "01-infrastructure" "statefulset:infrastructure-postgres,statefulset:infrastructure-kafka,statefulset:infrastructure-minio" || exit 1

  deploy_layer "02" "compute" "02-compute" "deployment:compute-trino,statefulset:compute-spark-worker" || exit 1

  deploy_layer "03" "streaming" "03-streaming" "" || exit 1  # Reserved for future streaming components

  deploy_layer "04" "orchestration" "04-orchestration" "" || exit 1
  sync_airflow_dags_from_repo || log_warning "Airflow DAG sync encountered issues (see logs above)"
  refresh_dashboard_runtime_credentials

  validate_analytics_examples_secret
  reset_analytics_examples_job
  deploy_layer "05" "analytics" "05-analytics" "deployment:analytics-superset" || exit 1

  if [ "${LOCAL_EXAMPLES_AVAILABLE}" = "true" ]; then
    sync_local_examples_to_pvc || log_warning "Failed to sync local analytics examples (see logs above)"
  fi

  # Post-deployment: Clean up JupyterHub proxy network policy if in dev environment
  if [ "$ENVIRONMENT" = "dev" ]; then
    log_info "Removing JupyterHub proxy network policy for dev environment..."
    kubectl delete networkpolicy analytics-jupyter-proxy -n openlakes 2>/dev/null && \
      log_success "Proxy network policy removed" || \
      log_warning "Proxy network policy not found (already removed or doesn't exist)"
  fi

  deploy_layer "06" "ingestion" "ingestion" "" || exit 1

  deploy_layer "07" "catalog" "catalog" "" || exit 1

  # ═══════════════════════════════════════════════════════════
  # Layer 08 - Monitoring (with GPU detection)
  # ═══════════════════════════════════════════════════════════
  echo ""
  log_info "═══════════════════════════════════════════════════════════"
  log_info "Preparing Layer 08: Monitoring"
  log_info "═══════════════════════════════════════════════════════════"

  # Verify metrics-server is installed (required for Prometheus metrics)
  verify_metrics_server

  # Detect GPUs and enable DCGM exporter if present
  GPU_MONITORING_ENABLED="false"
  if detect_gpus; then
    GPU_MONITORING_ENABLED="true"
    log_info "Enabling GPU monitoring (NVIDIA DCGM Exporter)"
  fi

  deploy_layer "08" "monitoring" "monitoring" "" || exit 1

  # Show final status
  echo ""
  log_info "═══════════════════════════════════════════════════════════"
  log_success "All layers deployed successfully!"
  log_info "═══════════════════════════════════════════════════════════"
  echo ""

  if [ "${DRY_RUN}" != "true" ]; then
    get_deployment_status
    summarize_pod_health || exit 1
    cleanup_node_debugger_pods
    refresh_dashboard_runtime_credentials

    echo ""
    log_info "╔════════════════════════════════════════════════════════════╗"
    log_info "║                    Service Access URLs                     ║"
    log_info "╚════════════════════════════════════════════════════════════╝"
    echo ""

    # Check if using Ingress or NodePort
    local networking_type=$(kubectl get configmap -n "${NAMESPACE}" -o jsonpath='{.data.NETWORKING_TYPE}' 2>/dev/null || echo "NodePort")

    local show_creds_lower
    show_creds_lower=$(echo "${CFG_DASHBOARD_SHOW_CREDS:-true}" | tr '[:upper:]' '[:lower:]')
    local dashboard_domain="${CFG_DOMAIN:-openlakes.local}"
    local dashboard_ingress_url="${CFG_DASHBOARD_PROTOCOL:-https}://dashboard.${dashboard_domain}"
    local dashboard_nodeport_url="${CFG_DASHBOARD_PROTOCOL:-https}://localhost:${CFG_DASHBOARD_PORT:-30443}"

    if [ "$networking_type" = "Ingress" ] || kubectl get ingressroute -n "${NAMESPACE}" >/dev/null 2>&1; then
      log_info "Access via Traefik Ingress (add to /etc/hosts: 127.0.0.1 *.openlakes.local):"
      echo ""
      log_info "Grafana (Monitoring):        http://grafana.openlakes.local"
      log_info "Prometheus (Metrics):        http://prometheus.openlakes.local"
      log_info "Alertmanager (Alerts):       http://alertmanager.openlakes.local"
      log_info "OpenMetadata (Catalog):      http://metadata.openlakes.local"
      log_info "Superset (Analytics):        http://superset.openlakes.local"
      log_info "Airflow (Orchestration):     http://airflow.openlakes.local"
      log_info "JupyterHub (Notebooks):      http://jupyter.openlakes.local"
      log_info "MinIO (Object Storage):      http://minio.openlakes.local"
      log_info "Trino (Query Engine):        http://trino.openlakes.local"
      log_info "Spark Master UI:             http://spark.openlakes.local"
      log_info "Traefik Dashboard:           http://traefik.openlakes.local/dashboard/"
      log_info "OpenLakes Dashboard:        ${dashboard_ingress_url}"
      if [ "${show_creds_lower}" = "true" ]; then
        log_info "Dashboard cards display live credentials pulled directly from the cluster (Airflow password is read from /opt/airflow/simple_auth_manager_passwords.json.generated)."
      else
        log_info "Dashboard cards omit credentials per configuration; adjust dashboard.showCredentials in core-config.yaml to expose them."
      fi
    else
      log_info "Access via NodePort (localhost):"
      echo ""
      log_info "OpenMetadata (Catalog):      http://localhost:30585"
      log_info "Superset (Analytics):        http://localhost:30088"
      log_info "Airflow (Orchestration):     http://localhost:30082"
      log_info "JupyterHub (Notebooks):      http://localhost:30888"
      log_info "MinIO (Object Storage):      http://localhost:30900"
      log_info "Trino (Query Engine):        http://localhost:30081"
      log_info "Spark Master UI:             http://localhost:30077"
      log_info "OpenLakes Dashboard:         ${dashboard_nodeport_url}"
      if [ "${show_creds_lower}" = "true" ]; then
        log_info "Dashboard cards display live credentials pulled directly from the cluster (Airflow password is read from /opt/airflow/simple_auth_manager_passwords.json.generated)."
      else
        log_info "Dashboard cards omit credentials per configuration; adjust dashboard.showCredentials in core-config.yaml to expose them."
      fi
    fi
    echo ""
  fi

  capture_resource_snapshot
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --timeout)
      TIMEOUT="$2"
      shift 2
      ;;
    --env)
      DEPLOY_ENV="$2"
      shift 2
      ;;
    --context)
      KUBE_CONTEXT="$2"
      shift 2
      ;;
    --skip-throughput-check)
      SKIP_THROUGHPUT_CHECK=true
      shift
      ;;
    --storage-config)
      STORAGE_CONFIG="$2"
      shift 2
      ;;
    --configure-storage)
      CONFIGURE_STORAGE=true  # Redundant now (enabled by default)
      shift
      ;;
    --skip-storage-wizard)
      CONFIGURE_STORAGE=false
      shift
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --dry-run                     Show what would be deployed without making changes"
      echo "  --namespace NAMESPACE         Kubernetes namespace (default: openlakes)"
      echo "  --timeout TIMEOUT             Helm timeout (default: 5m)"
      echo "  --env ENV                     Deployment environment (default: production)"
      echo "                                Values: local, dev, staging, production"
      echo "  --context CONTEXT             kubectl context to use (e.g., default, rancher-desktop)"
      echo "  --skip-throughput-check       Skip multi-node iperf3 throughput preflight"
      echo "  --skip-storage-wizard         Skip the interactive storage configuration wizard"
      echo "                                (wizard runs by default for multi-node clusters)"
      echo "  --storage-config FILE         Use pre-configured storage settings from FILE"
      echo "  --help                        Show this help message"
      echo ""
      echo "Environment Variables:"
      echo "  NAMESPACE              Alternative to --namespace flag"
      echo "  TIMEOUT                Alternative to --timeout flag"
      echo "  DRY_RUN                Set to 'true' for dry-run mode"
      echo "  DEPLOY_ENV             Alternative to --env flag"
      echo ""
      echo "Deployment Environments:"
      echo "  local      Fast local dev with Rancher Desktop (no push/pull)"
      echo "  dev        Collaborative development (team shares GHCR dev tag)"
      echo "  staging    QA/regression testing (release candidates)"
      echo "  production Stable production releases (version-pinned)"
      echo ""
      echo "Safety Features:"
      echo "  - Validates kubectl and helm are installed and working"
      echo "  - Checks cluster connectivity before deployment"
      echo "  - Detects existing deployments and asks for confirmation"
      echo "  - Idempotent: safe to run multiple times"
      echo "  - Waits for critical services to be ready"
      echo "  - Multi-node preflight measures inter-node throughput and warns if <1Gbps or non-Cilium CNI"
      echo ""
      echo "Examples:"
      echo "  $0                                         # Deploy with auto storage wizard (multi-node)"
      echo "  $0 --env local                             # Deploy local env with storage wizard"
      echo "  $0 --skip-storage-wizard                   # Deploy with default storage (no wizard)"
      echo "  $0 --storage-config /tmp/storage.yaml      # Deploy with pre-configured storage"
      echo "  $0 --dry-run --env local                   # Preview local deployment"
      echo "  $0 --namespace prod                        # Deploy to 'prod' namespace"
      echo ""
      echo "Storage Configuration Behavior:"
      echo "  - Multi-node clusters: Storage wizard runs automatically (interactive)"
      echo "  - Single-node clusters: Wizard skipped, standalone MinIO + local-path overrides applied automatically"
      echo "  - CI/CD (non-interactive): Wizard skipped automatically"
      echo "  - Use --skip-storage-wizard to disable wizard explicitly"
      echo "  - Use --storage-config FILE for pre-configured settings"
      echo ""
      echo "Note: Storage wizard requires Bash 4.0+ for associative arrays."
      echo "      On macOS: brew install bash"
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      echo "Run '$0 --help' for usage information"
      exit 1
      ;;
  esac
done

# Run main deployment
main
