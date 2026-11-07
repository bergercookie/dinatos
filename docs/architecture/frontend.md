# Frontend

This page explains the design decisions of the Flutter app in `frontend/`.
It is for contributors. To run the app, see
[Running and testing](../development/workflow.md). To ship it, see
[Releases and packaging](../development/releases.md). For the terms, see the
[domain model](domain-model.md).

## Overview

One [Flutter](https://flutter.dev) codebase builds for web, Android and Linux
desktop, and talks to the backend's REST API.

- **No code generation.** No `build_runner`, no `freezed`, no `@riverpod`.
  Models are hand-written classes with `fromJson`/`toJson`.
- **Plain [Riverpod](https://riverpod.dev)** for state, **Dio** for HTTP,
  **go_router** for navigation.

```text
frontend/lib/
  core/       API client and auth interceptor, auth state and storage, routing, theme
  models/     Request and response types, one file per resource
  features/   One directory per area, each with a repository, providers and screens
```

## Authentication

For the backend side, see [Authentication](backend.md#authentication).

- The session token lives in `flutter_secure_storage`, not a cookie.
- The app has no refresh token: a Dio interceptor turns any `401` into "log in
  again" (clear the token, go to `/login`).
- `go_router` redirects on the state in `AuthNotifier`, not on what a screen
  believes.
- Logout clears the local token even if `POST /auth/logout` fails, so an
  unreachable server never keeps someone signed in.

## Server URL

The app stores the backend URL on the device (`core/server_url_provider.dart`), not
only compiled in (`API_BASE_URL`), so one released binary works with anyone's
self-hosted server. Changing it in Settings logs out first, because a token
from one server is not valid on another.

> [!NOTE]
> A URL change rebuilds `AuthNotifier` (it watches `dioProvider`, which
> watches the URL) while a login can still be in flight. A guard
> (`state is AuthUnknown`) protects every state change in
> `AuthNotifier._bootstrap`; without it, whichever call finishes last wins.

## Secure storage can throw

On Linux, `flutter_secure_storage` throws `PlatformException` on every call
when the keyring is missing or locked, which is common outside a full GNOME or
KDE session. `TokenStorage`, `ServerUrlStorage` and `InsecureTlsStorage`
(`core/`) catch it and treat it as "nothing stored". An uncaught one once
crashed the app before its first frame: do not remove these catches. All three
use the `SecureStore` interface, so tests can pass a fake.

## Insecure-TLS toggle

A per-server switch next to the server URL skips certificate checks, for
homelab servers with a self-signed certificate. It is off by default, and it
works only on Android and Linux: browsers do their own TLS, so on web a
conditional import picks a stub that does nothing
(`core/insecure_tls_configurator*.dart`).

## CORS on the web target

A web build on another origin needs the backend's `CORSMiddleware`
(`cors_allowed_origins`; see
[Security and networking](../deploy/security-and-networking.md)). `flutter
test` cannot catch a CORS failure; only a real browser shows it.

## First-run tour

`features/onboarding/` guides a new account through setting units, saving a
first routine and logging a first workout. It is an overlay (the `builder` of
`MaterialApp.router`), not a screen, so screens do not know about it. A widget
the tour points at only needs an `OnboardingTarget` wrapper. The steps are
data in `onboarding_steps.dart`.

- **A step ends when the app did something, not on a press.** Steps advance on a route (`advanceOnLocation`) or an app event
  (`advanceOnEvent`). Assistive technology and browser tests press controls
  with a *semantic tap*, which a pointer listener never sees, so a listener
  would strand exactly the people who need the tour.
- **Only a single-press step is modal.** Pickers and bottom sheets open below
  the dimming, so a step that needs typing or picking only draws a ring.
- **A missing target never traps the user.** If the target is not visible
  (for example in an inactive tab), the step does not block input, and "Skip
  step" and "Skip tour" always work.

The app stores completion per account in `shared_preferences`
(`onboarding_seen_<user id>`).

## Supersets

The user does exercises with the same `supersetGroup` number back-to-back, which
only makes sense for *adjacent* exercises. Every edit (link, unlink, move,
remove) goes through `models/superset.dart`, which normalizes the list again after each edit: every run has at least two members, numbered 1, 2, ... in order.
This also repairs odd numbering from a Hevy import or a backup. The live
workout, the manual activity form and routines share this one implementation.

Every row has a process-local `uid` (`models/uid.dart`) used as its widget
key and never sent to the server. Without it, removing or moving a set leaves
stale text in a neighbor's `TextFormField`, which reads `initialValue` only
once.

## Live workout

A live workout lives in `liveActivityProvider`, and the app writes it to disk after every change, so it survives a killed app, and logging sets never
needs the server. "Last time" hints, suggestions and records arrive in the background; if that fails, they are simply not shown.

### Saving offline

Saving is the one step that needs the server (`activity_summary_screen.dart`).

- **A failed save keeps the workout**, on screen and on disk, with a banner on
  every tab until the save succeeds.
- **No response is not a rejection.** After a timeout or dropped connection
  the server may have saved it. The backend recognizes a retry by title, start
  and end ([Retried saves](backend.md#retried-saves)), so the app records the
  title it sent (`pendingTitle`) and locks the title field until the server
  gives a definite answer.
- **A failed record check is not "no new records".** The summary says it
  could not check, and offers a retry before saving.

### Finishing drops what was not done

`LiveActivityNotifier.finish()` drops untouched exercises and unticked sets,
because only ticked sets count in records, history and totals. Saving an
untouched planned set would record work that never happened. The app asks first when it would drop something.

### Hints, suggestions, plateaus and records

`GET /exercises/{id}/history` feeds three client-side features, as pure
functions in `features/progress/progression.dart`:

- **Last time**: the previous session's sets, shown as field hints.
- **Suggestion**: double progression from the last session. If every working
  set at the top weight hit the same reps, add 2.5 kg (1 kg below 20 kg);
  otherwise aim for the best set's reps. Body-weight exercises get one more
  rep. Warm-ups are never a baseline. *Use* fills only empty fields.
- **Plateau**: the best session (by estimated one-rep max) is four or more
  sessions old. Beating it by less than 0.5% is noise.

Personal records (`models/exercise_records.dart`) follow one rule everywhere:
a set must beat the prior best and every earlier set in the workout; warm-ups
never count, and reps count only for unloaded sets.

### Add many exercises from a typed list

*Add many* (`bulk_add_sheet.dart`) turns a typed or dictated list such as
"1 reverse lunges 2 bench press 3 pull ups" into exercises, entirely on the
device. Dictation has no punctuation, so the numbers separate items, and only
the *next expected* number splits ("one arm dumbbell row" stays whole). The
matcher (`ExerciseMatcher`) ignores order, case, plurals and punctuation, and
uncertain matches start unticked, because a wrong exercise mid-workout costs
more than an extra tap.

## Planned workouts and reminders

Plans live on the backend (`/planned-workouts`; see also
[Calendar feed](backend.md#calendar-feed)). The client code is in
`features/calendar/`.

- **Reminders are local notifications, not push.** The app schedules the next 50 again whenever the plan list changes, cleared on logout, and never
  cleared while auth is unknown or a fetch failed, so an offline start does
  not cancel tomorrow's reminder.
- Android uses inexact alarms (no exact-alarm permission, which Play
  restricts), so a reminder can be minutes late in doze mode. The manifest
  must declare the plugin's two receivers and `RECEIVE_BOOT_COMPLETED`, or
  scheduled notifications never show.
- **One tap callback for two services.** `flutter_local_notifications` keeps
  only the last `initialize()` callback, so the live-workout notification and
  the reminders share `dispatchNotificationTap` (`core/notification_taps.dart`).
- **A tap opens a route** (`/activities/plan/<id>/start`), not a widget
  callback, because a tap can cold-start the app and a route survives the
  login redirect. The plan's title becomes the default activity title.

## Routine shortcuts (Android)

The user can pin a routine to the Android home screen, and a tap starts a
workout from it. `MainActivity.kt` is a thin bridge; the decisions are in
`features/routines/routine_shortcuts.dart`, where tests can reach them.

- The channel, method and intent names appear in both Kotlin and Dart.
  `shortcut_contract_test.dart` reads `MainActivity.kt` and fails if one side
  changes alone. The shortcut id `routine-<id>` makes a second pin an update,
  not a copy.
- **A launch is a pending value, not a navigation.** It waits until the user signs in, then opens `/routines/<id>/start`, which reuses the play
  button's flow (including the "workout already in progress" question). The provider clears the value first, so a later login does not start it again.
- `MainActivity` ignores the launch intent when Android recreates the
  activity (for example from recent apps), so it cannot start a second
  workout.
- Off Android the service is a no-op. `flutter test` runs as Android, so
  tests override it. The Kotlin itself is only exercised on a device
  (`just android run`).

## "Which athlete do you resemble?"

`features/personas/` compares the user with six archetypes (sprinter,
distance runner, weightlifter, powerlifter, bodybuilder, gymnast) using data
the app already has, so there is no endpoint. It is for fun, not sports
science, and the page says so.

- **Body**: ratios rather than raw sizes (FFMI, body fat, waist, thigh and arm
  over height, shoulders over waist), each scored on a bell curve around the
  archetype. It uses the latest value of each field, because people log
  partial sets of measurements.
- **Training**: every working set goes into one of five focuses; cardio
  counts one set per 3 minutes, so an hour of running does not equal one
  bench set. The score is the overlap of the two mixes.
- Too little data gives no score rather than a misleading one.
- The backend has a port of this scoring for the MCP server; a shared fixture
  keeps the two equal (see [MCP server](backend.md#mcp-server)).
- **Known limitation:** the reference bodies are of a generic adult male,
  because the app does not know the user's sex.
