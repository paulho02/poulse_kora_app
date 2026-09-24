# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

## Project

Flutter client for Peerkola. The backend is the sibling repo
`poulse_kora_backend` (FastAPI, `fastapi-users` JWT auth, Postgres, Redis, S3 bucket) — its
CLAUDE.md holds the API rationale this file refers to. Flutter 3.44.x stable / Dart 3.12, org
`com.peerkola`, applicationId `com.peerkola.app`. Targets: Android and Web
(add iOS with `flutter create --platforms=ios .` if ever needed).

## Commands

```bash
flutter pub get                          # deps; also regenerates lib/l10n/generated/
flutter analyze
flutter test
flutter test test/widget_test.dart
flutter run                              # connected device/emulator
flutter run -d chrome --web-port=3000    # port must be 3000, see below
flutter run --dart-define-from-file=env.json   # physical device: cp env.example.json env.json, set your LAN IP
flutter devices
flutter pub add <package>
flutter pub outdated
```

The backend must be running (`docker compose up -d` in `poulse_kora_backend`). **Web CORS**: the
backend's `BACKEND_CORS_ORIGINS` whitelists only `localhost:3000`/`127.0.0.1:3000`; Flutter's web
dev server otherwise binds a random port the browser then blocks. `env.json` is gitignored
(per-machine IP).

## Deploying (Railway)

