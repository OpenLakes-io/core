# OpenLakes Spark Cluster Image
#
# Based on apache/spark:4.1.0-preview3 extended with:
# - OpenLineage Spark Agent for automated lineage tracking
# - OpenMetadata Transporter for native OpenMetadata integration
# - Hadoop AWS + AWS SDK v2 for S3A/MinIO support
# - Apache Iceberg 1.8.0 with Nessie catalog for Git-like data versioning
# - Nessie Client 0.77.1 for Project Nessie integration
# - Alluxio Client 2.9.3 for distributed caching (multi-node clusters)

FROM apache/spark:4.1.0-preview3

# Build arguments for versioning
ARG VERSION=1.0.0
ARG BUILD_DATE
ARG VCS_REF

# OCI labels (required for GHCR association)
LABEL org.opencontainers.image.title="OpenLakes Spark"
LABEL org.opencontainers.image.description="Apache Spark 4.1.0-preview3 with Iceberg, Nessie, S3A, OpenLineage, and OpenMetadata for OpenLakes data platform"
LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.source="https://github.com/openlakes/core"
LABEL org.opencontainers.image.url="https://github.com/openlakes/core"
LABEL org.opencontainers.image.vendor="OpenLakes"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.revision="${VCS_REF}"

USER root

# Download OpenLineage Spark Agent and OpenMetadata Transporter JARs from Maven Central
# OpenLineage Spark agent: io.openlineage:openlineage-spark_2.13:1.40.1 (Scala 2.13 for Spark 4.x)
# OpenMetadata transporter: io.github.natural-intelligence:openlineage-openmetadata-transporter:1.35
RUN curl -L -o /opt/spark/jars/openlineage-spark_2.13-1.40.1.jar \
    https://repo1.maven.org/maven2/io/openlineage/openlineage-spark_2.13/1.40.1/openlineage-spark_2.13-1.40.1.jar \
    && echo "Downloaded OpenLineage Spark Agent JAR" \
    && ls -lh /opt/spark/jars/openlineage-spark_2.13-1.40.1.jar

RUN curl -L -o /opt/spark/jars/openlineage-openmetadata-transporter-1.35.jar \
    https://repo1.maven.org/maven2/io/github/natural-intelligence/openlineage-openmetadata-transporter/1.35/openlineage-openmetadata-transporter-1.35.jar \
    && echo "Downloaded OpenMetadata Transporter JAR" \
    && ls -lh /opt/spark/jars/openlineage-openmetadata-transporter-1.35.jar

# Download Hadoop AWS JARs for S3A support
# Using Hadoop 3.4.1 with AWS SDK v2 (Spark 4.x compatible, avoids "60s" string parsing issues)
RUN curl -L -o /opt/spark/jars/hadoop-aws-3.4.1.jar \
    https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/3.4.1/hadoop-aws-3.4.1.jar \
    && echo "Downloaded Hadoop AWS JAR" \
    && ls -lh /opt/spark/jars/hadoop-aws-3.4.1.jar

# AWS SDK v2 Bundle (required by hadoop-aws 3.4.1)
RUN curl -L -o /opt/spark/jars/bundle-2.29.27.jar \
    https://repo1.maven.org/maven2/software/amazon/awssdk/bundle/2.29.27/bundle-2.29.27.jar \
    && echo "Downloaded AWS SDK v2 Bundle JAR" \
    && ls -lh /opt/spark/jars/bundle-2.29.27.jar

# Download Iceberg Nessie Catalog JAR for Git-like data versioning
# Using version matching Iceberg 1.8.0 (bundled with Spark 4.1.0)
RUN curl -L -o /opt/spark/jars/iceberg-nessie-1.8.0.jar \
    https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-nessie/1.8.0/iceberg-nessie-1.8.0.jar \
    && echo "Downloaded Iceberg Nessie Catalog JAR" \
    && ls -lh /opt/spark/jars/iceberg-nessie-1.8.0.jar

# Download Nessie Client JAR (required by iceberg-nessie)
RUN curl -L -o /opt/spark/jars/nessie-client-0.77.1.jar \
    https://repo1.maven.org/maven2/org/projectnessie/nessie/nessie-client/0.77.1/nessie-client-0.77.1.jar \
    && echo "Downloaded Nessie Client JAR" \
    && ls -lh /opt/spark/jars/nessie-client-0.77.1.jar

# Download Alluxio Client JAR for distributed caching (multi-node clusters)
# alluxio-shaded-client: All-in-one client with all dependencies
RUN curl -L -o /opt/spark/jars/alluxio-shaded-client-2.9.3.jar \
    https://repo1.maven.org/maven2/org/alluxio/alluxio-shaded-client/2.9.3/alluxio-shaded-client-2.9.3.jar \
    && echo "Downloaded Alluxio Client JAR" \
    && ls -lh /opt/spark/jars/alluxio-shaded-client-2.9.3.jar

# Verify JARs were downloaded successfully (will fail build if missing)
RUN test -f /opt/spark/jars/openlineage-spark_2.13-1.40.1.jar || \
    (echo "ERROR: OpenLineage Spark JAR not found!" && exit 1)
RUN test -f /opt/spark/jars/openlineage-openmetadata-transporter-1.35.jar || \
    (echo "ERROR: OpenMetadata transporter JAR not found!" && exit 1)
RUN test -f /opt/spark/jars/iceberg-nessie-1.8.0.jar || \
    (echo "ERROR: Iceberg Nessie JAR not found!" && exit 1)
RUN test -f /opt/spark/jars/nessie-client-0.77.1.jar || \
    (echo "ERROR: Nessie Client JAR not found!" && exit 1)
RUN test -f /opt/spark/jars/alluxio-shaded-client-2.9.3.jar || \
    (echo "ERROR: Alluxio Client JAR not found!" && exit 1)

# Display JAR info for build verification
RUN echo "Installed JARs:" && \
    ls -lh /opt/spark/jars/openlineage-*.jar && \
    ls -lh /opt/spark/jars/alluxio-*.jar

# Switch back to spark user
USER 185

WORKDIR /opt/spark/work-dir
