#!/bin/sh
set -e

# Replace environment variable placeholders in env-config.js
sed -i "s|__PROTOCOL__|${OPENLAKES_PROTOCOL:-https}|g" /usr/share/nginx/html/env-config.js
sed -i "s|__DOMAIN__|${OPENLAKES_DOMAIN:-openlakes.dev}|g" /usr/share/nginx/html/env-config.js
sed -i "s|__PORT__|${OPENLAKES_PORT:-30443}|g" /usr/share/nginx/html/env-config.js
sed -i "s#__SERVICES_B64__#${OPENLAKES_SERVICES_B64:-}#g" /usr/share/nginx/html/env-config.js
sed -i "s#__SHOW_CREDENTIALS__#${OPENLAKES_SHOW_CREDENTIALS:-true}#g" /usr/share/nginx/html/env-config.js
sed -i "s#__VERSION__#${OPENLAKES_VERSION:-v1.0.1}#g" /usr/share/nginx/html/env-config.js

# Start nginx
exec nginx -g 'daemon off;'
