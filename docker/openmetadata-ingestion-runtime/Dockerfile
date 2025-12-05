# OpenLakes OpenMetadata ingestion Airflow runtime
#
# Base: openmetadata/ingestion:1.10.7 (includes OpenMetadata DAGs & plugins)
# Adds just enough extras for OpenLakes (S3 remote logging, protobuf pin).

FROM openmetadata/ingestion:1.10.7

ARG VERSION=1.0.0
ARG BUILD_DATE
ARG VCS_REF

LABEL org.opencontainers.image.title="OpenLakes OpenMetadata Ingestion Runtime"
LABEL org.opencontainers.image.description="OpenMetadata ingestion Airflow image with S3 logging dependencies baked in"
LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.source="https://github.com/openlakes/core"
LABEL org.opencontainers.image.url="https://github.com/openlakes/core"
LABEL org.opencontainers.image.vendor="OpenLakes"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.revision="${VCS_REF}"

# Install dependencies required for MinIO/S3 remote logging
RUN pip install --no-cache-dir 'protobuf>=5.0,<6.0' apache-airflow-providers-amazon==9.0.0
