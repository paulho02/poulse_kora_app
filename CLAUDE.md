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
- `features/feedback/` — the feedback / bug-report form (`/feedback`), reachable from the profile
  **and from the login and register screens**. That last part is the constraint the feature is
  built around, and it shows up in three places that should not be undone:
  - **The route sits outside every redirect gate.** `app_router.dart`'s `redirect` early-returns
    for `/feedback` before the signed-in / verified / onboarded chain, because the reports most
    worth receiving come from exactly the people those gates have stopped. The backend accepts the
    endpoint unauthenticated for the same reason.
  - **Signed out, anonymity is shown locked on rather than hidden**, and "you can contact me" is
    not offered at all — there is no verified address to reply to. Choosing anonymity while signed
    in really does cut the link (the backend stores no user id for one), so the contact option
    disappears with it. The screen mirrors the backend's rules; it does not enforce them.
  - **Attachments skip the cropper.** This is the one upload path with no `CropMediaScreen` in
    front of it, because a screenshot has no shape to choose — so its content type comes from
    `core/media/image_content_type.dart` sniffing the bytes instead of from a re-encode, and the
    picker is deliberately given no `maxWidth`/`maxHeight` (those make it re-encode, turning a PNG
    screenshot into a JPEG with ringing around the very text being reported). An unsupported file
    is caught locally with a message rather than as a 400 after the upload.
  Consent is a hard precondition, reported as a line above the button rather than by disabling it
  — same rule as the composer's `_PublishBlocker`, and for the same reason. The screen depends on
  `Navigator`, not `GoRouter`, so it mounts anywhere.
- `features/onboarding/` + `features/tutorial/` — how a new account is introduced to the app.
  Two features, because they answer two different questions and only one of them is mandatory.
  `OnboardingScreen` is the post-registration flow the router forces
  (`intro → tutorial offer → [tutorial] → [username] → channels → disclaimer`, the last three
  conditional); the deck in `features/tutorial/` is the long explanation, and it is *asked for*
  rather than imposed. Five things are load-bearing:
  - **The tutorial is offered as a question with two real answers.** `TutorialOfferStep` puts
    "Show me the idea behind Relay" and "I'll explore it on my own" on screen as two buttons of
    the same weight, rather than hanging a "learn more" link off the last intro slide. A link is
    an aside that gets skimmed past, and the people who skim it are the ones who later meet the
    token economy as a surprise. Making it a step means declining is a decision. That is also why
    the "you can start this anytime from Settings" hint sits on *that* screen and not only at the
    end of the deck: the person who most needs it is the one who just said no.
  - **The deck is a widget first and a route second.** Onboarding embeds `TutorialDeck`;
    `/tutorial` (Settings → How Relay works) wraps the same widget in `TutorialScreen`. It cannot
    be a route in both places: while `onboardingCompleted` is false, `app_router.dart`'s gate
    chain bounces every location that isn't `/onboarding` straight back to it, so a route pushed
    from inside the flow would not survive the push. `onSkip` is null on the Settings route
    because the app bar's back button is already the way out.
  - **The five chapters are a chain of consequences, not a feature list.** A post travels by hand
    (1), so no ranking model is involved (2), so the decision is yours (3), which is worth
    something and is therefore priced (4), and the result is a feed that is finite (5). Chapter 5
    is there because a feed that runs dry is the most confusing thing about Relay for anyone
    arriving from an infinite scroll: it looks broken, and it isn't. Chapters are the place for
    depth; the intro slides stay at three sentences because everyone sees them.
  - **The animations are hand-drawn `CustomPainter`s** (`tutorial_illustrations.dart`), with no
    Lottie/Rive and no asset files. They have to read in both themes, and an exported animation
    bakes its colours in, while these take every colour from `ColorScheme` at paint time. They are
    also diagrams of a mechanic rather than artwork, so the part most likely to change is the part
    a vector asset would freeze. Two rules every one of them follows, both in `_Loop`: it animates
    **only while its page is the visible one** (a `PageView` builds its neighbours, so otherwise
    three controllers tick for one drawing), and it honours **reduced motion** by pinning a chosen
    representative frame rather than frame 0, which is generally an empty stage. Captions are
    widgets over the canvas, never text painted into it, so they stay translated and scale with
    the reader's text size.
  - **The channel list is fetched when the flow starts, not when the channel step mounts**
    (`OnboardingScreen.initState`). Nothing else in onboarding watches
    `channelsNotifierProvider`, so the step used to be what started the request, and the step is
    minutes downstream of registration for anyone who takes the tutorial. That put the one
    request onboarding cannot continue without at the end of a long idle gap, on an account too
    new to have a cached list: a single dropped connection ended the flow at a Retry button.
    `ChannelSelectionStep` holds the other half, and it is narrow on purpose. It re-asks **only**
    when the provider is already sitting on an error when the step mounts, because that error is
    minutes old and was never on screen. A list that loaded is left alone, and a second failure
    is shown, since that one is current. Pinned by `test/onboarding_channels_test.dart`.
  Consequence for tests: an on-screen illustration repeats forever, and so does the intro
  slides' icon badge, so **`pumpAndSettle` on anything in this flow never returns**. Drive it
  with `pump(duration)`. `test/tutorial_test.dart` says so at the top and is the reference.
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

