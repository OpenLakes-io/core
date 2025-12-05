# OpenLakes Dashboard - Material UI service links dashboard
#
# Multi-stage build:
# 1. Build React app
# 2. Serve static files with nginx

# Build stage
FROM node:18-alpine AS build

# Build arguments for versioning
ARG VERSION=1.0.0
ARG BUILD_DATE
ARG VCS_REF

WORKDIR /app

# Copy package files
COPY package.json ./

# Install dependencies
RUN npm install

# Copy source code
COPY public/ ./public/
COPY src/ ./src/

# Build production bundle
RUN npm run build

# Production stage
FROM nginx:alpine

# Build arguments for labels
ARG VERSION=1.0.0
ARG BUILD_DATE
ARG VCS_REF

# OCI labels (required for GHCR association)
LABEL org.opencontainers.image.title="OpenLakes Dashboard"
LABEL org.opencontainers.image.description="Material UI dashboard for OpenLakes Core service links"
LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.source="https://github.com/openlakes/core"
LABEL org.opencontainers.image.url="https://github.com/openlakes/core"
LABEL org.opencontainers.image.vendor="OpenLakes"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.revision="${VCS_REF}"

# Copy built static files from build stage
COPY --from=build /app/build /usr/share/nginx/html

# Copy env-config.js template to the build output
COPY public/env-config.js /usr/share/nginx/html/env-config.js

# Copy custom nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy entrypoint script
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Insert script tag for env-config.js in the built index.html
RUN sed -i 's|</title>|</title><script src="/env-config.js"></script>|' /usr/share/nginx/html/index.html

# Expose port 80
EXPOSE 80

# Environment variables with defaults
ENV OPENLAKES_PROTOCOL=https
ENV OPENLAKES_DOMAIN=openlakes.dev
ENV OPENLAKES_PORT=30443
ENV OPENLAKES_SERVICES_B64=""
ENV OPENLAKES_SHOW_CREDENTIALS=true
ENV OPENLAKES_VERSION=v1.0.0

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost/ || exit 1

# Start with entrypoint that configures env vars
ENTRYPOINT ["/docker-entrypoint.sh"]
