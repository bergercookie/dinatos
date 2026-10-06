# Frontend

`frontend/` is a Flutter app (web, Android, and Linux desktop -- see
[Distribution](distribution.md) for how each one ships) against the
backend's REST API, with no code generation step (no `build_runner`, no
`freezed`) -- models are hand-written classes with `fromJson`/`toJson`, and
state management is plain Riverpod (`Provider`, `StateNotifierProvider`,
`FutureProvider`), not the `@riverpod`-annotated generator variant. One
dependency less to keep in sync, and nothing to regenerate when a model's
shape changes.

Layout:

```text
frontend/lib/
  core/       API client (Dio + an auth interceptor), auth state/storage,
              routing (go_router), theme
  models/     Hand-written request/response types, one file per resource
  features/   One directory per resource (exercises, routines, activities,
              profile, measurements, auth, home, onboarding) -- each with its own
              repository (wraps Dio), Riverpod providers, and screens
```

## The first-run tour is an overlay above the router, not a screen

`features/onboarding/` walks a new account through setting units, saving a
first routine and logging a first workout, by dimming everything but the
real control to press next and pointing at it. It is wired in as
`MaterialApp.router`'s `builder`, so one widget (`OnboardingOverlay`) sits
above every route and no screen has to know a tour exists -- beyond
wrapping the handful of widgets it points at in an `OnboardingTarget`,
which draws and handles nothing itself, only registers where it is.

Three decisions worth knowing before changing it:

- **Steps complete by what the app did, not by what the user pressed.** A
  step advances when the router reaches a path (`advanceOnLocation`) or the
  app reports an event (`advanceOnEvent`, e.g. the profile was saved) --
  never by a pointer listener on the highlighted widget. A mouse or finger
  reaches the app as pointer events, but assistive technology (and a
  browser test driving the accessibility tree) activates a control with a
  semantic tap, which a pointer listener never sees; the tour would hang on
  exactly the people who most need guidance to be correct. Pressing the
  highlighted control is the real thing, so its normal effect is the signal.
- **Only single-press steps are modal.** The overlay is above the app's own
  `Navigator`, so anything the app opens in it -- a dropdown menu, the
  exercise picker's bottom sheet -- renders *beneath* the dimming. A modal
  step (everything outside the spotlight blocks input) is therefore only
  used where one press is the whole step; steps that need the user to fill
  something in leave the app usable and only draw the ring, with "Skip
  step" as the way out if they get stuck.
- **A missing target never traps the user.** A modal step blocks only once
  its target has actually been found on screen -- in a visible branch, not
  an inactive tab an `IndexedStack` is keeping alive. If the user wandered
  off, the card still shows (docked, no dimming) and "Skip step"/"Skip
  tour" always work.

Completion is remembered per account in `shared_preferences`
(`onboarding_seen_<user id>`), so a second account on the same device gets
its own tour; Settings' "Take the tour again" restarts it. Its steps are
data (`onboarding_steps.dart`), so adding or reordering one is an edit to
that list plus an `OnboardingTarget` where it points.

`e2e/` drives this in a real browser; see
[CI and releases](../development/ci-and-releases.md).

## Auth mirrors the backend's design deliberately

