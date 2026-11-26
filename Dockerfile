FROM docker.io/openresty/openresty:1.27.1.2-alpine-fat AS fat

RUN luarocks install lua-resty-openidc

FROM docker.io/openresty/openresty:1.27.1.2-alpine-slim

# hadolint ignore=DL3018
RUN apk update && \
    apk upgrade && \
    apk add --no-cache ca-certificates gettext bash

COPY --from=fat /usr/local/openresty/luajit/lib/lua/5.1 /usr/local/openresty/luajit/lib/lua/5.1
COPY --from=fat /usr/local/openresty/luajit/share/lua/5.1 /usr/local/openresty/luajit/share/lua/5.1

RUN chmod -R a+rX /usr/local/openresty/lualib /usr/local/openresty/nginx/modules

RUN mkdir -p /tmp/nginx/logs \
             /tmp/nginx/client \
             /tmp/nginx/fastcgi \
             /tmp/nginx/proxy \
             /tmp/nginx/uwsgi \
             /tmp/nginx/scgi \
             /etc/nginx/oidc && \
    rm -f /etc/nginx/conf.d/default.conf

COPY ./src/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf.template
COPY ./src/oidc.conf /etc/nginx/conf.d/oidc.conf.template
COPY ./src/client.conf /etc/nginx/oidc
COPY ./src/logout.conf /etc/nginx/oidc

RUN chgrp -R 0 /tmp/nginx /var/run/openresty /usr/local/openresty/nginx/logs /usr/local/openresty/nginx/conf /etc/nginx/conf.d /etc/nginx/oidc && \
    chmod -R g+rwX /tmp/nginx /var/run/openresty /usr/local/openresty/nginx/logs /usr/local/openresty/nginx/conf /etc/nginx/conf.d /etc/nginx/oidc

COPY ./src/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

COPY ./src/index.html /usr/share/nginx/html/index.html
RUN chmod -R a+r /usr/share/nginx/html

EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
USER 1031
