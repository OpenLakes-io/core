# Drive-Level Storage Allocation

## Overview

OpenLakes storage wizard implements **drive-level allocation tracking** to ensure precise storage management across Longhorn (block storage), Alluxio (caching), and MinIO (object storage). This document explains how drive-specific allocations are tracked and applied to Kubernetes deployments.

## Architecture

### The Gap That Was Filled

**Previous Behavior**: The storage wizard tracked allocations at the drive level internally, but generated generic Helm values that didn't actually configure specific drives:

- **Longhorn**: Used `/var/lib/longhorn` (generic root filesystem path)
- **MinIO**: Used `local-path` StorageClass (Kubernetes decides placement)
- **Alluxio**: Used average cache size with no specific drive paths

**New Behavior**: The wizard now generates:

1. **Drive-specific configurations** for each storage component
2. **Post-deployment scripts** to configure Longhorn disks via CRDs
3. **Mount path documentation** for MinIO and Alluxio drives
4. **Alluxio tieredstore configuration** with hostPath for specific drives

## How It Works

### 1. Drive Detection and Allocation

The storage wizard (`deploy-openlakes.sh`) performs drive-level tracking:

```bash
# Internal tracking arrays
LONGHORN_DRIVES=("0:/dev/sda:200" "1:/dev/nvme0n1:200")
ALLUXIO_DRIVES=("0:/dev/sdb:300" "1:/dev/nvme1n1:300")
MINIO_DRIVES=("0:/dev/sda:500" "1:/dev/nvme0n1:500")

# Per-drive allocation tracking
DRIVE_ALLOCATED_GB["0:/dev/sda"]=700  # 200 Longhorn + 500 MinIO
DRIVE_TOTAL_GB["0:/dev/sda"]=1000
```

### 2. Helm Values Generation

The `generate_helm_values()` function (deploy-openlakes.sh:1353) transforms drive arrays into Helm value overrides:

#### Longhorn Configuration

```yaml
longhorn:
  enabled: true
  defaultSettings:
    createDefaultDiskLabeledNodes: false  # Manual disk configuration
```

Additionally generates `/tmp/configure-longhorn-disks.sh`:

```bash
#!/usr/bin/env bash
# Configures Longhorn Node CRDs to use specific drives

kubectl patch node.longhorn.io/nuc -n openlakes --type=json -p='[
  {
    "op": "add",
    "path": "/spec/disks/_dev_sda",
    "value": {
      "allowScheduling": true,
      "path": "/mnt/longhorn-dev-sda",
      "storageReserved": 800000000000  # Total - Allocated
    }
  }
]'
```

#### MinIO Configuration

```yaml
# Drive-level allocation configured:
#   - nuc: /dev/sda (500GB)
#   - ryzen: /dev/nvme0n1 (500GB)
minio:
  enabled: true
  replicas: 4
  persistence:
    storageClass: ""  # Use hostPath
  # Mount paths for each replica:
  #   replica-0: nuc:/mnt/minio-dev-sda (from /dev/sda, 500GB)
  #   replica-1: ryzen:/mnt/minio-dev-nvme0n1 (from /dev/nvme0n1, 500GB)
```

#### Alluxio Configuration

```yaml
# Drive-level allocation configured:
#   - nuc: /dev/sdb (300GB)
#   - ryzen: /dev/nvme1n1 (300GB)
alluxio:
  enabled: true
  tieredstore:
    levels:
    - level: 0
      alias: MEM
      mediumtype: MEM
      path: /dev/shm
      type: emptyDir
      quota: 1Gi
    - level: 1
      alias: SSD
      mediumtype: SSD
      path: /mnt/alluxio-dev-sdb  # Specific drive mount
      type: hostPath
      quota: 300Gi
```

### 3. Drive Mounting Requirements

For the configurations to work, drives must be mounted at specific paths on each node:

**Longhorn Drives**:
```
/mnt/longhorn-dev-sda
/mnt/longhorn-dev-nvme0n1
```

**MinIO Drives**:
```
/mnt/minio-dev-sda
/mnt/minio-dev-nvme0n1
```

**Alluxio Drives**:
```
/mnt/alluxio-dev-sdb
/mnt/alluxio-dev-nvme1n1
```

## Mount Path Naming Convention

The wizard generates consistent mount paths:

```bash
drive="/dev/sda"
mount_path="/mnt/longhorn$(echo $drive | tr '/' '-')"
# Result: /mnt/longhorn-dev-sda
```

This converts device paths like `/dev/nvme0n1` to mount paths like `/mnt/longhorn-dev-nvme0n1`.

## Implementation Status

### ✅ Fully Implemented

1. **Drive-level allocation tracking**
   - `LONGHORN_DRIVES`, `ALLUXIO_DRIVES`, `MINIO_DRIVES` arrays
   - `DRIVE_ALLOCATED_GB` and `DRIVE_TOTAL_GB` associative arrays
   - Over-allocation validation

2. **Longhorn disk configuration**
   - Generates `/tmp/configure-longhorn-disks.sh`
   - Patches Longhorn Node CRDs with specific disk paths
   - Calculates storage reserved per drive

3. **Alluxio tieredstore configuration**
   - Generates multi-level tieredstore with MEM + disk tiers
   - Uses hostPath volumes for specific drives
   - Directly supported by Alluxio Helm chart

4. **MinIO drive documentation**
   - Documents required mount paths per replica
   - Lists drive allocations in generated YAML

