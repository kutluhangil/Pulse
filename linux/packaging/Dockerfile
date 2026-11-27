# Pulse for Linux: test, package and screenshot in Ubuntu 24.04 (the target desktop).
#   docker buildx build -f linux/packaging/Dockerfile --target deb  --output dist/linux .
#   docker buildx build -f linux/packaging/Dockerfile --target shots --output docs/design/linux .
# The container opens no ports; it only runs tests and builds files.
FROM ubuntu:24.04 AS base
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-gi python3-gi-cairo python3-pytest \
      gir1.2-gtk-4.0 gir1.2-adw-1 gir1.2-secret-1 \
      adwaita-icon-theme librsvg2-common fonts-cantarell fonts-ubuntu \
      xvfb xauth dbus-x11 imagemagick dpkg-dev \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src

FROM base AS test
COPY linux/ linux/
COPY app/Packages/PulseKit/Tests/PulseCoreTests/Fixtures/ linux/tests/fixtures/
RUN cd linux && python3 -m pytest -q tests

FROM test AS build
ARG VERSION=0.1.0
RUN linux/packaging/build-deb.sh "$VERSION" /out

FROM scratch AS deb
COPY --from=build /out/ /

FROM test AS shoot
RUN cd linux && xvfb-run -a -s "-screen 0 1600x1200x24" dbus-run-session -- python3 tests/screenshots.py /shots

FROM scratch AS shots
COPY --from=shoot /shots/ /
