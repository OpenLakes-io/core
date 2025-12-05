# OpenLakes JupyterHub Notebook Image
#
# Based on jupyter/pyspark-notebook but upgraded to match OpenLakes Spark cluster:
# - Spark 4.1.0-preview3 (matches Layer 02 compute cluster)
# - Scala 2.13
# - Hadoop 3.4.2 with S3A support
# - Apache Iceberg 1.8.0
# - OpenMetadata Python SDK
# - Pre-installed dependencies for all OpenLakes patterns

FROM jupyter/pyspark-notebook:ubuntu-22.04

# Build arguments for versioning
ARG VERSION=1.0.0
ARG BUILD_DATE
ARG VCS_REF
ARG SPARK_VERSION=4.1.0-preview3
ARG HADOOP_VERSION=3.4.2
ARG SCALA_VERSION=2.13
ARG ICEBERG_VERSION=1.10.0
ARG ALLUXIO_VERSION=2.9.3

# OCI labels (required for GHCR association)
LABEL org.opencontainers.image.title="OpenLakes JupyterHub Notebook"
LABEL org.opencontainers.image.description="JupyterHub singleuser notebook with Spark 4.1.0, Iceberg, S3A, and OpenLakes pattern dependencies"
LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.source="https://github.com/openlakes/core"
LABEL org.opencontainers.image.url="https://github.com/openlakes/core"
LABEL org.opencontainers.image.vendor="OpenLakes"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.revision="${VCS_REF}"

# Switch to root for system changes
USER root

# Remove existing Spark 3.5.0
RUN rm -rf /usr/local/spark* && \
    rm -f /usr/local/bin/spark-* && \
    rm -f /usr/local/bin/pyspark*

# Download and install Spark 4.1.0-preview3 matching OpenLakes cluster
# https://dist.apache.org/repos/dist/release/spark/spark-4.1.0-preview3/spark-4.1.0-preview3-bin-hadoop3-connect.tgz
RUN wget -q https://dist.apache.org/repos/dist/release/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop3-connect.tgz && \
    tar -xzf spark-${SPARK_VERSION}-bin-hadoop3-connect.tgz -C /usr/local && \
    rm spark-${SPARK_VERSION}-bin-hadoop3-connect.tgz && \
    ln -s /usr/local/spark-${SPARK_VERSION}-bin-hadoop3-connect /usr/local/spark

# Set Spark environment variables
ENV SPARK_HOME=/usr/local/spark
ENV PATH=${PATH}:${SPARK_HOME}/bin:${SPARK_HOME}/sbin
ENV PYTHONPATH=${SPARK_HOME}/python:${SPARK_HOME}/python/lib/py4j-0.10.9.9-src.zip:${PYTHONPATH}

# Pre-download required JARs to avoid download delays at runtime
RUN mkdir -p ${SPARK_HOME}/jars-extra && \
    cd ${SPARK_HOME}/jars-extra && \
    # Apache Iceberg for Spark 4.x (runtime 4.0 for Spark 4.0+)
    wget -q https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark-runtime-4.0_${SCALA_VERSION}/${ICEBERG_VERSION}/iceberg-spark-runtime-4.0_${SCALA_VERSION}-${ICEBERG_VERSION}.jar && \
    # Hadoop AWS for S3A support (Hadoop 3.4+ requires AWS SDK v2)
    wget -q https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/${HADOOP_VERSION}/hadoop-aws-${HADOOP_VERSION}.jar && \
    # AWS SDK v2 Bundle (required by Hadoop 3.4.2 and Iceberg 1.10.0)
    wget -q https://repo1.maven.org/maven2/software/amazon/awssdk/bundle/2.29.39/bundle-2.29.39.jar && \
    # Alluxio client for S3A filesystem interception (shaded to avoid dependency conflicts)
    wget -q https://repo1.maven.org/maven2/org/alluxio/alluxio-shaded-client/${ALLUXIO_VERSION}/alluxio-shaded-client-${ALLUXIO_VERSION}.jar && \
    # Add JARs to Spark classpath
    cp *.jar ${SPARK_HOME}/jars/ && \
    cd / && rm -rf ${SPARK_HOME}/jars-extra

# Switch back to jovyan user
USER ${NB_UID}

# Install OpenLakes pattern dependencies
# NOTE: We do NOT install pyspark via pip - we use the bundled PySpark from $SPARK_HOME/python
# which is already in PYTHONPATH and matches the Spark binary version exactly
RUN pip install --no-cache-dir \
    kafka-python==2.0.2 \
    confluent-kafka==2.3.0 \
    psycopg2-binary==2.9.10 \
    trino==0.329.0 \
    sqlalchemy==2.0.36 \
    papermill==2.6.0 \
    nbformat==5.10.4 \
    ipywidgets==8.1.5 \
    boto3==1.35.34 \
    minio==7.2.9
# Note: openmetadata-ingestion excluded due to complex dependency conflicts
# Can be installed in notebook if needed: pip install openmetadata-ingestion

# Verify installation
RUN python -c "import pyspark; print(f'PySpark: {pyspark.__version__}')" && \
    spark-submit --version 2>&1 | grep "version ${SPARK_VERSION}" && \
    echo "✓ Spark ${SPARK_VERSION} with Scala ${SCALA_VERSION}" && \
    echo "✓ Hadoop ${HADOOP_VERSION} with S3A support" && \
    echo "✓ Apache Iceberg ${ICEBERG_VERSION}" && \
    echo "✓ Alluxio ${ALLUXIO_VERSION} client" && \
    echo "✓ All OpenLakes dependencies installed"

# Default working directory
WORKDIR /home/jovyan

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import pyspark" || exit 1
