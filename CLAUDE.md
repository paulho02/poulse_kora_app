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

## Deploying (Railway)

`Dockerfile` (repo root) builds the web target with Flutter, then serves the static output via
nginx (`nginx.conf.template` + `docker-entrypoint.sh`, which substitutes Railway's injected `$PORT`
into the nginx config at container start — no Flutter/Nixpacks buildpack exists on Railway, hence
the explicit Dockerfile). `railway.json` wires it up as the Dockerfile builder with a `/` healthcheck.

`API_BASE_URL` and `BETA_DISCLAIMER_ENABLED` (see `core/config/app_config.dart`) are **build-time**,
not runtime — they're compiled into the JS bundle via `--dart-define`. They must exist as Railway
**service Variables** on this service; the Dockerfile declares matching `ARG`s in the build stage,
and Railway auto-populates any `ARG` from a same-named Variable with no extra config needed.

Because `API_BASE_URL` has to be known at build time, there's a one-time bootstrapping order when
standing up both services fresh: deploy the backend first, note its Railway domain, set that as this
service's `API_BASE_URL`, deploy this service, then go back and add *this* service's domain to the
backend's `BACKEND_CORS_ORIGINS` and redeploy the backend once more. Full details in the backend
repo's `RAILWAY.md`.

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
- `core/avatars/` — profile pictures. The backend serves them from an **authenticated** route, so
  they are deliberately *not* `Image.network`: `AvatarCache` fetches the bytes through the same Dio
  client as every other call and renders them with `Image.memory`. That cache is a long-lived
  mutable object behind a plain `Provider`, not a `FutureProvider.family`, because it has to outlive
  the widgets watching it — feed cards are disposed and rebuilt constantly while scrolling, and an
  auto-disposed family would re-request every image on every scroll. Three consequences to keep:
  failures (offline included) are cached as "no picture" so an offline feed can't storm the network,
  which is why `app.dart` calls `refresh()` on `backOnline`; the cache is also cleared at every
  session boundary, since it holds one account's faces; and because the URL is derived from the user
  id it does **not** change when a picture is replaced, so `ProfileNotifier` evicts the entry
  explicitly after an upload or delete. That last point is why the cache is a `ChangeNotifier`:
  eviction has to reach avatars *already on screen*, which cannot notice a swap by diffing their own
  unchanged inputs — without the notification a replaced picture stayed stale until an app restart.
  Hence two spellings of "drop everything": `refresh()` notifies (reconnect — the widgets needing
  another try are the mounted ones) and `clear()` stays silent (logout — waking them would only fire
  requests against a token being thrown away). `UserAvatar` renders picture-or-fallback and
  `MonogramAvatar` is the coloured initial; `features/feed/presentation/post_author_avatar.dart`
  wraps both with the anonymity rule for the three places a post is drawn.
  Setting a picture lives on the profile header's own avatar (`EditableProfileAvatar`), not in
  Settings — the profile view already shows the picture, so a settings row would be a second,
  less obvious answer to "where do I change this?". Picking is followed by `CropAvatarScreen`,
  which **always re-encodes to a 512px PNG**. That is what makes the upload's declared content type
  true by construction: `image_picker` re-encodes differently per platform (its web resizer goes
  through a canvas and emits PNG, Android emits JPEG, and neither renames the file), so anything
  derived from the picker's own output would have been a guess. Format validation is likewise
  Flutter's decoder rejecting the bytes, rather than an extension or magic-number check. The crop
  geometry is the one part that can be subtly wrong, so it is a pure function (`cropSourceRect`)
  tested on its own rather than only through the widget.
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

**Auth** lives in `features/auth/`. `authNotifierProvider` tracks token *presence* only (there is
no refresh-token flow); `app_router.dart`'s `redirect` chain guards routes in a fixed order —
signed-in, then email-verified, then onboarded — and a 401 from the Dio interceptor forces a logout
via `onUnauthorizedProvider`, while a 403 deliberately does not. Backend endpoints:
`POST /api/v1/auth/jwt/login`, `POST /api/v1/auth/register`, `POST /api/v1/auth/google`,
`GET/PATCH /api/v1/users/me`.

