FROM apache/airflow:2.11.0-python3.11

# Switch to root for system dependencies
USER root

# Install system dependencies required by OpenMetadata
RUN apt-get update && apt-get install -y \
    build-essential \
    default-libmysqlclient-dev \
    libpq-dev \
    libsasl2-dev \
    libssl-dev \
    libkrb5-dev \
    pkg-config \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install uv for faster package installation (install system-wide)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh && \
    mv /root/.local/bin/uv /usr/local/bin/uv

# Install OpenMetadata packages and dependencies using uv (while still root for --system flag)
RUN uv pip install --system \
    openmetadata-ingestion[all]==1.6.1 \
    openmetadata-managed-apis==1.6.1 \
    apache-airflow-providers-postgres>=5.0.0 \
    apache-airflow-providers-http>=4.0.0

# Switch back to airflow user
USER airflow

# Set environment variables for OpenMetadata
ENV AIRFLOW__OPENMETADATA__ENABLED=True

# Health check remains the same
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
  CMD airflow jobs check --job-type SchedulerJob --hostname "$(hostname)" || exit 1