### The forwarding score

After a verdict — and only after — the card shows how many forwards the post has, as a badge that
pops in, holds a beat, and then leaves with the card (`features/feed/presentation/`:
`forward_score_badge.dart`, sequenced by `PostCard._review` and the detail page's `_review`).
Four things are load-bearing:

- **The server is what makes "only after" true.** The count arrives on `PostReviewResult` and is
  deliberately absent from `PostRead`, so no feed or detail response carries it (see the backend's
  CLAUDE.md). Hiding it client-side would leave the raw API as the way around it, and a reader who
  can see that everyone else forwarded a post is voting on the crowd rather than on the post. So
  `ForwardScoreBadge` takes a number from a review result and has no way to read one off a `Post`
  — there is nothing there to read. Don't "helpfully" add one.
- **Loudness is logarithmic** (`ForwardScoreBadge.heatFor`, 0 at 1 forward, 1 at 50). A forward
  re-fans the post out to more readers, so counts compound; on a linear ramp nearly every real post
  would look identical and only freak ones would register. The ramp drives colour (grey → accent →
  amber), size and glow together, so the number reads before it is read.
- **The order is reveal, hold, exit** — the reveal has to land while the card the score belongs to
  is still there. `FeedNotifier.reviewPost` deliberately doesn't touch the list; the caller commits
  the removal with `applyReviewResult` once its own animation is done.
- **A drop discloses it on the same terms.** The number describes the post, not a reward for
  agreeing with the crowd.

The badge shows an arrow and a numeral, nothing to translate; the localized string is the
screen-reader announcement (`postForwardScoreAnnouncement`), which is what says *what* was counted.
`test/forward_score_test.dart`.

The composer's **Preview** button opens that same screen
(`features/create_post/presentation/post_preview.dart`): same `PostDetailScaffold`, same
`slideUpRoute`, so there is no second post layout to keep in step with the real one. Four things
make it work and are worth keeping:
- **It previews the *opened* post, not the feed card.** That is the view carrying every block the
  author wrote, and the one where forwarding is actually decided. Reusing `PostCard` instead would
  have meant a non-interactive fork of a widget whose buttons hit the network.
- **The post is assembled locally** (`buildPreviewPost`) into a real `Post` with placeholder ids
  that never leave the device — publishing still goes through `_submit`'s `ComposerBlockInput`
  list. It runs the same "drop empty paragraphs, keep the order" walk, so what is previewed is what
  would be published. Anonymity is previewed *as anonymity* (no name, no picture, the neutral
  glyph), which is the single thing here most worth being sure about before relaying;
  `subscription_kind` is the one thing it cannot anticipate — the backend snapshots it at creation
  — so a supporter's post previews as an ordinary one, which under-promises rather than over-.
- **A picked attachment renders from its bytes** — `PostMedia.local` carries them and `isLocal` is
  what every caller must branch on, since there is no URL and no poster yet. A **photo** draws for
  real (the bytes *are* the cropper's output, so it is exactly what publishes); a **clip** shows a
  placeholder at the shape it will publish in, because the crop, the transcode and the poster frame
  are all still the server's to do and playing the raw file would preview a shape the reader never
  sees.
- **The drop/forward footer is shown, disabled.** It takes the bottom of the screen away from the
  article, so omitting it would preview more room than the post gets; a line above it says the
  screen is a preview, which is otherwise only discoverable by tapping something that does nothing.
No channel is required to preview — that choice is made at publish time and the meta line simply
drops the channel while it is open — but an empty post raises the composer's existing
`_PublishBlocker.emptyPost` line rather than opening a blank screen. Covered by
`test/post_preview_test.dart`.

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

**Posting is priced per channel, so there are two prices and they mean different things.**
`GET /posts/economy` quotes a *global reference rate* — the right number for the feed pill, which
is about the balance rather than about any one channel. What a post actually costs is the price on
the channel it goes to (`Channel.postPrice`, from `GET /channels`), which the backend holds for the
same window as the global one and charges verbatim. So the composer passes
`EconomyHeaderStatus(priceOverride: selectedChannel?.postPrice)` and derives its affordability
state — the Relay button, `_ShortOnTokensHint` — from `_effectiveEconomy`, never from the raw
global figure. Dropping that override would show a price nobody is ever charged, and it would look
entirely normal on screen; `test/channel_pricing_test.dart` is what stops that. `postPrice` is
nullable (a channel list cached before per-channel pricing) and null means **unknown, fall back to
the global rate** — never free.

**Channel prices are off by default and live behind one switch** (`showChannelPricesProvider`,
`core/settings/price_display_settings.dart`; the app-bar toggle on `ChannelsScreen`, and a
`SwitchListTile` in the explainer sheet, which is where someone staring at a price they can't
afford will find it). It is a mode switch, not a preference: nobody picks a channel by price, so a
permanent column of figures would turn browsing into reading a market board — but someone who
wants to post and is reviewing to earn the difference is watching exactly that. Two rules follow
and should not be undone. `ChannelPriceLabel` renders **affordability, not a figure** ("3 · Enough
to post" / "3 · 6 more tokens to post", reusing the feed pill's own two clauses), because the
question in that mode is "can I afford it yet", not "what does it cost". And while prices are on,
`ChannelsScreen` follows `post_price_expires_at` and re-fetches through
`ChannelsNotifier.refreshPrices()` — a quiet refresh, since `refresh()` would replace the list
being read with a spinner once per window. Nothing in this paragraph runs while the switch is off,
including the economy fetch and the timer.

### The feed keeps itself current

The review queue is something the backend's worker *pushes into*, so a client that fetches once
holds a list that can only ever shrink — which is what made the feed feel like a page to reload
rather than something to keep reading. `FeedNotifier` (`features/feed/application/`) closes that
gap, and four decisions in it are load-bearing:

- **It polls `GET /posts/feed/status`, not the feed.** That route answers with the queue's post
  ids and costs one `LRANGE` server-side, so the common answer ("nothing new") is cheap enough
  to ask every 20 seconds. `_accountedFor` — every id this session has already pulled *or* been
  told about — is what keeps it cheap: without it, a channel filter alone would guarantee a
  wasted full feed fetch on every tick, since the status lists the whole queue while a filtered
  list holds part of it, and the difference would read as news forever.
- **Arrivals are appended, never spliced in or pruned out.** The server hands the queue back
  newest-first; inserting where the server puts it would shove the post being read down the
  screen mid-sentence, which is the opposite of continuous. And removal stays
  `applyReviewResult`'s job alone, so a card already playing its exit animation is never yanked
  out from under it by a poll landing the beat after the review was accepted.
- **It watches only while someone is watching.** Polling starts when the feed is the visible tab
  *and* the app is in front, and stops otherwise. Tab visibility comes from
  `TickerMode.valuesOf(context).enabled` in `didChangeDependencies` —
  `StatefulShellRoute.indexedStack` keeps every tab mounted and only turns the ticker off on the
  ones you cannot see, so `initState` cannot tell you this. The other half of the reason is
  honesty: the same request marks the user active for the backend's price formula, so a poll
  that kept running in the background would be a lie about who is here. `_watching` is tracked
  apart from the timer itself because `build` re-runs whenever the channel filter changes and
  takes its `onDispose` with it — without that, choosing a channel would quietly leave the feed
  static for the rest of the session.
- **Three things ask ahead of the timer**: reviewing down to the last few posts (a review is the
  one moment a queue slot is *guaranteed* to have just freed up server-side, so the worker may
  be placing something right now), settling a scroll near the bottom (the infinite-scroll
  gesture, answered by asking the queue — there is no next page, only what has arrived since),
  and coming back to the tab or the app.

Where the list ends, `_EndOfFeedNotice` says which ending it is: a full queue is work waiting to
be done, an empty one is a queue waiting on other people. A feed that just stops at the last card
cannot be told apart from one that failed to load the rest — which is exactly the doubt the
reload button used to exist to answer.

Worth knowing when this feels wrong: none of it creates *supply*. A queue that is genuinely empty
stays empty until someone posts or forwards, because reach is what an author paid for
(`FEED_FANOUT` recipients per operation) and handing out undelivered posts on demand would be an
economy change, not a UX one. See the backend's CLAUDE.md and the todo.

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
- **The feed's app bar dropped the open-post count, and then the reload button.** The count was a
  number nobody acts on (the queue is whatever it is, and the count moves on its own), and the
  title bar was worth more as the place the token pill lives. The reload button went for a
  stronger reason: the feed now keeps itself current (above), so a control whose whole job is
  "check again" would be advertising a chore that no longer exists — and its presence was most
  of what made the feed read as a static list. Pull-to-refresh stays, for impatience rather than
  necessity, and it no longer blanks the list to a spinner: `FeedNotifier.refresh` writes no
  `AsyncLoading` and throws on failure instead, so a failed reload leaves the reader where they
  were and merely says so.
- **The composer's publish row holds all three publishing decisions**: anonymous, channel, Relay.
  The channel picker used to be a full-width labelled field above the editor — a whole row for one
  word chosen once — and is now `_ChannelSelectorChip`, outlined in the primary colour while
  unpicked so a required-but-open choice still looks like one. The picker sheet behind it is
  unchanged, but three things about it follow from the move to the *bottom* of the screen and
  should stay that way:
  - **Publish preconditions are a line in the toolbar, not a snackbar** (`_PublishBlocker` /
    `_PublishBlockerHint`). A snackbar is drawn over the bottom of the screen, which is now
    where the controls are: "pick a channel" landed squarely on the channel chip it was asking
    the author to tap, so the message had to time out before it could be acted on. The blocker
    is held as an enum case rather than resolved text so a locale change can't strand it, and
    it clears as soon as it stops being true (picking a channel, adding a block, typing).
  - **Opening the picker drops keyboard focus**, before and after — a modal route hands focus
    back to whatever held it, which reopened the keyboard over a post that was already written.
    Reopening it made sense while the picker came *before* the editor; from the publish row the
    next thing wanted is Relay.
  - **A successful post clears the channel too.** The composer is a tab in the shell's
    `IndexedStack`, so its state outlives the post it was written for and used to keep the last
    channel selected until an app restart — inherited silently by the next post, and noticed
    only after relaying to the wrong place.

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
- **A taken username is shown under the field, not in a snackbar.** The backend answers 409
  `username_taken` on both writers, and both screens that set a name (`register_screen.dart`,
  `username_step.dart`) hold the refused string and feed it to `InputDecoration.errorText`,
  clearing it on the first keystroke. Deliberately not a `validator` rule: a form only
  re-validates on submit, so a validator version leaves the message under the field while the
  user types the replacement. While it is set, submit returns early — the server's answer is
  still true for that exact string, so a retry would only spend a round trip. `messageFor`
  still maps the code (unlike `google_link_required`), as the fallback for anywhere that has
  only a snackbar.
  The same field carries a `FieldInfoIcon` (`core/presentation/`) saying the name is visible to
  other people — it uses `TooltipTriggerMode.tap` because a default Tooltip opens on *long
  press* on touch, which nobody finds, and a hint meant to be read before someone types their
  real name has to be findable.

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
