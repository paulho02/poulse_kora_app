#!/bin/sh
# Substitute only $PORT into the nginx config template — deliberately not a
# blanket `envsubst` over every env var, so nginx's own `$uri`/`$host`/etc.
# in the template are left untouched.
set -e

: "${PORT:=8080}"

envsubst '${PORT}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

exec nginx -g 'daemon off;'
