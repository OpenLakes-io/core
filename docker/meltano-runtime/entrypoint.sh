#!/bin/sh
set -euo pipefail

PROJECT_ROOT="${MELTANO_PROJECT_ROOT:-/workspace/project}"
BOOTSTRAP_DIR="${MELTANO_BOOTSTRAP_DIR:-/bootstrap}"

mkdir -p "${PROJECT_ROOT}"

if [ -d "${BOOTSTRAP_DIR}" ]; then
  if [ -f "${BOOTSTRAP_DIR}/meltano.yml" ]; then
    cp "${BOOTSTRAP_DIR}/meltano.yml" "${PROJECT_ROOT}/meltano.yml"
  fi

  if [ -f "${BOOTSTRAP_DIR}/requirements.txt" ]; then
    echo "NOTE: /bootstrap/requirements.txt detected. Custom dependencies must be baked into the Meltano image."
  fi
fi

cd "${PROJECT_ROOT}"
meltano install

exec tail -f /dev/null
