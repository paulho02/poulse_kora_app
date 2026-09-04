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
- **Media loading** (`core/media/presentation/network_media_image.dart`) — every image in the app,
  avatars and post photos alike, is a plain `Image.network` on the URL the backend returned.
  That is only true because media moved out of Postgres and into an S3-compatible bucket: the
  backend now returns **presigned URLs** whose query-string signature *is* the authorization
  (see `app/core/storage.py` in the backend repo). Three rules follow, and all three are the
  opposite of what this app used to do:
  - **Never attach the bearer token, and never rewrite the URL.** S3 rejects a request carrying
    both a query signature and an `Authorization` header, and the signature covers the path and
    the query, so touching either 403s every image. This replaced an `AuthenticatedByteCache`
    that fetched bytes through Dio and rendered `Image.memory`, plus its API-relative path
    munging — both existed purely because the old routes required the token.
    `test/network_media_image_test.dart` pins it.
  - **No hand-written cache.** Flutter's `ImageCache` (and the browser's HTTP cache on web) does
    it, and does it better. It works here only because the backend keeps a presigned URL
    byte-identical for ~15 min instead of re-signing per request, and stamps every object
    `Cache-Control: private, max-age=86400, immutable`. The one thing Flutter cannot do by
    itself is re-resolve a *settled* failure, which is what `mediaReloadProvider` is for:
    `app.dart` calls `reload()` on `backOnline` (an image that failed while offline would
    otherwise stay a fallback all session) and at every session boundary (the image cache is
    keyed by URL and would happily paint the previous account's faces).
  - **A replaced profile picture needs no eviction.** Every upload writes a new object key, so
    the URL genuinely changes and the widget reloads because its inputs did. The old URL was
    derived from the user id and identical before and after, which is why `ProfileNotifier` used
    to have to evict explicitly and the cache had to be a `ChangeNotifier` to reach avatars
    already on screen. All of that is gone.
  On web this is also what dodges CORS: a cross-origin byte fetch needs CORS on the bucket, and
  a Railway Bucket offers no way to set one (its credentials have no `s3:PutBucketCors`). So
  images pass `webHtmlElementStrategy: fallback` — normal byte-fetching, dropping to an `<img>`
  element only if the fetch is blocked — and video needs nothing, since `video_player_web`
  renders into a bare `<video>` element, which is not CORS-gated.
- `core/avatars/` — profile pictures. `UserAvatar` renders picture-or-fallback over
  `NetworkMediaImage` and `MonogramAvatar` is the coloured initial;
  `features/feed/presentation/post_author_avatar.dart` wraps both with the anonymity rule for the
  three places a post is drawn. There is deliberately no spinner: an avatar is decoration around a
  name that already reads fine, and swapping a spinner for an image makes every feed card jitter
  on scroll.
  Setting a picture lives on the profile header's own avatar (`EditableProfileAvatar`), not in
  Settings — the profile view already shows the picture, so a settings row would be a second,
  less obvious answer to "where do I change this?". Picking is followed by `CropAvatarScreen`,
  a thin wrapper over the shared `core/media/presentation/crop_media_screen.dart`, which
  **always re-encodes to PNG** (512px square, here). That is what makes the upload's declared
  content type true by construction: `image_picker` re-encodes differently per platform (its web
  resizer goes through a canvas and emits PNG, Android emits JPEG, and neither renames the file),
  so anything derived from the picker's own output would have been a guess. Format validation is
  likewise Flutter's decoder rejecting the bytes (`decodeImageBytes`), rather than an extension or
  magic-number check. The crop geometry is the one part that can be subtly wrong, so it lives in
  `core/media/presentation/crop_geometry.dart` as pure functions (`cropSourceRect`, `fitAspectRatio`,
  `outputSizeFor`) tested on their own rather than only through the widget.
- `core/media/` — **post attachments**. Three rules, all downstream of one decision: every
  published attachment is one of **two fixed shapes**, 4:3 wide or 4:5 upright
  (`post_media_format.dart`, mirroring the backend's `POST_MEDIA_*_RATIO` — kept in sync by hand,
  and a drift surfaces as a `post_media_invalid_aspect_ratio` rejection rather than silently).
  A single-column feed reads far better for it, and a media block can size itself from
  `PostMedia.width/height` before a byte has arrived instead of reflowing as each image decodes.
  - **A photo is cropped here; a video is not.** The composer pushes `CropMediaScreen` per picked
    photo — mandatory, not offered, since the backend rejects any other ratio, so a "skip" would
    only build an upload that fails later; backing out drops *that* photo and moves on. A Flutter
    client has no video encoder, so a clip instead gets `showVideoOrientationSheet` and the server
    center-crops it inside the transcode it already runs (`ComposerBlockInput.orientation`, sent
    for videos only).
  - **A video is never a black rectangle.** The backend stores a poster frame as its own object
    beside every clip; `PostMedia.previewUrl` resolves to it, and `PostMediaPreview` renders it —
    so a feed card and an unplayed inline block both show a real frame, at the cost of one small
    JPEG rather than any of the clip's bytes. Both `posterUrl` and `width`/`height` are nullable
    (old rows, and deliberately non-fatal poster extraction), and **null means "unknown shape,
    letterbox it"** — never "assume a default", which would crop an old post's photo in half.
  - **The player is pointed straight at the media URL, on every platform.** That deleted a
    web-only path worth remembering: while media came from an authenticated backend route, a
    browser `<video>` could not fetch it (an element cannot carry an `Authorization` header), so
    web downloaded the whole clip through Dio and handed the player a `blob:` URL — up to
    `POST_VIDEO_MAX_BYTES` in memory before the first frame. A presigned URL needs no header, so
    the browser now streams it with range requests like every other platform already did.
  - **The player chrome is ours, not chewie's** (`core/media/presentation/video_player_surface.dart`,
    mounted by `InlineMediaBlock` once the poster is tapped). chewie's material controls are built
    for long-form video — two ten-second seek buttons flanking play, an options bar, and a
    `black54` sheet over the whole frame — and all of it is driven by chewie's `PlayerNotifier`,
    so it sat on top of a clip of at most a minute whether it was playing or paused. The rule here
    is that **playing means nothing on screen**: the chrome auto-hides ~2.2s after the last touch,
    a tap brings it back, and a *paused* clip keeps it (hiding it would leave a still frame with no
    way back in). Two further consequences of the same rule, and neither should be undone: **every
    control sits in one row along the bottom edge**, play/pause included, so nothing is ever drawn
    on the picture (a centred play glyph belongs on the *poster*, where it is the only affordance
    there is, not over moving video), and **the clip loops** rather than ending on a frozen frame
    under a replay button — pausing is how it stops. A bottom gradient rather than a full-surface
    scrim, for the same reason the poster frame exists: a clip is never a dark rectangle, and a
    scrim would put that back. `wakelock_plus` is a direct dependency because chewie held the
    screen awake and a 60-second clip still needs that.
  - **Exactly one clip plays at a time, and only while it is on screen.** `InlineMediaBlock`
    claims `activeVideoProvider` (`core/media/application/active_video.dart`) whenever its player
    starts — from the controller, not from the button, so every entry point counts — and pauses
    itself the moment someone else claims it; it also pauses when less than a quarter of the block
    is left in the viewport (via the enclosing `ScrollPosition`) and when the app is backgrounded.
    This is not tidiness: leaving a scrolled-past clip running is what produced both playback bugs
    a post with several videos used to have — a clip heard but not seen (its audio under the one
    being watched), and a clip stuck on a spinner forever (two streams competing for Android's
    decoders). The blocks *pause* rather than tear the controller down, so scrolling back
    resumes where you left off instead of returning to the poster with the download to redo.
  - A feed card is a *preview*, so `PostMediaThumbnail` clamps to `minAspectRatio` (square): a 4:5
    photo at true shape is ~440dp tall on a phone and pushes the drop/forward buttons off screen.
    The full shape is what the opened post shows.
