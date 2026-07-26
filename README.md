# poulse_kora_app

Flutter client for Poulse Kora. Talks to the [poulse_kora_backend](../poulse_kora_backend) FastAPI
service.

## Getting started

```bash
flutter pub get
flutter run -d chrome --web-port=3000   # or -d <android-device-id>, see `flutter devices`
```

By default the app points at the backend's local docker-compose setup
(`http://localhost:8000`, or `http://10.0.2.2:8000` on the Android emulator, which aliases the
host machine). Make sure the backend is running (`docker compose up -d` in `poulse_kora_backend`,
then `docker compose exec backend alembic upgrade head`).

`--web-port=3000` matters: the backend's `BACKEND_CORS_ORIGINS` (in its `.env`) only whitelists
`http://localhost:3000`. Flutter's web dev server otherwise picks a random port each run, which
the browser's CORS check will then reject. If you need a different port, add it to
`BACKEND_CORS_ORIGINS` in the backend's `.env`.

Override the backend URL at run/build time:

```bash
flutter run --dart-define=API_BASE_URL=https://api.example.com
```

For local dev (e.g. running on a real Android device on your LAN, where neither `localhost` nor
`10.0.2.2` reaches the host machine), copy `env.example.json` to `env.json` and set your machine's
LAN IP:

```bash
cp env.example.json env.json   # then edit API_BASE_URL to your machine's LAN IP
flutter run --dart-define-from-file=env.json
```

`env.json` is gitignored since the right IP is per-machine/per-network.

## Commands

```bash
flutter analyze          # static analysis / lints
flutter test              # widget & unit tests
flutter test test/some_test.dart   # single test file
flutter run                # run on a connected device/emulator/browser
flutter devices            # list available targets
```

## Architecture

Feature-first structure under `lib/src/`:

- `core/config/app_config.dart` — backend base URL resolution (env override + per-platform default).
- `core/network/dio_client.dart` — shared `Dio` instance, attaches the stored JWT bearer token to
  every request via an interceptor.
- `core/storage/token_storage.dart` — `flutter_secure_storage` wrapper for the JWT access token.
- `core/providers.dart` — Riverpod providers wiring the above together.
- `routing/app_router.dart` — `go_router` config (`routerProvider`).
- `features/<feature>/data|application|presentation` — one folder per feature, e.g.
  `features/home` shows the pattern: a `Repository` (data), a Riverpod `Provider`/`FutureProvider`
  (application), and a `ConsumerWidget` screen (presentation). Follow this pattern for new features
  (e.g. `features/auth` for login/register against the backend's `fastapi-users` endpoints at
  `/api/v1/auth/...`).

State management: Riverpod (`flutter_riverpod`), plain `Provider`/`FutureProvider`s — no code
generation (`riverpod_generator`) set up yet.