`Dockerfile` builds the web target and serves it via nginx (`nginx.conf.template` +
`docker-entrypoint.sh`, which substitutes Railway's `$PORT` at container start); `railway.json`
wires it as the Dockerfile builder with a `/` healthcheck. `API_BASE_URL`,
`BETA_DISCLAIMER_ENABLED`, `GOOGLE_SERVER_CLIENT_ID` and `CUSTOM_SERVER_ENABLED`
(`core/config/app_config.dart`) are **build-time** `--dart-define`s, declared as `ARG`s in the
Dockerfile and auto-filled from same-named Railway service Variables. Bootstrapping order for a fresh pair of services: deploy
the backend, put its domain in this service's `API_BASE_URL`, deploy this, then add this domain to
the backend's `BACKEND_CORS_ORIGINS` and redeploy it. Details in the backend's `RAILWAY.md`.

## Architecture

Feature-first under `lib/src/`: each feature has `data/` (repositories), `application/` (Riverpod
providers/state), `presentation/` (widgets/screens). Plain Riverpod (`Provider`, `FutureProvider`,
`ConsumerWidget`), no codegen; for mutable state prefer `NotifierProvider`/`AsyncNotifierProvider`.
`features/channels/` or `features/history/` are the shape to copy for a new feature.

Core plumbing:
- `core/config/app_config.dart` — base URL: `API_BASE_URL` dart-define, else `10.0.2.2:8000` on
  the Android emulator (can't reach the host as `localhost`), `localhost:8000` elsewhere. Prefix
  `/api/v1` matches the backend's `API_PATH`.
- `core/config/server_config.dart` — the login screen's self-hosted-backend picker
  (`ServerSettingsButton`), persisted in `SharedPreferences` and read synchronously so the first
  `dioClientProvider` build already has the right base URL. **Off unless
  `CUSTOM_SERVER_ENABLED=true`** (off for the MVP: there is only the official server, and "which
  server?" is a question nobody else can answer). `ServerConfigStore.isSupported` folds that flag
  with `!kIsWeb` — both compile-time constants, so a build with it off tree-shakes the sheet away
  — and gates the *store*, not just the button: an install that saved a custom URL under an
  earlier build would otherwise keep talking to it with no UI left to undo it. The stored key
  survives, so flipping the flag back on restores the previous choice.
- `core/network/dio_client.dart` — one `Dio` (`dioClientProvider`); its interceptor sets
  `Authorization: Bearer` from `TokenStorage` and `Accept-Language` from the active locale. New
  repositories take this instance.
- `core/storage/token_storage.dart` — `flutter_secure_storage` wrapper for the single access
  token (no refresh flow). Caches in memory and dedupes concurrent cold reads, since every request
  reads it and a keystore read is a native round trip. `saveAccessToken`/`clear` are the only
  writers, so the cache can't go stale.
- `core/providers.dart` (top-level providers), `routing/app_router.dart` (`routerProvider`,
  go_router, so routes can depend on auth state).

### Media loading

Every image is a plain `Image.network` on the **presigned URL** the backend returned
(`core/media/presentation/network_media_image.dart`); the query-string signature *is* the
authorization. Three rules, each the opposite of what this app once did:
- **Never attach the bearer token, never rewrite the URL.** S3 rejects a request carrying both a
  query signature and an `Authorization` header, and the signature covers path and query.
  `test/network_media_image_test.dart` pins it.
- **No hand-written cache.** Flutter's `ImageCache` (and the browser's) does it, viable because
  the backend keeps a URL byte-identical for ~15 min and stamps objects `Cache-Control: private,
  max-age=86400, immutable`. What Flutter can't do is re-resolve a *settled* failure — that is
  `mediaReloadProvider`: `app.dart` calls `reload()` on `backOnline` and at every session boundary
  (the cache is keyed by URL and would paint the previous account's faces).
- **A replaced profile picture needs no eviction**: every upload writes a new key, so the URL
  changes and the widget reloads on its own.
On web, images pass `webHtmlElementStrategy: fallback` (byte fetch, dropping to an `<img>` only
when CORS blocks it — a Railway Bucket allows no CORS config); video needs nothing, since
`video_player_web` renders a bare `<video>`, which isn't CORS-gated. Debug builds log
`media.load_failed` with host and path only — never the query string, which is the read capability.

**The bucket is a second host and fails on its own.** Media comes from `S3_PUBLIC_ENDPOINT_URL`
(MinIO on port **9000** locally, a Railway Bucket in prod), not the API. "The app ignored my
upload" is usually the bucket being unreachable from the device: the `PUT` succeeds, `GET
/users/me` returns the picture, and the monogram still shows — because `UserAvatar` renders
`fallback` for loading, no-picture and failed-fetch alike. Open
`http://<lan-ip>:9000/minio/health/live` in the phone's browser before touching Dart. The host is
part of what is signed, so "point it at localhost" is not a fix — that is why the backend has
`S3_PUBLIC_ENDPOINT_URL` beside `AWS_ENDPOINT_URL`.

### Avatars

`core/avatars/`: `UserAvatar` (picture-or-fallback over `NetworkMediaImage`) and `MonogramAvatar`;
`features/feed/presentation/post_author_avatar.dart` applies the anonymity rule for every place a
post is drawn. No spinner — an avatar is decoration beside a name, and swapping spinner for image
jitters every card. Setting one lives on the profile header's own avatar (`EditableProfileAvatar`),
not in Settings. Picking goes through `CropAvatarScreen`, a wrapper over the shared
`core/media/presentation/crop_media_screen.dart`, which **always re-encodes to PNG** (512px square)
— that is what makes the declared content type true: `image_picker` emits PNG on web and JPEG on
Android and renames nothing. Format validation is Flutter's decoder (`decodeImageBytes`), not an
extension check. Crop geometry is pure functions in `crop_geometry.dart`, tested directly.

### Post attachments

Every attachment is one of **two fixed shapes**, 4:3 or 4:5 (`post_media_format.dart`, mirroring
the backend's `POST_MEDIA_*_RATIO` by hand — drift surfaces as `post_media_invalid_aspect_ratio`).
A media block can size itself from `PostMedia.width/height` before a byte arrives.
- **A photo is cropped here; a video is not.** The composer pushes `CropMediaScreen` per photo —
  mandatory, since the backend rejects any other ratio; backing out drops that photo. Flutter has
  no video encoder, so a clip gets `showVideoOrientationSheet` and the server center-crops inside
  its transcode (`ComposerBlockInput.orientation`, videos only).
- **A video is never a black rectangle**: `PostMedia.previewUrl` resolves to the backend's poster
  frame and `PostMediaPreview` renders it. `posterUrl` and `width`/`height` are nullable, and
  **null means "unknown shape, letterbox it"** — never a default, which would crop an old photo.
- **The player is pointed straight at the media URL on every platform**; a presigned URL needs no
  header, so the browser streams with range requests like everyone else.
- **The player chrome is ours** (`video_player_surface.dart`, mounted by `InlineMediaBlock` once
  the poster is tapped; chewie was removed, `wakelock_plus` stays a direct dependency). Rule:
  **playing means nothing on screen** — chrome auto-hides ~2.2s after the last touch, a tap brings
  it back, a paused clip keeps it. Consequences not to undo: every control sits in one bottom row
  so nothing is drawn over the picture (a centred play glyph belongs on the *poster* only); the
  clip loops rather than ending under a replay button; a bottom gradient, not a full scrim.
- **Exactly one clip plays at a time, and only on screen.** `InlineMediaBlock` claims
  `activeVideoProvider` (`core/media/application/active_video.dart`) from the controller — so every
  entry point counts — and pauses when someone else claims it, when under a quarter of the block
  is visible, or when the app is backgrounded. This is what fixed audio playing under another clip
  and clips stuck on a spinner (two streams competing for Android's decoders). Blocks *pause*
  rather than dispose, so scrolling back resumes.
- A feed card is a preview: `PostMediaThumbnail` clamps to square (a 4:5 photo at true shape
  pushes the drop/forward buttons off a phone screen).

### Feedback (`features/feedback/`)

The form (`/feedback`) is reachable from the login and register screens as well as the profile,
and that constraint shapes three things:
- **The route sits outside every redirect gate** — `app_router.dart`'s `redirect` early-returns for
  `/feedback` before the signed-in/verified/onboarded chain. The backend accepts it unauthenticated.
- **Signed out, anonymity is shown locked on**, and "you can contact me" isn't offered. Signed in,
  choosing anonymity hides the contact option (the backend stores no user id for one). The screen
  mirrors the backend's rules; it doesn't enforce them.
- **Attachments skip the cropper** (a screenshot has no shape to choose), so content type comes
  from `core/media/image_content_type.dart` sniffing bytes, and the picker gets no
  `maxWidth`/`maxHeight` (those re-encode a PNG screenshot into JPEG with ringing on the text being
  reported). Unsupported files are caught locally.
Consent is a line above the button, not a disabled button — same rule as the composer's
`_PublishBlocker`. The screen uses `Navigator`, not `GoRouter`, so it mounts anywhere.

### Onboarding and tutorial

`OnboardingScreen` (`features/onboarding/`) is the router-forced post-registration flow
(`intro → tutorial offer → [tutorial] → [username] → channels → languages → disclaimer`); the deck
in `features/tutorial/` is the long explanation, offered rather than imposed.
- **The offer is a question with two equal buttons** (`TutorialOfferStep`), not a "learn more"
  link — declining must be a decision, and the "start it anytime from Settings" hint sits on that
  screen because the person who most needs it just said no.
- **The deck is a widget first, a route second.** Onboarding embeds `TutorialDeck`; `/tutorial`
  (Settings → How Relay works) wraps it in `TutorialScreen`. It can't be a route inside the flow:
  while `onboardingCompleted` is false the router bounces every other location back.
- **The five chapters are a chain of consequences** — travels by hand (1) → no ranking model (2)
  → the decision is yours (3) → so it's priced (4) → so the feed is finite (5). Chapter 5 exists
  because a feed that runs dry looks broken to anyone from an infinite scroll. Intro slides stay at
  three sentences.
- **Illustrations are hand-drawn `CustomPainter`s** (`tutorial_illustrations.dart`), no
  Lottie/Rive: they take colours from `ColorScheme` at paint time and are diagrams of a mechanic.
  `_Loop` animates only while its page is visible (a `PageView` builds neighbours) and honours
  reduced motion by pinning a representative frame, not frame 0. Captions are widgets over the
  canvas, never painted text.
- **The channel list is fetched in `OnboardingScreen.initState`**, not when the channel step
  mounts minutes later — one dropped connection there used to end the flow at a Retry button.
  `ChannelSelectionStep` re-asks only when the provider already holds an error when it mounts
  (`test/onboarding_channels_test.dart`).
- **`ContentLanguagesStep` exists because the default is invisible.** The backend narrows a new
  account to its registration locale, so a German phone yields a German-only reader whose feed just
  fills slowly — indistinguishable from an empty platform. The step's third line is the whole
  point: it says where the ticks came from, so one ticked box reads as a starting point rather than
  as a choice already made. Unlike the channel step it **never blocks** — the set is guaranteed
  non-empty, so Continue is always live and walking past is a legitimate answer. The list itself is
  `ContentLanguageChecklist`, shared with the Filters tab (`features/feed_preferences/`): the
  empty-set refusal and the save-on-toggle are both silent failures if a second copy drifts.
  `test/onboarding_languages_test.dart`.
Tests: illustrations and the intro icon badge repeat forever, so **`pumpAndSettle` never returns
in this flow** — drive with `pump(duration)`. `test/tutorial_test.dart` is the reference.

### Channels

`features/channels/`: `ChannelAvatar` is a **topic glyph** in the channel's colour (`channelIcon`,
falling back to `#` for an unknown channel — channels are backend rows, so that case is real), not
a name initial (that convention is for people). Rows are cards with the same margin/radius as
`PostCard`. Both the badge and `ChannelPriceChip` are shared with the composer's
`showChannelPickerSheet` — one look for one thing.

### Reading a post

Opening a post is a full-screen `slideUpRoute` (`core/presentation/slide_up_route.dart`), not a
bottom sheet — a post is mostly media and a sheet kept a barrier and rounded corners over it.
`PostDetailScaffold` is the shared chrome for the feed's reviewable post and history's read-only
one. Media is **full-bleed** (`PostBlocksView.fullBleed`; text keeps its margin) and the
drop/forward footer is **pinned**, so a long post needn't be scrolled to act on.

**The forwarding score** (`forward_score_badge.dart`, sequenced by `PostCard._review` and the
detail page's `_review`) shows after a verdict — and only after — as a badge that pops in, holds,
and leaves with the card. The server makes "only after" true: the count arrives on
`PostReviewResult` and is absent from `PostRead`, so `ForwardScoreBadge` takes a number from a
review result and has no way to read one off a `Post`. Don't add one. Loudness is logarithmic
(`heatFor`: 0 at 1 forward, 1 at 500), driving colour, size and glow together. Order is reveal,
hold, exit: `FeedNotifier.reviewPost` doesn't touch the list; the caller commits removal with
`applyReviewResult` once its animation ends. A drop discloses it on the same terms. The badge is a
glyph and numeral; the localized string is the screen-reader announcement
(`postForwardScoreAnnouncement`). `test/forward_score_test.dart`.

**Preview** (`features/create_post/presentation/post_preview.dart`) opens the same
`PostDetailScaffold` via the same `slideUpRoute` — the opened post, not the card, since that is
where forwarding is decided. `buildPreviewPost` assembles a real `Post` locally with placeholder
ids, running the same drop-empty-paragraphs walk as `_submit`. Anonymity previews *as* anonymity;
`subscription_kind` can't be anticipated (the backend snapshots it), so a supporter's post previews
as ordinary. A picked attachment renders from `PostMedia.local` bytes — callers branch on
`isLocal`; a photo draws for real, a clip shows a placeholder at its published shape. The footer is
shown disabled with a line saying it's a preview. No channel is required; an empty post raises
`_PublishBlocker.emptyPost` instead. `test/post_preview_test.dart`.

### Trust checks

A **trust check** is a probe post the backend mints per reader (`app/core/probes.py` there); its
text asks to be forwarded or dropped, and compliance feeds the reader's Reviewer Trust, which
scales how far their *forwards* travel. Three rules, each a test in `test/probe_post_test.dart`:
- **The check is marked up front** (`probe_marker.dart`, rendered by `PostCard` and
  `PostDetailScaffold`) — measuring people secretly is a trick — but *quietly*: one small outline
  glyph in the meta line's own ink, words only on the tooltip and semantics label. A loud marker
  would let people sort checks from posts without reading. No colour, fill or visible word.
- **A check never shows a forwarding score**: `probe_result_badge.dart` takes the badge's place
  in the same beat (a different tempo would be a tell). The server zeroes the counts and sets
  `is_probe`.
- **Getting one wrong is said plainly** — otherwise the only feedback is forwards quietly reaching
  fewer people.
`showTrustExplainer` (`features/stats/presentation/trust_explainer.dart`) — full-screen
`slideUpRoute` like `showEconomyExplainer`, live figures first — **leads with the effect, not the
number** ("each post you forward now reaches 4 people") and **names the inputs but not their
weights**, so the cheapest way to raise the score stays reading. The window length comes from
`UserStats.trustWindowDays`.

### Refreshing history

`PostHistoryScreen` has an app-bar button and pull-to-refresh; the button drives the
`RefreshIndicator` through its `GlobalKey` (one gesture, one spinner, one path; falls back to the
provider only before a first page exists). Two details are where the gesture used to die: the
**empty state lives inside the indicator**, and the `ScrollablePositionedList` gets
**`AlwaysScrollableScrollPhysics`** (default physics refuse the drag on a list that fits).
`test/history_refresh_test.dart`. A refresh invalidates the provider, dropping every page and
resetting `hasMore`, so an exhausted history can be paged again.

### The token economy in the UI

`EconomyHeaderStatus` takes an `EconomyBarVariant` and states **one fact** per screen as a pill in
the app bar's `actions`: a number, a clause saying what it means, and a bar filling toward
affording a post. **Feed**: balance and distance to a post ("12 · 2 more tokens to post", or
"2–6 tokens per post" once affordable). **Composer**: `Cost 3` and the price-lock countdown
("Cost 3 · held for 4:32") — named, not signed (a leading `−` read as a balance change); worded
as a promise, not a bare deadline. The clause becomes "2 more needed" (pill in `errorContainer`)
when unaffordable, "of your 12" for a cached quote with no expiry, and a **spinner** once expired
— which is when `_ComposerPill` re-fetches (it keeps a timer; retries, since `refresh()` swallows
connectivity failures). Details:
- Number and clause are separated by a **middot** (two facts, not one sentence) and the rate leads
  ("1 token per post", not "Posts cost 1 token" — a plural noun after a number reads as a count).
- The spinner state centres the row: a baseline-aligned row inside `IntrinsicWidth` asks for a
  dry baseline, and a painter throws. The sentence survives on the tooltip/semantics
  (`economyPillCheckingPrice`).
- The clause is **one line, width-capped** (`_labelCap`) — app bar actions get unbounded width.
  Anything longer belongs in `showEconomyExplainer`, opened by tapping either pill: a full-screen
  `slideUpRoute` (a sheet arrived already scrolled), live figures first. New economy copy goes
  there. "You need 2 more tokens" is `_ShortOnTokensHint`, one line above the disabled Relay button,
  only while it applies.

**Posting is priced per route (channel, language), so nothing quotes one number until both are
chosen.** `GET /posts/economy` gives base rate + deployment-wide `post_price_min/max`;
`GET /channels` the range per channel (`Channel.postPriceMin/Max`); `GET /posts/price`
(`ChannelsRepository.fetchPostPrice`, deliberately uncached) the exact charge. The composer walks
that ladder. Three rules, pinned by `test/channel_pricing_test.dart` and
`test/content_language_test.dart`:
- **The composer states one price and gates Relay on that same price**: `_effectiveEconomy`
  collapses the range onto `_effectivePrice`, because the affordability getters read the range's
  low end — otherwise a cheap route elsewhere could vouch for this one.
- **Everywhere else, affordability is judged against the cheapest end** (`priceRange.$1`,
  `Economy.canAffordPost`), since the feed pill is about the balance, not one post.
- **Null means unknown, never free**: `postPriceMin` is nullable and the chip renders nothing.
`hasSinglePrice` renders "4" not "4–4" — common, since `FEED_PRICE_CHANNEL_BAND` (±50%) rounds
away at the bottom of the scale. **On a quiet dev backend every route is `FEED_PRICE_MIN` and the
range is invisible**; raise that floor to see a spread, don't change anything here.
`_ExactPriceLine` ("Price based on your selection: 4") is keyed on `_routePrice` being non-null —
a quote the backend actually returned — so it never sits over an interpolation.

**Spending is animated over the editor** (`TokenSpendBadge`, `token_spend_badge.dart`): the
balance you had, a red "−N" rising away, digits easing down. Deliberately the sibling of
`ForwardScoreBadge` — same position, pop-in and beat (`kTokenSpendPlay`/`kTokenSpendHold` vs
`kForwardScorePopIn`/`kForwardScoreHold`); only the hold differs, because these digits are still
falling when the play ends. Labelled "Your tokens:" (`economySpendBadgeLabel`). It plays on the
composer *before* `context.go('/feed')` and navigation awaits it — an animation in the feed's app
bar corner was over before anyone found it and needed a cross-screen provider. Driven by the
actual delta (`balanceBefore - result.tokenBalance`), so a superuser's free post raises no badge.
**The controller is built in `initState`, never as a `late final` initializer** — lazy init would
first construct it inside `dispose` and a `Ticker` on a deactivated element throws.

**Channel prices are off by default, behind one switch** (`showChannelPricesProvider`,
`core/settings/price_display_settings.dart`): a labelled `Switch` in the channels app bar and a
`SwitchListTile` in the explainer. A mode switch, not a preference — nobody picks a channel by
price, but someone reviewing to earn the difference watches exactly that. A labelled switch
replaced an icon toggle whose only name was a long-press tooltip. While on, `ChannelsScreen`
follows `post_price_expires_at` and re-fetches via `ChannelsNotifier.refreshPrices()` (quiet, no
spinner); nothing — not the economy fetch, not the timer — runs while off. `ChannelPriceChip`
renders **a figure, not a sentence** (token glyph + number in a bordered stadium so it reads as
tappable), opens the explainer, and carries its own `InkWell` so tapping the price can't select the
channel. Null renders nothing.

### The feed keeps itself current

The queue is pushed into by the backend's worker, so a one-shot fetch only ever shrinks.
`FeedNotifier` (`features/feed/application/`) closes that gap:
- **It polls `GET /posts/feed/status`, not the feed** — post ids, one `LRANGE` server-side, cheap
  enough every 20s. `_accountedFor` (every id pulled *or* announced this session) is what keeps a
  channel filter from turning every tick into a full feed fetch.
- **Arrivals are appended, never spliced in or pruned out.** Inserting where the server puts
  them would shove the post being read; removal stays `applyReviewResult`'s job so a card mid-exit
  is never yanked.
- **It watches only while someone is watching**: polling runs while the feed is the visible tab
  *and* the app is in front. Tab visibility is `TickerMode.valuesOf(context).enabled` in
  `didChangeDependencies` — `StatefulShellRoute.indexedStack` keeps every tab mounted, so
  `initState` can't tell. The same request marks the user active for the price formula, so
  background polling would lie about who is here. `_watching` is tracked apart from the timer
  because `build` re-runs on a channel-filter change and takes `onDispose` with it. Stopping goes
  through `_feed`, a cached notifier reference, because **`dispose` must not touch `ref`**:
  Riverpod throws on a read from an unmounting widget, which aborts the unmount pass, leaves
  `GlobalKey`s registered, and renders the whole tab as an `ErrorWidget` on its next activation —
  every new account saw that the moment onboarding ended. `test/feed_branch_remount_test.dart`.
- **Three things ask ahead of the timer**: reviewing down to the last few posts (a slot just
  freed server-side), settling a scroll near the bottom (there is no next page, only what has
  arrived), and returning to the tab or app.
`_EndOfFeedNotice` says which ending it is — a full queue is work waiting, an empty one is waiting
on other people. None of this creates *supply*: an empty queue stays empty until someone posts or
forwards, because reach is what an author paid for (see the backend's CLAUDE.md).

**The Feed tab carries the count** (`feed_waiting_icon.dart`): posts waiting, badged on the bottom
nav, **hidden while the feed is the selected tab** (there the list is the count). It must never
overcount (undercounting self-corrects on the next poll; overcounting sends someone to an empty
feed), so `_removeFromList` calls `FeedQueueStatusNotifier.remove` at the moment the server
confirms a slot is gone. It costs no extra polling: last status minus reviews since. "9+" past
nine (`FEED_QUEUE_MAX_SLOTS` is a server setting this app needn't know). Accent colour, not red —
red is Drop and delete-account here.

### A slot can outlive its post

The queue is a list of ids server-side, so erasing an account can leave slots pointing at nothing
(backend `account_deletion.py`). `GET /posts/feed` answers `FeedEntry` envelopes, mirrored in
`post.dart` as a sealed pair — `FeedPost` / `MissingPost` — not a nullable field, so every renderer
must say what it does with the case. `FeedNotifier` keys on `entry.postId`. `MissingPostCard` is an
explanation and one button; three absences are the design: **no forward** (nothing to pass on),
**not tappable** (no detail to open), **not a drop** — it calls `DELETE /posts/feed/{id}`, which
records no review, and a `409 post_available` (the post is in fact still there) leaves the card in
place rather than hiding a post still owed a verdict. A cache entry from before this shape fails to
parse and is discarded as a miss (`JsonCache.read`), so no migration was needed.

### Downloading your data

Settings → Account → "Download my data" (`DataExportTile`), placed *above* the delete row — an
export discoverable only inside the deletion dialog is one nobody takes. `GET /users/me/export`
returns a ZIP, so this call differs from every other:
- **`ResponseType.bytes` with a ten-minute receive timeout.** Dio applies it *between chunks*, so
  it stays a stall detector; the body is held in memory because `download()` streams to a file
  only where there is a filesystem, and this app runs on web too.
- **That response type broke error handling**: Dio decodes by the *request's* options, so a 429
  arrived as bytes and read as "something went wrong". `RelayApiException._decodedIfBytes`
  (`api_exception.dart`) decodes a small byte body as JSON first.
- **Delivery is per platform**: `core/files/file_delivery.dart` is a conditional export. Web gets
  the browser download (not the Web Share API). Android stages the file in the app cache and hands
  it to the system share sheet — the staging folder is cleared on the way *in*, never out, because
  the receiving app reads after the sheet closes. Through `fileDeliveryProvider` so tests can stub
  it.
- **A 429 gets its own sentence** — the shared copy counts seconds, and this budget is 3 per day.
  A dismissed share sheet says nothing.

### Deleting an account

Settings → Account ends in the one row in the error colour. `DeleteAccountDialog` is two slides in
one dialog (a chain can't go back). Slide one: keep the posts (they stay, unnamed) or erase them
too — default keep, since both are permanent and that destroys less. Slide two proves the account:
a password account types its password; a Google account (no password — linking overwrote it) gets
the confirmation alone; either way the slide repeats the choice. It ends via
`AuthNotifier.logout`, so token, cache and router fall back like any session boundary.

### Chrome that yields to content

Both main screens are mostly other people's content; anything else has to earn a permanent row.
- **The feed's channel filter has two sizes**: `_ChannelFilter` cross-fades between the chip row
  and a one-line summary, driven by `UserScrollNotification` *direction* (reaching back up for the
  filter is the same gesture as reaching back up the feed). Tapping the collapsed line reopens it.
  Horizontal notifications are ignored — the chip row is itself a scroll view.
- **The feed's app bar has no count and no reload button.** The count moved to the tab badge;
  reload went because the feed keeps itself current and the button advertised a chore that no
  longer exists. Pull-to-refresh stays and doesn't blank the list: `FeedNotifier.refresh` writes
  no `AsyncLoading` and throws on failure.
- **The composer's publish row holds all three decisions** — anonymous, channel
  (`_ChannelSelectorChip`, outlined in primary while unpicked), Relay. Because the controls are at
  the bottom: publish preconditions are a toolbar line (`_PublishBlocker`/`_PublishBlockerHint`,
  held as an enum so a locale change can't strand it, cleared as soon as untrue), not a snackbar
  that would cover the chip it points at; opening the picker drops keyboard focus before and after;
  a successful post clears the channel too, since the composer tab's state outlives the post in
  the shell's `IndexedStack`.

### Waiting, and having nothing

Loading, empty and broken are each a *designed* screen:
- **A cold load shows the shape of what is coming** (`core/presentation/skeleton.dart` + one
  `*_skeleton.dart` per screen). **Shapes must match what replaces them** — built from the same
  numbers as the real widgets (12/6 card margin, 24dp author avatar, 40dp action row), so a
  geometry change means changing the skeleton in the same commit. **Cold load only, never a
  refresh**: every screen falls back to cached content (`core/cache/`), and grey boxes over
  something being read would be a regression. One `Shimmer` controller per subtree, **stopped**
  under `MediaQuery.disableAnimations` (a repeating controller ticks whether or not anything reads
  it). A `Shimmer` on screen means `pumpAndSettle` never returns.
- **An empty screen names its way out** (`EmptyStateView`, `core/presentation/empty_state.dart`):
  icon, a subtitle saying *why*, and an action wherever one exists. Under pull-to-refresh use
  `ScrollableEmptyState`.
- **`ErrorStateView`** is the third member of the same family.
- **A switch must not lie.** The two notification rows are `_DisabledSetting` with a "Soon" badge
  rather than switches over fields nothing reads — a disabled switch still shows a position.

### Offline behaviour

- **Preferences render from `core/settings/app_settings.dart`, never from the server profile.**
  `appSettingsProvider` owns `themeMode`; `profileProvider` is only a sync input. Reconciliation
  is `decideSettingsSync`: branches on a local `dirty` flag, local wins on a real two-device
  conflict, detected via the server's `settings_revision`.
- **Reads fall back to cache; writes do not queue.** `core/cache/cached_fetch.dart`: write-through
  on success, serve the last copy on a *connection* failure only — never on a 4xx. Writes fail
  with a message (reviews are guarded by the Redis queue, posts priced at request time). Controls
  are never disabled by connectivity.
- **All errors go through `core/errors/`.** `asRelayException` unwraps the `DioException`
  (`AsyncValue.guard` hands widgets the wrapper); `messageFor` maps `detail.error` to copy. Never
  render `toString()`. After an await that may unmount the widget (an optimistic review unmounts
  its `PostCard`), capture the `ScaffoldMessenger` first and use `showErrorSnackBarOn`.
- **Session boundaries are handled centrally** in `PeerkolaApp`'s `authNotifierProvider`
  listener. Logout clears token, cache and local settings and invalidates the keep-alive data
  providers; sign-in warms `profileProvider`. Account-scoped providers are invalidated on the way
  **in** as well (`_invalidateSessionScoped`, `app.dart`): the router's permanent listener on
  `profileProvider` rebuilt it after logout with the token already gone, cached the 401, and the
  next sign-in inherited "session expired".
- **Riverpod's auto-retry is disabled for connectivity failures** (`_retryPolicy`, `main.dart`) —
  left on, an offline provider with no cache spins for minutes. `ConnectivityNotifier` owns
  recovery: polls `/api/v1/health` on a backoff; `PeerkolaApp` re-runs what failed on reconnect.

### Auth

`features/auth/`: `authNotifierProvider` tracks token *presence* only. `app_router.dart`'s
`redirect` chain guards in a fixed order — signed-in, email-verified, onboarded. A 401 from the Dio
interceptor forces logout via `onUnauthorizedProvider`; a 403 deliberately does not. Endpoints:
`POST /auth/jwt/login`, `POST /auth/register`, `POST /auth/google`, `GET/PATCH /users/me`.

**Google sign-in** (`google_sign_in` 7.x) is an ID-token flow: the plugin yields a token,
`POST /auth/google` verifies it and returns our JWT. No deep links.
- **One client ID, two names**: `AppConfig.googleServerClientId` is `serverClientId` on Android
  and `clientId` on web — the web plugin asserts `serverClientId` is null
  (`features/auth/data/google_sign_in_service.dart`).
- **Web needs Google's own button**: `supportsAuthenticate()` is false there, so
  `google_sign_in_button.dart` is a conditional export (`dart.library.js_interop`) and the result
  arrives on `GoogleSignInService.idTokens`. Anything touching it must be checked with
  `flutter build web` *and* `flutter build apk` — `flutter analyze` only sees the non-web branch.
- **Account identity is one-way.** `UserProfile.authProvider` (`"password"`/`"google"`) drives the
  UI: Settings hides Change password; only Google signups get the onboarding username step. The
  backend's `409 google_link_required` is a *prompt* — `GoogleAuthSection` shows the irreversibility
  dialog and re-sends the same token — so it is deliberately absent from `error_messages.dart`. The
  login-screen and Settings entry points have separate copy: from login the Google address *is*
  the account address; from Settings any Google account may be linked and the account keeps its
  own email.
- **A taken username is shown under the field** (`InputDecoration.errorText` in
  `register_screen.dart` and `username_step.dart`, cleared on the first keystroke), not as a
  `validator` rule (forms only re-validate on submit). While set, submit returns early. The field
  carries a `FieldInfoIcon` (`core/presentation/`) with `TooltipTriggerMode.tap`, because a
  long-press tooltip is never found.

### Localization (i18n)

English + German. **Every user-facing string goes through this system — a raw `Text('...')`
literal is a bug.**
- **Source of truth**: `lib/l10n/app_en.arb` (template, `@key` metadata for placeholders/ICU
  plurals) and `app_de.arb`. Add to *both* in the same change as the widget. `flutter pub get` /
  `flutter gen-l10n` regenerates `lib/l10n/generated/` (gitignored, never hand-edited).
- **Usage**: `final l10n = AppLocalizations.of(context); l10n.someKey`. `nullable-getter: false`,
  so never append `!`. Reference: `core/errors/error_messages.dart` (error code → copy, including
  the backend's structured password-policy violations) and `settings_screen.dart`.
- **German tone**: casual `du`, warm; translate for meaning; keep established loanwords (`Feed`,
  `Token`, `Post`/`Beitrag`, `Score`); avoid `Nominalstil` and passive voice.
- **Locale resolution**: device locale, overridable in Settings → Language
  (`core/settings/locale_settings.dart`, local only, never synced — `activeLocaleProvider`). Sent
  as `Accept-Language` on every request, which is what localizes backend-authored text (banner,
  password policy).
- **Interface language and content language are two different settings and must stay in
  different places**: the former is a Settings row (subtitle "The language this app is shown
  in"), the latter (`User.contentLanguages`, server-side, decides what the feed sends) is a tab of
  `FeedPreferencesScreen` beside the channel list, because accepting a language is the same act as
  subscribing to a channel. Both used to sit in Settings and read as one setting stated twice;
  removing the subtitle or the hint on the languages tab is an invisible regression (switch the app
  to German, see no feed change, conclude the filter is broken). Backend mirrors this with
  `SUPPORTED_LOCALES` vs `CONTENT_LANGUAGES`.
- **Untranslated on purpose**: the `Relay` brand name and placeholder URLs.

### Content language

The backend routes on (post language × reader's accepted languages); getting it wrong sends
someone an unreadable post with no error anywhere. See the backend's "Language routing".
- **Both lists come from the server** (`GET /config` → `contentLanguagesProvider`,
  `languageUnspecifiedProvider`), never a Dart constant, so picker, detector candidates and
  accepted values can't drift.
- **Detection is on-device and only prefills** (`core/languages/language_detector.dart`, a
  stopword heuristic — no plugin, works on web, unlike ML Kit; swap at `languageDetectorProvider`).
  **Null is a real answer** and leaves the picker alone; the detector **stops proposing** once the
  author opens the picker (`_languageTouched`); stopword lists stay **disjoint**
  (`test/language_detector_test.dart`). **`_redetect` is a pure function of the current text and
  every path that changes the block set must call it** — `_removeBlock` re-runs it immediately.
  "Text but unsure" leaves the choice alone; "no text at all" withdraws the suggestion (which also
  puts "no language" back within reach). `minimumWords` is 4, tuned against real posts (8 abstained
  on an ordinary seven-word first post); `minimumScore`/`minimumMargin` keep short text honest.
  `test/composer_language_test.dart` drives the real screen because the failure mode is silence.
- **A language is required to publish and never defaulted to the app's own** — a phone set to
  English says nothing about what someone is writing.
- **"No language" is offerable only for a post with no text** (it routes to the whole channel).
  The picker greys it out *with a reason*; the composer refuses it before spending an upload. The
  converse is not enforced: a video can be spoken German.
- **`FeedPreferencesScreen`** (`features/feed_preferences/`) is the bottom-nav tab "Filters"
  (`feedPrefsTitle`, `Icons.filter_alt`): `ChannelsTab` and `ContentLanguagesTab` under one
  `TabController`, each with its own client-side search field. `ChannelPriceSwitchAction` sits in
  the `AppBar` actions only while `_tabs.index == 0` (it's chrome about the channel list). `ViewTip`
  wraps the `TabBarView`, not each tab — one card, one `tipKey` (`'tip.feedPreferences'`) explaining
  the screen's purpose, dismissed once for both tabs.
