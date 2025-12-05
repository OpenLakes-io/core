# OpenLakes Airflow runtime image
#
# Based on apache/airflow:3.1.2 with extra dependencies baked in so the chart
# no longer needs to `pip install` packages at runtime.

FROM apache/airflow:3.1.2

ARG VERSION=1.0.0
ARG BUILD_DATE
ARG VCS_REF

LABEL org.opencontainers.image.title="OpenLakes Airflow Runtime"
LABEL org.opencontainers.image.description="Airflow 3.1.2 with Papermill, Spark, Amazon provider, and OpenLakes orchestration deps baked in"
LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.source="https://github.com/openlakes/core"
LABEL org.opencontainers.image.url="https://github.com/openlakes/core"
LABEL org.opencontainers.image.vendor="OpenLakes"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.revision="${VCS_REF}"

# Install required packages with the official constraints to stay compatible
COPY --chown=airflow:airflow requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt && \
    rm -f /tmp/requirements.txt

# Re-introduce the legacy airflow.utils.log.secrets_masker import path so that
# older providers (including apache-airflow-providers-amazon) continue to work
# on Airflow 3.x.
COPY --chown=airflow:airflow compat/ /tmp/openlakes-compat/
RUN python <<'PY'
from pathlib import Path
import site

compat_root = Path('/tmp/openlakes-compat') / 'airflow' / 'utils' / 'log'
shim_src = compat_root / 'secrets_masker.py'
site_packages = Path(site.getusersitepackages())
dst = site_packages / 'airflow' / 'utils' / 'log' / 'secrets_masker.py'
dst.parent.mkdir(parents=True, exist_ok=True)
dst.write_text(shim_src.read_text())
PY
