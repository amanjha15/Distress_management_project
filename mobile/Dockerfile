# Railway build for the Flutter web frontend. Builds the static web app,
# then serves it with nginx on Railway's dynamic $PORT.

FROM ghcr.io/cirruslabs/flutter:stable AS build
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
