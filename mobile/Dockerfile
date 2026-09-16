# Railway build for the Flutter web frontend. Builds the static web app,
# then serves it with nginx on Railway's dynamic $PORT.

FROM debian:bookworm-slim AS build

# The ghcr.io/cirruslabs/flutter:stable image's checkout lags patch
# releases (shipped Dart 3.12.0 while pubspec.yaml requires ^3.12.2) and
# its git checkout is too shallow for `flutter channel`/`flutter upgrade`
# to fix in-place. Installing a pinned SDK straight from Flutter's own
# archive sidesteps both problems -- 3.44.6 is the first stable release
# bundling Dart 3.12.2.
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates xz-utils git \
    && rm -rf /var/lib/apt/lists/*

ENV FLUTTER_VERSION=3.44.6
RUN curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" -o /tmp/flutter.tar.xz \
    && tar -xf /tmp/flutter.tar.xz -C /opt \
    && rm /tmp/flutter.tar.xz
ENV PATH="/opt/flutter/bin:${PATH}"
RUN git config --global --add safe.directory /opt/flutter \
    && flutter config --no-analytics \
    && flutter precache --web

WORKDIR /app
COPY . .

# Railway auto-passes any Dockerfile ARG that matches a variable set on this
# service, so set API_BASE_URL as a service variable pointing at the
# backend's Railway public URL (e.g. https://backend-production-xxxx.up.railway.app)
# before the first deploy -- it's baked into the JS bundle at build time,
# not read at runtime, so changing it later requires a redeploy.
ARG API_BASE_URL
RUN flutter pub get \
    && flutter build web --release --dart-define=API_BASE_URL=${API_BASE_URL}

FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
COPY nginx.railway.conf.template /etc/nginx/templates/default.conf.template

# Fallback for local `docker build && docker run` testing; Railway overrides
# this with its own dynamic PORT at runtime.
ENV PORT=8080
EXPOSE 8080
