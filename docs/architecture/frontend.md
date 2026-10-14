# Frontend

How the Flutter app in `frontend/` is built and why. For contributors changing
the app; no prior knowledge of the code is assumed. To run it, see
[Running and testing](../development/workflow.md). To ship it, see
[Distribution](distribution.md).

## Overview

`frontend/` is a [Flutter](https://flutter.dev) app that talks to the backend's
REST API. One codebase targets web, Android and Linux desktop.

Stack choices:

- **No code generation.** No `build_runner`, no `freezed`. Models are
  hand-written classes with `fromJson`/`toJson`. Changing a model's shape means
  editing one file and regenerating nothing.
- **Plain [Riverpod](https://riverpod.dev)** for state (`Provider`,
  `StateNotifierProvider`, `FutureProvider`), not the `@riverpod` generator.
  A *provider* is a global, lazily built value that widgets watch and rebuild on.
- **[Dio](https://pub.dev/packages/dio)** as the HTTP client and
  **[go_router](https://pub.dev/packages/go_router)** for navigation.

```text
frontend/lib/
  core/       API client (Dio + auth interceptor), auth state and storage,
              routing, theme
  models/     Request/response types, one file per resource
  features/   One directory per area (exercises, routines, activities, calendar,
              profile, measurements, auth, home, onboarding, ...). Each has a
              repository (wraps Dio), Riverpod providers, and screens.
```

Vocabulary used below:

- **Activity**: a logged workout. **Routine**: a saved workout template.
  **Planned workout**: a routine or workout scheduled for a date. See
  [Domain model](domain-model.md).
- **Live workout**: the in-progress workout screen, before it is saved as an
  activity.
- **Superset**: exercises done back-to-back.

## Authentication

Mirrors the backend ([Authentication](backend.md#authentication)):

- The session token is stored with `flutter_secure_storage`, not a cookie.
- There is no refresh token. A 401 from *any* request (caught by a Dio
  interceptor) clears the token and routes to `/login`. A 401 always means
  "log in again".
- `go_router` redirects on the auth state held by `AuthNotifier`
  (`core/auth/auth_notifier.dart`), not on what a screen believes.
- Logout calls `POST /auth/logout`, then clears the local token *even if the
  call failed*. An unreachable backend must not leave the person signed in.

## Server URL

The backend URL is not only a compile-time constant (`--dart-define=API_BASE_URL`,
see `core/api_config.dart`). It is also stored on the device
(`core/server_url_provider.dart`, separate key from the token), so one released
binary can point at anyone's self-hosted server.

- Editable on the login screen. It is committed just before the login/register
  call, so that call goes to what the field shows now.
- Editable in Settings, which logs out first: a token from one server is
  meaningless on another.
- User-facing description: [Getting started](../user-guide/getting-started.md).

Gotcha: changing the URL rebuilds `AuthNotifier` (it watches `dioProvider`,
which watches the URL) while a login/logout may be in flight on the new
instance. Every state transition in `AuthNotifier._bootstrap` is therefore
guarded by `state is AuthUnknown`. Without the guard, whichever call finished
last would win.

## Secure storage can throw

On Linux, `flutter_secure_storage` uses the system keyring (libsecret). If it
is not running or unlocked (common outside a full GNOME/KDE session), every
call throws `PlatformException` instead of returning null.

- `TokenStorage`, `ServerUrlStorage` and `InsecureTlsStorage` (all in
  `frontend/lib/core/`) catch it at every call and treat it as "nothing
  stored" or "could not persist". Letting it escape `main()`'s startup read
  crashed the app before any window appeared. Do not remove these catches.
- All three depend on a small `SecureStore` interface
  (`core/secure_store.dart`) so tests can inject a fake. `flutter test` has no
  platform channel.

## Insecure-TLS toggle

Next to the server URL (login and Settings) is a per-server switch that skips
TLS certificate verification. It exists for homelab servers behind a reverse
proxy with a self-signed certificate.

- **Off by default.** It is a real security reduction: any network path can
  impersonate the server.
- Code: `core/insecure_tls_provider.dart`, applied to Dio by
  `core/insecure_tls_configurator.dart`.
- **Android and Linux only.** A browser owns its TLS handshake, so on web the
  conditional export (`dart.library.io`) selects
  `insecure_tls_configurator_stub.dart`, a deliberate no-op.
- When an operator should enable it:
  [Security and networking](../deploy/security-and-networking.md).

## CORS on the web target

A browser blocks cross-origin requests unless the server allows them, and the
web build's origin is rarely the backend's. The backend therefore installs
`CORSMiddleware` (`backend/src/dinatos_backend/main.py`), configured by
`cors_allowed_origins` ([Security and networking](../deploy/security-and-networking.md)).
Android and Linux are unaffected.

Neither `flutter analyze` nor `flutter test` can catch a CORS failure, because
no browser is involved. The symptom is `net::ERR_FAILED` or "could not reach
the server". Verify web API changes by loading the built app in a browser. The
`/docs` page ([API documentation](backend.md#api-documentation)) is the same
kind of browser-only problem.

## First-run tour

`features/onboarding/` guides a new account through setting units, saving a
first routine and logging a first workout. It dims the screen except the real
control to press next.

It is an overlay, not a screen. `OnboardingOverlay` is `MaterialApp.router`'s
`builder`, so it sits above every route and screens need not know it exists.
The only exception is wrapping the widgets it points at in `OnboardingTarget`,
which draws nothing and only reports its position.

Design rules:

- **Steps complete by what the app did, not what the user pressed.** A step
  advances when the router reaches a path (`advanceOnLocation`) or the app
  reports an event (`advanceOnEvent`, e.g. profile saved). Never use a pointer
  listener on the highlighted widget: assistive technology and browser tests
  activate controls with a *semantic tap*, which pointer listeners never see,
  and the tour would hang for exactly the people who need it.
- **Only single-press steps are modal.** The overlay sits above the app's own
  `Navigator`, so dropdowns and bottom sheets (the exercise picker) render
  *beneath* the dimming. Steps that need typing or picking leave the app
  usable, draw only a ring, and offer "Skip step".
- **A missing target never traps the user.** A modal step blocks input only
  once its target is actually visible (not in an inactive tab kept alive by an
  `IndexedStack`). Otherwise the card is docked with no dimming. "Skip step"
  and "Skip tour" always work.

Other facts:

- Completion is stored per account in `shared_preferences`
  (`onboarding_seen_<user id>`). Settings has "Take the tour again".
- Steps are data in `onboarding_steps.dart`. To add or reorder one, edit that
  list and add an `OnboardingTarget` where it points.
- `e2e/` drives the tour in a real browser:
  [CI and releases](../development/ci-and-releases.md).

## Routines and activities share an editor shape

Both edit a nested list of exercises, each with sets, matching the backend
schemas ([API surface](backend.md#api-surface)). Saving replaces the whole
object (`PUT`, not per-set `PATCH`).

"Start from a saved routine" copies the routine's exercises and target
weights/reps into a new activity on the client. The only API link is the
`routine_id` stored on the created activity.

## Supersets

Exercises sharing a `supersetGroup` number are done back-to-back. A group only
makes sense as a run of *adjacent* exercises, so every edit (link, unlink,
move, remove) goes through `models/superset.dart`, which re-normalizes the
list:

- every run of neighbours sharing a group has at least two members;
- runs are numbered 1, 2, ... in order.

This also repairs messy numbers from a Hevy import or a restored backup the
first time the list is edited. The helpers take an accessor, so live workouts,
the manual activity form and routines share one implementation and one test
suite.

Rows in these lists carry a `uid`, a process-local id (`models/uid.dart`, never
sent to the server) used as the widget key. Without it, removing or moving a
set leaves a neighbour's `TextFormField` showing stale text, because
`initialValue` is read only once. The number fields also resync their text when
the model changes from outside, e.g. a suggestion being filled in.

## Live workout

A live workout is held in `liveActivityProvider` and written to disk on every
change (`activities/live/live_session_storage.dart`). Killing the app loses
nothing, and logging sets never needs the server.

Server-backed extras are fetched in the background and are simply absent on
failure: "last time" hints, suggestions, trophies and the record check. A
missing hint never blocks a set.

### Saving offline

Saving is the one step that needs the server. The summary screen
(`activity_summary_screen.dart`) is built around it failing:

- **A failed save keeps the session** on screen and on disk, with a Save again
  button. A finished-but-unsaved workout shows a banner on every tab
  (`features/home/live_workout_banner.dart`).
- **No HTTP status means no response** (dropped connection, timeout), so the
  server may have stored the workout. The backend recognises a retry by title,
  start and end ([Retried saves](backend.md#retried-saves)). After such a
  failure the session records `pendingTitle` and locks the title field to it,
  because the title is the one thing the user could otherwise change between
  attempts. `pendingTitle` is persisted, and cleared by any definite server
  answer (success, or an error with a status).
- **The record check also needs the server.** On failure the summary says it
  could not check (not the same as "no new records") and offers a retry, only
  before saving. After saving, the server's "best" already includes this
  workout.

Tests: `test/features/activities/live/activity_summary_screen_test.dart` (mocked
`Dio`) and the storage tests (real `SharedPreferences` kill-and-restore).

### Finishing drops what was not done

`LiveActivityNotifier.finish()` removes exercises with no completed set, and
removes never-ticked sets from the others. Only ticked sets count anywhere
(records, history, totals), so saving an untouched planned set would record
work that did not happen.

- `LiveActivitySession.unfinished` counts what would be dropped;
  `finishedExercises` is the result.
- Exercises go through the same `removeItem` path as the remove button, so a
  superset left with one member is dissolved.
- `_confirmFinish` asks first whenever something would be lost. "Keep logging"
  leaves the session untouched.

### Past sessions: hints, suggestions, plateaus, records

`GET /exercises/{id}/history` feeds three features, computed client-side in
pure functions (`features/progress/progression.dart`) so they are unit-tested
without widgets:

- **Last time**: the previous session's sets, shown as field hints.
- **Suggestion**: a simple double progression based on the last session.
  - Every working set at the top weight got the same reps: add weight (2.5 kg,
    or 1 kg below 20 kg) and aim for those reps.
  - Otherwise: keep the weight and aim for the best set's reps on every set.
  - Body-weight exercise: one more rep.
  - Warm-ups never count as a baseline. Drop and failure sets do not either,
    unless nothing else exists.
  - Tapping *Use* fills only values still empty.
- **Plateau**: the best session (by estimated one-rep max, or best reps when
  there is no load) is at least four sessions behind the latest. Beating the
  best by under 0.5% is noise, not progress.

Personal records (`models/exercise_records.dart`, from
`GET /exercises/{id}/records`) follow the same rules everywhere:

- A set counts only if it beats the prior best *and* every earlier set in the
  same workout.
- Warm-ups never count.
- Reps count only for a set with no load.
- The live screen flags only exercises that have history. The summary screen
  counts a first-ever set as a record.

### Adding several exercises from a typed list

*Add several* on the live screen opens `bulk_add_sheet.dart`. The user types
"1 reverse lunges 2 bench press 3 pull ups", reviews the matches, and adds them
all (without sets, as with a single *Add exercise*). The three steps stay on
screen and each row says how sure the match is, because a free-text box with a
hidden format is where people give up. Nothing is added until the button is
pressed.

- **Text only, fully on device.** The exercise catalog is already in memory, so
  there is no endpoint. Dictation is the keyboard's job; the app has no speech
  recognition.
- **Splitting** (`splitExerciseList` in `exercise_text_matcher.dart`): numbers,
  as digits or words, are the separator, because dictation gives no
  punctuation. Only the *next expected* number splits, so "one arm dumbbell
  row" stays whole. A "1" opening a new line starts a new run, which is how a
  second dictation appends. Without a leading "1" it falls back to new lines,
  commas, and "and"/"then"/"next".
- **Matching** (`ExerciseMatcher`): ignores word order, case, plurals and
  punctuation; expands `db`/`bb`; treats "pull ups" as "Pullup"; forgives a
  one-letter slip in a long word. Ties go to the exercise logged most.

  | Result | Meaning | Ticked by default |
  | --- | --- | --- |
  | Matched | Whole name matches, no extra words | yes |
  | Best guess | All words appear in a longer name | yes |
  | Not sure | Some words match | no |
  | No match | None match | no |

  Unticked by default because a wrong exercise mid-workout costs more than
  one extra tap.
- Tests: `test/features/exercise_text_matcher_test.dart` and
  `test/features/activities/live/bulk_add_sheet_test.dart`.

## Planned workouts and reminders

A planned workout (`lib/features/calendar/`) is stored by the backend, not
client state: see "Calendar feed" in [Backend](backend.md) and
`/planned-workouts`. Client-side points:

- **Reminders are local notifications, not push.**
  `workoutReminderSyncProvider` (watched from the app root) reschedules the next
  50 reminders whenever `plannedWorkoutListProvider` changes, and clears them on
  logout. It does *not* clear them while auth is still `AuthUnknown` or when
  the fetch fails, so starting offline never cancels tomorrow's reminder.
  - Android uses `AndroidScheduleMode.inexactAllowWhileIdle`: a reminder may be
    a few minutes late in doze, but no exact-alarm permission is needed (Play
    restricts it).
  - The time is an absolute instant passed as UTC, so no timezone database is
    needed.
  - `AndroidManifest.xml` must declare the plugin's two receivers and
    `RECEIVE_BOOT_COMPLETED`. Without them a scheduled notification never shows.
- **One tap callback, two services.** `flutter_local_notifications` keeps a
  single `onDidReceiveNotificationResponse`, and a second `initialize()` call
  silently replaces the first. Both the live-workout notification and the
  reminders therefore pass `dispatchNotificationTap`
  (`core/notification_taps.dart`) and register a listener for their own
  payloads (the live one has none; a reminder's is `planned:<id>`).
- **A tap opens the route `/activities/plan/<id>/start`**, not a callback into
  a widget: the notification may cold-start the app, and a route survives the
  login redirect. `StartPlannedWorkoutScreen` loads the plan and its routine,
  then starts the live workout. `startPlannedWorkout` is the shared entry point,
  also used by the Home card, the day sheet and the third option of the
  **Start activity** sheet.
- **The live session carries `plannedWorkoutId`** (persisted with it) and the
  summary sends it with `POST /activities`. The plan's *title*, not the
  routine's name, becomes the default activity title.
- The Start activity sheet reads the plans Home already loaded (`valueOrNull`)
  rather than waiting on the network.

## "Which athlete do you resemble?"

`features/personas/` compares the user with hand-picked archetypes (sprinter,
distance runner, weightlifter, powerlifter, bodybuilder, gymnast) and draws two
radar-chart shapes: body closeness and training closeness. It has no endpoint.
It reads measurements, activities, the exercise catalog and profile height the
app already loads. The numbers in `persona_profiles.dart` are rough on purpose:
this is for fun and explainable, not sports science, and the page says so.

- **Body** (`computeBodyFeatures`):
  - Uses the latest value of *each* measurement field, not just the newest
    entry, because people log partial sets.
  - Converts them to ratios (FFMI, body fat, waist and thigh/arm over height,
    shoulders over waist) so short and tall people compare alike.
  - Each feature scores a bell curve around the archetype's typical value (one
    tolerance away is about 60%). The body score is the weighted mean, with
    height weighted half.
  - Fewer than three known features gives no score. The page lists which
    inputs would unlock more.
  - Smart-scale data adds a muscle index (muscle mass over height squared) and
    the lower-body muscle share (leg over arm-plus-leg segmental muscle).
    Scales define "muscle" differently, so the muscle-index targets are
    approximate.
- **Training** (`classifySet`):
  - Every non-warm-up set goes into exactly one of five focuses: max strength,
    muscle building, explosive, endurance, bodyweight & skill. Inputs are
    weight, reps, distance, time and exercise name.
  - A cardio set counts one set-equivalent per three minutes, otherwise an hour
    of running would weigh the same as one bench set.
  - Score = 1 minus the total variation distance between the user's mix and the
    archetype's, i.e. how much they overlap. Under ten set-equivalents gives
    no score.
- **Known limitation:** reference bodies are generic adult-male proportions,
  because the app does not know sex. The page warns about it. The fix is a
  profile field plus per-sex targets.
