#!/bin/bash
set -e

NGINX_RESOLVER=${NGINX_RESOLVER:-$(awk '/^nameserver / { print $2; exit }' /etc/resolv.conf)}
export NGINX_RESOLVER

# shellcheck disable=SC2016
envsubst '${NGINX_RESOLVER}' < /usr/local/openresty/nginx/conf/nginx.conf.template > /usr/local/openresty/nginx/conf/nginx.conf
# shellcheck disable=SC2016
envsubst '${NGINX_RESOLVER}' < /etc/nginx/conf.d/oidc.conf.template > /etc/nginx/conf.d/oidc.conf

exec /usr/local/openresty/bin/openresty -g "daemon off;"