### ⚠️ Requires Additional Work

**MinIO hostPath Configuration**:
The current MinIO Helm chart uses a simple `persistence` configuration. To use specific drives per replica, one of these approaches is needed:

1. **Custom StatefulSet volumeClaimTemplates** - Patch MinIO Helm chart to support per-replica hostPath volumes
2. **Pre-created PersistentVolumes** - Create PV objects with node affinity before deployment
3. **Custom MinIO Helm Chart** - Fork and modify the MinIO chart to support drive mappings

**Recommendation**: Create pre-deployment script to generate PV objects:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: minio-nuc-sda
spec:
  capacity:
    storage: 500Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  local:
    path: /mnt/minio-dev-sda
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - nuc
```

## Usage Workflow

### 1. Run Storage Wizard

```bash
./deploy-openlakes.sh
# Interactive wizard detects drives and allocates storage
```

### 2. Review Generated Configuration

```bash
cat /tmp/openlakes-storage-config.yaml
# Check Longhorn, MinIO, Alluxio configurations

cat /tmp/configure-longhorn-disks.sh
# Review Longhorn disk configuration script
```

### 3. Mount Drives on Nodes

Before deployment, ensure drives are mounted:

```bash
# On each node
sudo mkdir -p /mnt/longhorn-dev-sda
sudo mount /dev/sda /mnt/longhorn-dev-sda

sudo mkdir -p /mnt/minio-dev-sda
sudo mount /dev/sdb /mnt/minio-dev-sda

sudo mkdir -p /mnt/alluxio-dev-sdc
sudo mount /dev/sdc /mnt/alluxio-dev-sdc
```

### 4. Deploy OpenLakes

```bash
./deploy-openlakes.sh
# Deployment uses generated storage configuration
```

### 5. Configure Longhorn Disks

After Longhorn is running:

```bash
/tmp/configure-longhorn-disks.sh
# Patches Longhorn nodes with drive-specific disk configuration
```

## Testing

### Validation Test

The `test-storage-simple.sh` script validates allocation reconciliation:

```bash
./test-storage-simple.sh
```

**Validates**:
1. Component totals (Longhorn + Alluxio + MinIO)
2. Per-drive allocation tracking
3. No over-allocation
4. Drive-level reconciliation

### Configuration Generation Test

The `test-drive-allocation.sh` script tests Helm values generation:

```bash
./test-drive-allocation.sh
```

**Validates**:
1. Longhorn disk configuration script generation
2. MinIO drive mapping documentation
3. Alluxio tieredstore configuration with hostPath

## Benefits

1. **Precise Storage Management**: No wasted capacity, no over-allocation
2. **Performance Optimization**: Place workloads on appropriate drive types (NVMe vs HDD)
3. **Resource Isolation**: Separate drives for block, cache, and object storage
4. **Capacity Planning**: Clear visibility into storage allocation per component
5. **Failure Isolation**: Drive failures affect only specific components

## Future Enhancements

1. **Automatic Drive Mounting**: Pre-deployment script to format and mount drives
2. **MinIO PV Generation**: Create PersistentVolume objects with node affinity
3. **Drive Type Detection**: Automatically detect NVMe vs SSD vs HDD
4. **Dynamic Rebalancing**: Adjust allocations based on actual usage patterns
5. **Health Monitoring**: Track drive health and automatically evacuate failing drives

## Related Files

- `deploy-openlakes.sh` - Main deployment script with storage wizard
- `deploy-openlakes.sh:1270-1350` - `generate_longhorn_disk_config()` function
- `deploy-openlakes.sh:1353-1609` - `generate_helm_values()` function
- `test-storage-simple.sh` - Allocation reconciliation validation
- `test-drive-allocation.sh` - Configuration generation test
- `/tmp/openlakes-storage-config.yaml` - Generated Helm values (runtime)
- `/tmp/configure-longhorn-disks.sh` - Longhorn disk configuration script (runtime)
- `.openlakes-storage-config.env` - Storage configuration environment variables

## Troubleshooting

### Issue: Longhorn not using specific drives

**Solution**: Run `/tmp/configure-longhorn-disks.sh` after Longhorn is deployed. Verify mount paths exist on nodes.

### Issue: Alluxio worker pods failing to start

**Cause**: hostPath `/mnt/alluxio-dev-*` doesn't exist on node.

**Solution**: Create mount points and mount drives before deploying Alluxio.

### Issue: MinIO replicas not using specific drives

**Cause**: MinIO Helm chart doesn't support per-replica hostPath configuration.

**Solution**: Create PersistentVolume objects with node affinity before deploying MinIO, or use a custom MinIO Helm chart.

### Issue: Over-allocation errors

**Cause**: Drive allocated to multiple components exceeds total capacity.

**Solution**: Re-run storage wizard and adjust allocations. The wizard validates and prevents over-allocation interactively.

## References

- [Longhorn Node and Disk Configuration](https://longhorn.io/docs/latest/references/storage-network/)
- [Alluxio Tiered Storage](https://docs.alluxio.io/os/user/stable/en/core-services/Caching.html#tiered-storage)
- [MinIO Distributed Mode](https://min.io/docs/minio/linux/operations/install-deploy-manage/deploy-minio-multi-node-multi-drive.html)
- [Kubernetes Local Persistent Volumes](https://kubernetes.io/docs/concepts/storage/volumes/#local)
