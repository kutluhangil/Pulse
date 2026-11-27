# Pulse site: built static files + nginx (unprivileged, 8080). Version pinned, updated by hand.
FROM nginxinc/nginx-unprivileged:1.30.1-alpine
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY dist/ /usr/share/nginx/html/