- `features/home/` — reference implementation of the data → application → presentation pattern:
  calls the backend's `/hello-world` endpoint as an end-to-end connectivity check. Copy this shape
  for new features rather than inventing a new structure.

### Reading a post

Opening a post is a **full-screen route**, not a bottom sheet: `slideUpRoute`
(`core/presentation/slide_up_route.dart`) keeps the slide-from-bottom motion a sheet had, because
that part was right, and drops the size cap, because a post is mostly media and a sheet kept a
barrier and rounded corners over the top of the picture however far it was dragged.
`PostDetailScaffold` is the shared chrome for both the feed's reviewable post and history's
read-only one, which used to be near-identical copies. Two things follow from having the whole
screen and should not be undone: media is **full-bleed** (text keeps its reading margin —
`PostBlocksView`'s `fullBleed`), and the drop/forward footer is **pinned** rather than appended
after the article, so acting on a long post no longer means scrolling to the end of something you
had already decided about.

### Refreshing history

`PostHistoryScreen` offers both an app-bar button and pull-to-refresh, and the button drives the
`RefreshIndicator` through its `GlobalKey` rather than running its own fetch — one gesture, one
spinner, one code path (it falls back to the provider only before a first page exists, when there
is no indicator mounted). Two details are load-bearing and were exactly where the gesture used to
die: the **empty state lives inside the indicator** (a bare `Center` cannot be pulled, and "you
haven't posted anything yet" is precisely when someone pulls to check again), and the
`ScrollablePositionedList` is given **`AlwaysScrollableScrollPhysics`** (default physics refuse the
drag on a list that fits on screen, so the shortest histories were the un-refreshable ones). Both
are covered by `test/history_refresh_test.dart`. A refresh invalidates the provider, which drops
every loaded page and resets the pager's `hasMore` — deliberate, so an exhausted history can be
paged again.

### The token economy in the UI

`EconomyHeaderStatus` takes an `EconomyBarVariant` and states **one fact** per screen, as a pill
among the app bar's `actions`: a number, the clause that says what the number means, and a bar
filling toward affording a post. The **feed** variant is the balance and how far it is from a post
("12 · 2 more tokens to post"). The **composer** variant is `−3`, what this post takes off that
balance, and its clause is the **price-lock countdown** ("−3 · held for 4:32") — the composer is
the screen you sit in for minutes while the quote's window runs out, so that is where the clock
belongs, and it stays worded as the promise it is rather than shown as a bare `4:32`, which reads
as a deadline to race. The clause gives way to "2 more needed" (and the pill to `errorContainer`)
when the balance can't cover the post, since how long an unaffordable price holds is nobody's
question; it falls back to "of your 12" for a cached quote with no expiry, and to "checking price…"
once expired or stale — which is also when `_ComposerPill` re-fetches. A full bar means "you can
post", which is why the feed never needs the price as a number.

What changed is *how much room this gets*, not what it says: both variants used to be full-width
bars stacked under the app bar, a permanent row of chrome on the two screens with the least space
to spare. Two rules keep it that way. The clause is **one line, width-capped** against the screen
(`_labelCap`) — app bar actions get unbounded width, so nothing else would stop a long translation
from pushing the title off the left edge, and the full sentence is on the tooltip either way.
Anything longer than that clause belongs in `showEconomyExplainerSheet`, reachable by tapping
either pill — that is the one place the model is spelled out, and it opens with the live figures
precisely because no bar states them any more. New economy copy goes there rather than growing the
pill.

Two things the bars used to do still need doing and now happen elsewhere. The composer's price
quote expires, so `_ComposerPill` keeps a timer and re-fetches when it lapses (retrying, since
`refresh()` swallows connectivity failures) — it just no longer renders a countdown. And "you
need 2 more tokens", which was permanent chrome for everyone including the people it didn't
concern, is now `_ShortOnTokensHint`: one line, only while it applies, directly above the disabled
Relay button it explains.

### Chrome that yields to content

Both main screens are mostly other people's content, and the rule for anything else on them is
that it has to earn a permanent row. Three consequences worth keeping:

- **The feed's channel filter has two sizes.** `_ChannelFilter` cross-fades between the row of
  chips and a one-line summary of what is being read, driven by `UserScrollNotification`
  *direction* rather than by scroll offset: reaching back up for the filter is then the same
  gesture as reaching back up the feed, instead of a header that snaps open at some magic pixel.
  The collapsed line is the same control — tapping it brings the chips back, so the filter is
  never more than one tap away from wherever the feed has been scrolled to. Note the listener
  ignores horizontal notifications, since the chip row is itself a scroll view.
- **The feed's app bar dropped the open-post count.** It was a number nobody acts on (the queue is
  whatever it is, and the count moves on its own), and the title bar was worth more as the place
  the token pill lives.
- **The composer's publish row holds all three publishing decisions**: anonymous, channel, Relay.
  The channel picker used to be a full-width labelled field above the editor — a whole row for one
  word chosen once — and is now `_ChannelSelectorChip`, outlined in the primary colour while
  unpicked so a required-but-open choice still looks like one. The picker sheet behind it is
  unchanged.

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
