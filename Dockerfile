# Multi-stage: compile the Flutter web bundle, then serve the static output
# with nginx. Flutter has no Railway/Nixpacks buildpack, hence the explicit
# Dockerfile (mirrors the backend repo's approach).
#
# Installs the official Flutter SDK directly from Google's release archive
# rather than a third-party mirror image (e.g. cirruslabs/flutter, which only
# publishes 3.44.0 at time of writing — behind this app's pubspec.yaml
# constraint of Dart >=3.12.2, bundled starting with Flutter 3.44.6). Bump
# FLUTTER_VERSION here if pubspec.yaml's `sdk:` constraint moves further.
FROM debian:bookworm-slim AS build

ARG FLUTTER_VERSION=3.44.6

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates git xz-utils \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
        -o /tmp/flutter.tar.xz \
    && tar -xf /tmp/flutter.tar.xz -C /opt \
    && rm /tmp/flutter.tar.xz

ENV PATH="/opt/flutter/bin:${PATH}"

RUN git config --global --add safe.directory /opt/flutter \
    && flutter config --no-analytics --enable-web \
    && flutter precache --web

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .

# Declared in this stage only — build-time inputs, baked into the compiled JS
# bundle. Railway auto-populates these from service Variables of the same
# name; nothing else to configure. See app/src/core/config/app_config.dart.
ARG API_BASE_URL
ARG BETA_DISCLAIMER_ENABLED=true
# Google OAuth *web* client ID. Empty (the default) hides the Google button;
# the backend's own GOOGLE_OAUTH_ENABLED has to agree as well.
ARG GOOGLE_SERVER_CLIENT_ID=
# Self-hosted-backend picker on the login screen. The web build never offers
# it regardless (see server_settings_sheet.dart); kept here so one variable
# governs every target.
ARG CUSTOM_SERVER_ENABLED=false

RUN flutter build web --release \
    --dart-define=API_BASE_URL=${API_BASE_URL} \
    --dart-define=BETA_DISCLAIMER_ENABLED=${BETA_DISCLAIMER_ENABLED} \
    --dart-define=GOOGLE_SERVER_CLIENT_ID=${GOOGLE_SERVER_CLIENT_ID} \
    --dart-define=CUSTOM_SERVER_ENABLED=${CUSTOM_SERVER_ENABLED}

FROM nginx:alpine

COPY --from=build /app/build/web /usr/share/nginx/html
COPY nginx.conf.template /etc/nginx/nginx.conf.template
COPY docker-entrypoint.sh /docker-entrypoint.sh

RUN chmod +x /docker-entrypoint.sh

EXPOSE 8080

ENTRYPOINT ["/docker-entrypoint.sh"]
