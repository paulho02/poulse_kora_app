# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Flutter client app for Poulse Kora. Its backend is the sibling repo `poulse_kora_backend`
(FastAPI + `fastapi-users` JWT auth + Postgres) — see that repo's `CLAUDE.md` for API details.
The backend's React Admin frontend is unrelated/disabled; this Flutter app is the actual product
client going forward.

Scaffolded with `flutter create` on Flutter 3.44.5 / Dart 3.12.2 (stable), org
`com.poulsekora`, applicationId `com.poulsekora.poulse_kora_app`. Targets: Android, Web (iOS/desktop
not enabled — add with `flutter create --platforms=ios .` etc. if needed later).

## Commands

```bash
flutter pub get                      # install dependencies
flutter analyze                      # static analysis / lints (flutter_lints)
flutter test                         # run all tests
flutter test test/widget_test.dart   # run a single test file
flutter run                          # run on a connected device/emulator/browser
flutter run -d chrome --web-port=3000   # run in a browser; port must be 3000, see below
flutter devices                      # list available run targets
flutter pub add <package>            # add a dependency
flutter pub outdated                 # check for newer package versions
```

The backend must be running (`docker compose up -d` in `poulse_kora_backend`) for anything that
hits the network to work — see Architecture below for how the base URL is resolved.

**Web CORS gotcha**: the backend's `BACKEND_CORS_ORIGINS` (`.env`) only whitelists
`http://localhost:3000`/`http://127.0.0.1:3000`. Flutter's web dev server otherwise binds a random
port, which the browser then blocks via CORS. Always run web with `--web-port=3000`, or add the
port you need to the backend's `.env`.

## Architecture

Feature-first layout under `lib/src/`, each feature split into `data/` (repositories talking to
the backend), `application/` (Riverpod providers/state), `presentation/` (widgets/screens):

- `core/config/app_config.dart` — resolves the backend base URL. Reads `API_BASE_URL` from
  `--dart-define` first; otherwise defaults per platform (`10.0.2.2:8000` on Android emulator,
  since it can't reach the host via `localhost`; `localhost:8000` elsewhere). API path prefix is
  `/api/v1`, matching the backend's `settings.API_PATH`.
- `core/network/dio_client.dart` — single `Dio` instance per app (via `dioClientProvider`), with
  an interceptor that reads the JWT from `TokenStorage` and sets `Authorization: Bearer <token>`
  on every outgoing request. Any new repository should take this `Dio` instance rather than
  creating its own.
- `core/storage/token_storage.dart` — `flutter_secure_storage` wrapper, currently just the access
  token (`fastapi-users` issues a single JWT bearer token, no refresh token flow). It **caches the
  token in memory** after the first read and dedupes concurrent cold reads, because the interceptor
  attaches it to every request and each keystore read is a native round trip plus a decrypt. Keep
  `saveAccessToken`/`clear` as the only writers, so the cache can't go stale.
- `core/providers.dart` — top-level Riverpod providers (`tokenStorageProvider`, `dioClientProvider`)
  that feature-level providers build on top of.
- `routing/app_router.dart` — `go_router` config as a Riverpod provider (`routerProvider`), so
  routes can later depend on auth state (e.g. redirect logic reading `tokenStorageProvider`).
- `features/home/` — reference implementation of the data → application → presentation pattern:
  calls the backend's `/hello-world` endpoint as an end-to-end connectivity check. Copy this shape
  for new features rather than inventing a new structure.

### Offline behaviour

The app stays usable without a connection. Four rules that new code must not break:

- **Preferences render from `core/settings/app_settings.dart`, never from the server profile.**
  `appSettingsProvider` is the source of truth for `themeMode`; `profileProvider` is only a *sync
  input* to it. Deriving the theme from a network call is what used to break dark mode offline.
  Reconciliation is `decideSettingsSync` — it branches on a local `dirty` flag, not on comparing
  timestamps, and on a genuine two-device conflict the local value wins. The server's
  `settings_revision` (bumped only by settings PATCHes) is what detects that conflict.
- **Reads fall back to cache; writes do not queue.** `core/cache/cached_fetch.dart` wraps each
  read: write-through on success, serve the last good copy on a *connection* failure only — never
  on a 4xx, which is a real answer and must surface. Writes fail with a message instead of being
  replayed later, because reviews are guarded server-side by the Redis queue and posts are priced
  at request time. Controls are never disabled by connectivity.
- **All errors go through `core/errors/`.** `asRelayException` unwraps the `DioException` Dio
  rethrows (`AsyncValue.guard` hands widgets the wrapper, not the failure inside it); `messageFor`
  maps the backend's `detail.error` code to copy. Never render an exception's `toString()`.
  When reporting an error after an await that may unmount the widget — an optimistic review
  unmounts its `PostCard` — capture the `ScaffoldMessenger` first and use `showErrorSnackBarOn`.
- **Session boundaries are handled centrally**, in `PoulseKoraApp`'s `authNotifierProvider`
  listener. Logging out clears the token, the cache and local settings, but the providers holding
  fetched data are keep-alive and survive it — so they're invalidated there. Signing in then warms
  `profileProvider` to pull the new account's preferences; without that, `ref.read` on a provider
  that still held state was a no-op and the theme silently stayed on defaults.
- **Riverpod's auto-retry is disabled for connectivity failures** (`_retryPolicy` in `main.dart`).
  Left on, a provider offline with no cache retries for minutes while pinned in `loading`, so the
  screen never reaches its error state. `ConnectivityNotifier` owns recovery instead: it polls
  `/api/v1/health` on a backoff, and `PoulseKoraApp` re-runs whatever failed on reconnect.

State management is plain Riverpod (`Provider`, `FutureProvider`, `ConsumerWidget`) — no
`riverpod_generator`/`build_runner` code generation is wired up. If a feature needs mutable state
beyond a `FutureProvider`, prefer `NotifierProvider`/`AsyncNotifierProvider` over introducing a new
pattern.

There is no auth flow implemented yet (login/register screens, token refresh-on-401 handling,
route guards) — `core/network` and `core/storage` exist specifically so that work has somewhere to
plug in. The backend's auth endpoints are `POST /api/v1/auth/jwt/login`,
`POST /api/v1/auth/register`, `GET/PATCH /api/v1/users/me` (see backend `app/deps/users.py`).