The session token is persisted (`flutter_secure_storage`, not a cookie),
there is no refresh token, and a 401 from *any* request (caught by a Dio
interceptor) clears it and routes back to `/login` -- there is nothing to
refresh, so a 401 always means "log in again," never "retry after
refreshing." `go_router` redirects based on that auth state, not on which
screen thinks it's logged in. Logging out (the settings screen's app bar
icon) calls `POST /auth/logout` to revoke the session server-side, then
clears the local token regardless of whether that call succeeded -- if the
backend is unreachable, "logged out on this device" still has to win over
leaving the person stuck signed in. See
[Authentication](backend.md#authentication) for the server-side design this
mirrors.

## The backend's base URL is persisted too

Not just baked in at compile time via `--dart-define=API_BASE_URL`: a binary
built once by the release workflow and handed to someone else is only
useful if it can point at *their* own backend, not whichever one built it
(a separate storage key from the session token -- see
`core/server_url_provider.dart`). It's editable from the login screen
(before ever signing in -- committed just before the actual login/register
call, so that call always goes to whatever the field currently says) and
from the settings screen (which logs out first, since a session token from
one backend is meaningless on another). See
[Getting started](../user-guide/getting-started.md) for this same field
explained for someone using the app rather than building it.

Every state transition in `AuthNotifier._bootstrap` is guarded by `state is
AuthUnknown`: changing the server URL rebuilds `AuthNotifier` (it watches
`dioProvider`, which watches the server URL) at the same moment a
login/logout call may already be in flight on the fresh instance, and
without the guard whichever finished last would silently win.

## Secure storage can throw, and that's expected

`flutter_secure_storage`'s Linux backend is the system keyring (libsecret);
one that isn't running or unlocked -- common outside a full GNOME/KDE
session -- makes every call throw `PlatformException` instead of returning
null. `TokenStorage`/`ServerUrlStorage` (`frontend/lib/core/`) both catch
that at every call site and treat it as "nothing stored"/"couldn't
persist": the alternative, letting it propagate out of `main()`'s startup
read, crashed the app before it ever showed a window. Both classes (and the
later `InsecureTlsStorage`) depend on a small `SecureStore` interface
(`core/secure_store.dart`) rather than `FlutterSecureStorage` directly,
specifically so a fake can stand in for it under `flutter test`, which has
no platform channel at all.

## The insecure-TLS toggle

Next to the server URL, on the same two screens, is a per-server toggle to
skip TLS certificate verification (`core/insecure_tls_provider.dart`, wired
into `dioProvider` via `core/insecure_tls_configurator.dart`) -- for a
homelab server sitting behind a reverse proxy with a self-signed
certificate, which otherwise can't be reached at all short of installing a
CA on every device. Off by default: it's a real reduction in security (any
network path can then impersonate the server), not just a convenience, so
it's opt-in rather than something CORS-style middleware could paper over.
It only does anything on Android and Linux desktop -- the web target can't
touch the browser's own TLS handshake from Dart at all, so
`insecure_tls_configurator_stub.dart` (picked via `dart.library.io`
conditional export) is a deliberate no-op there. See
[Security and networking](../deploy/security-and-networking.md) for when a
deploying operator would actually turn this on.

## Shared editing shape

