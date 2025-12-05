# OpenLakes Meltano runtime image
#
# Purpose:
#   - Provide a pinned Meltano CLI version for ingestion workflows
#   - Bake in OpenLakes metadata and entrypoint so runtime pods avoid ad-hoc setup
#   - Execute `meltano install` on container start, then remain available for
#     orchestrators (Airflow/Dagster) to exec `meltano run` commands
#
# Notes:
#   - Additional Python dependencies should be added via a derived image. We
#     intentionally avoid runtime `pip install` inside the pod.

FROM meltano/meltano:v4.0.6

ARG VERSION=1.0.0
ARG BUILD_DATE
ARG VCS_REF

LABEL org.opencontainers.image.title="OpenLakes Meltano Runtime"
LABEL org.opencontainers.image.description="Pinned Meltano CLI runtime with OpenLakes bootstrap entrypoint"
LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.source="https://github.com/openlakes/core"
LABEL org.opencontainers.image.url="https://github.com/openlakes/core"
LABEL org.opencontainers.image.vendor="OpenLakes"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.revision="${VCS_REF}"

# Copy bootstrap entrypoint
COPY entrypoint.sh /usr/local/bin/openlakes-meltano-entrypoint.sh
RUN chmod +x /usr/local/bin/openlakes-meltano-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/openlakes-meltano-entrypoint.sh"]