**Google sign-in** (`google_sign_in` 7.x) is an ID-token flow, not a redirect: the plugin yields a
Google ID token, `POST /auth/google` verifies it server-side and returns our own JWT. No deep links
or URL schemes are involved. Three things about it are load-bearing:
- **One client ID, two names.** `AppConfig.googleServerClientId` (a `--dart-define`, also wired
  into the `Dockerfile`) is passed as `serverClientId` on Android and `clientId` on web — the web
  plugin *asserts* `serverClientId` is null. See `features/auth/data/google_sign_in_service.dart`.
- **Web needs Google's own button.** `supportsAuthenticate()` is false there and `authenticate()`
  throws, so `google_sign_in_button.dart` is a conditional export (`dart.library.js_interop`) and
  the result arrives on `GoogleSignInService.idTokens` rather than from the call. Anything touching
  that file must be checked with `flutter build web` *and* `flutter build apk` — `flutter analyze`
  only ever sees the non-web branch.
- **Account identity is one-way.** Linking a password account to Google destroys its password, so
  `UserProfile.authProvider` (`"password"`/`"google"`) drives what the UI offers: Settings hides
  Change password, and only Google signups get the onboarding username step (the backend derived
  their name; password registrants typed one). The backend's 409 `google_link_required` is a
  *prompt*, not a failure — `GoogleAuthSection` turns it into the irreversibility dialog and
  re-sends the same ID token, which is why it is deliberately absent from `error_messages.dart`.
  The two entry points differ and have separate dialog copy: from the **login screen** the Google
  address *is* the account address (that is what matched them), whereas from **Settings** any
  Google account may be linked and the account keeps its own email as its contact address.

Session boundaries invalidate the account-scoped providers on the way **in** as well as out
(`_invalidateSessionScoped` in `app.dart`). Only invalidating on logout was not enough: the router
keeps a permanent listener on `profileProvider`, so logout's invalidation rebuilt it immediately
with the token already cleared, cached the resulting 401, and the next sign-in inherited that
"session expired" — `ref.read(...future)` is a no-op on a provider that already holds state.

### Localization (i18n)

The app ships English + German today, built to extend to more languages later. **Every
user-facing string is required to go through this system — a raw `Text('...')` literal in a
widget is a bug**, the same way a hardcoded English error message on the backend would be. This
applies to all new features, not just ones the user explicitly calls out as needing translation.

- **Source of truth**: `lib/l10n/app_en.arb` (template, with `@key` metadata for placeholders/ICU
  plurals) and `lib/l10n/app_de.arb` (translation, values only). Adding a string means adding it
  to *both* files, in the same change that introduces the widget using it — not as a follow-up.
  `flutter pub get` (or `flutter gen-l10n`) regenerates `lib/l10n/generated/` (gitignored); that
  directory is never hand-edited.
- **Usage**: `final l10n = AppLocalizations.of(context);` then `l10n.someKey` (or
  `l10n.someKey(arg)` for a parameterized/plural one). `nullable-getter: false` in `l10n.yaml`
  means `.of(context)` is non-null — never append `!`. Reference implementations:
  `core/errors/error_messages.dart` (the error-code-to-copy layer, including how the backend's
  structured password-policy violations get formatted) and
  `features/profile/presentation/settings_screen.dart` (the language picker).
- **German tone**: casual `du`-form, professional but warm — translate for *meaning*, not
  word-for-word. Loanwords already established in this app's German copy (`Feed`, `Token`,
  `Post`/`Beitrag`, `Score`) should stay loanwords rather than being forced into a stiffer native
  equivalent; avoid literal, nominalized, or passive-voice German (`Nominalstil`) even when it's
  what a direct translation would produce.
- **Locale resolution**: device locale by default, with a manual override in Settings → Language
  (`core/settings/locale_settings.dart`, persisted locally, never synced to the server — see
  `activeLocaleProvider`). The active locale is sent on every backend request as `Accept-Language`
  (`core/network/dio_client.dart`'s interceptor), which is what lets backend-authored text (the
  admin banner, password-policy messages) match the app's language too — see the backend's
  `app/core/locale.py` / `app/core/banner.py`.
- **Exceptions** (deliberately left untranslated): the `Relay` brand name, and example/placeholder
  URLs (e.g. `server_settings_sheet.dart`'s hint text) — URLs aren't translated by convention.