`routines` and `activities` share the same nested "exercises, each with
sets" editing shape the backend's schemas do (see
[API surface](backend.md#api-surface)), including the same full-replace
semantics on save (`PUT`, not per-set `PATCH`). An activity's "start from a
saved routine" button copies a routine's exercises and target weights/reps
into a new activity client-side -- convenience only, not an API relationship
beyond the `routine_id` reference already stored on the created activity.

## Finishing a workout without a connection

A live workout is held in `liveActivityProvider` and written to disk on every
change (`live_session_storage.dart`), so killing the app mid-workout loses
nothing, and nothing about logging sets needs the server. What *does* use the
server -- "last time" hints, suggestions, trophies, the end-of-workout record
check -- is fetched in the background and simply absent when it fails: a
missing hint is never an error and never blocks a set.

Saving is the one thing that needs it, and the summary screen is built around
that failing:

- A failed save leaves the session where it is, on screen and on disk. The
  summary says so and offers Save again. A workout that is finished but not
  saved keeps a banner on every tab (`live_workout_banner.dart`), so there is
  always a way back to that Save button after wandering off.
- No HTTP status on the error means no response at all (dropped connection,
  timeout): the server may have stored the workout. The retry has to be
  recognisable as the same save, and the backend recognises it by title, start
  and end (see [Retried saves](backend.md#retried-saves)) -- so after such a
  failure the session records `pendingTitle` and the title field is locked to
  it. The title would otherwise be the one thing the person could change
  between attempts. `pendingTitle` is persisted with the session, so it
  survives the app being killed between attempts, and is cleared by a
  definite answer from the server (success, or an error with a status).
- The end-of-workout record check needs the server too. When it fails the
  summary says it could not check -- which is not the same as "no new
  records" -- and offers a retry, but only before saving: afterwards the
  server's "best" already includes this workout.

`test/features/activities/live/activity_summary_screen_test.dart` drives these
paths against a mocked `Dio`; the storage tests cover the kill-and-restore
round trip through the real `SharedPreferences` path.

## Supersets

Exercises sharing a `supersetGroup` are done back-to-back. A group only means
anything as a run of *adjacent* exercises, so every edit -- link with the next
exercise, take one out, move, remove -- goes through `models/superset.dart`,
which re-normalizes the list: each run of neighbours sharing a group has at
least two members, and runs are numbered 1, 2, ... in order. That also repairs
group numbers that arrive messy (a Hevy import reuses numbers, a restored
backup may be anything) the first time such a list is edited. The helpers are
generic over an accessor, so activities (live workout and the manual form) and
routines share one implementation and one set of tests.

Rows in these lists carry a `uid`, a process-local id (`models/uid.dart`,
never sent anywhere) used as their widget key. Without it, removing or moving
a set would leave a neighbour's `TextFormField` showing the old text, because
`initialValue` is only read once; reordering exercises made that unavoidable,
so rows are keyed, and the number fields sync their text to the model when it
changes from outside (a suggestion being filled in).

## What the live workout knows about past sessions

`GET /exercises/{id}/history` feeds three things, all computed client-side in
pure functions so they are unit-tested without a widget
(`features/progress/progression.dart`):

- **Last time** -- the previous session's sets, shown as the fields' hints.
- **A suggestion** -- a simple double progression: if every working set at the
  top weight got the same reps, add weight (2.5 kg, or 1 kg under 20 kg); if
  not, hold the weight and aim for the best set's reps on every set; if the
  for a body-weight exercise, one more
  rep. Warm-ups, and drop/failure sets when there are normal ones, are not a
  baseline. Tapping *Use* fills only values that are still empty.
- **A plateau** -- the best session (by estimated 1RM, or best reps when there
  is no load) is at least four sessions behind the latest, with a half-percent
  tolerance so noise does not count as progress.

Personal records (`models/exercise_records.dart`) use `GET
/exercises/{id}/records` and the same rules everywhere: a set counts only if it
beats the prior best *and* every earlier set in the workout, warm-ups never
count, and reps count only for a set with no load. The live screen only flags
an exercise that has history (nothing to have beaten otherwise); the summary
screen counts a first-ever set as a record, as it always did.

## "Which athlete do you resemble?" is a best-effort estimate, computed on the device

`features/personas/` compares the person with a few hand-picked athlete
archetypes (sprinter, distance runner, weightlifter, powerlifter,
bodybuilder, gymnast) and draws two overlaid shapes on a radar chart: how close
their *body* is to each, and how close their *training* is. Like the stats page
it has no endpoint -- it reads the measurements, activities, exercise catalog
and profile height the app already loads. The numbers in `persona_profiles.dart`
are rough on purpose; this is meant to be fun and explainable, not sports
science, and the page says so.

- **Body.** `computeBodyFeatures` turns the latest value of each measurement
  field (not just the newest entry: people log partial sets) into ratios --
  FFMI, body fat, waist and thigh/arm over height, shoulders over waist -- so
  a short and a tall person with the same build compare alike. Each feature
  scores a bell curve around the archetype's typical value (one tolerance away
  is about 60%), weighted (height counts half), and the body score is the
  weighted mean. Fewer than three known features means no score rather than a
  guess; the page lists which inputs would unlock more. A smart scale's data
  adds two more: a muscle index (its muscle mass over height squared) and the
  lower-body muscle share (leg over arm-plus-leg segmental muscle, which
  separates leg-heavy builds like sprinters and lifters from upper-body-heavy
  ones like gymnasts). Scales define "muscle" differently, so the muscle index
  targets are only approximate.
- **Training.** Every non-warm-up set goes into exactly one of five focuses
  (max strength, muscle building, explosive, endurance, bodyweight & skill) by
  its weight, reps, distance, time and exercise name (`classifySet`). A cardio
  set counts one set-equivalent per three minutes, otherwise an hour of running
  would weigh the same as one bench set. The score is one minus the total
  variation distance between the person's mix and the archetype's, i.e. how
  much of their training already overlaps it. Under ten set-equivalents there is
  no score.
- **Known limitation.** The reference bodies are generic adult-male proportions
  because the app does not know anyone's sex; the page warns about it. Adding a
  profile field and per-sex targets would be the fix.

## The web target needs the backend's CORS middleware

A browser enforces CORS on cross-origin requests, and the frontend's origin
(whatever serves the Flutter web build) is never the backend's own -- native
targets (Android) don't go through a browser and aren't affected either
way. This was found, not assumed -- by actually running the built web app in
a browser against a live backend, which is what surfaced the missing
`CORSMiddleware` (`backend/src/dinatos_backend/main.py`) as a
`net::ERR_FAILED`/"could not reach the server" in the first place;
`flutter analyze`/`flutter test` have no way to catch a CORS problem, since
there's no browser involved in either. See
[Security and networking](../deploy/security-and-networking.md) for the
`cors_allowed_origins` setting this depends on.

The `/docs` route (see [API documentation](backend.md#api-documentation)) is
the same kind of browser-only problem, and needed a browser to find for the
same reason.
