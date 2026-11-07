# Frontend

This page explains how the Flutter app in `frontend/` works and why. It is for
contributors who change the app. You do not need to know the code first.

- To run the app, see [Running and testing](../development/workflow.md).
- To ship the app, see [Releases and packaging](../development/releases.md).

## Overview

`frontend/` is a [Flutter](https://flutter.dev) app. It talks to the REST API
of the backend. One codebase builds for web, Android and Linux desktop.

The app uses these tools:

- **No code generation.** The app has no `build_runner` and no `freezed`.
  Each model is a hand-written class with `fromJson` and `toJson`. To change
  the shape of a model, edit one file. You do not need to generate code.
- **Plain [Riverpod](https://riverpod.dev)** for state. The app uses
  `Provider`, `StateNotifierProvider` and `FutureProvider`. It does not use
  the `@riverpod` generator. A *provider* is a global value that the app
  builds when it is first needed. Widgets watch a provider and rebuild when
  it changes.
- **[Dio](https://pub.dev/packages/dio)** is the HTTP client.
- **[go_router](https://pub.dev/packages/go_router)** does the navigation.

The code has this layout:

```text
frontend/lib/
  core/       API client (Dio + auth interceptor), auth state and storage,
              routing, theme
  models/     Request/response types, one file per resource
  features/   One directory per area (exercises, routines, activities, calendar,
              profile, measurements, auth, home, onboarding, ...). Each has a
              repository (wraps Dio), Riverpod providers, and screens.
```

This page uses these terms:

- **Activity**: a logged workout.
- **Routine**: a saved workout template.
- **Planned workout**: a routine or workout that has a date.
- **Live workout**: the screen of a workout in progress. The app has not
  saved it as an activity yet.
- **Superset**: a group of exercises that the user does back-to-back.

For the first three terms, see [Domain model](domain-model.md).

## Authentication

The app follows the backend. For the backend side, see
[Authentication](backend.md#authentication).

- The app keeps the session token in `flutter_secure_storage`. It does not
  use a cookie.
- The app has no refresh token. A Dio interceptor catches a 401 from any
  request. The app then clears the token and goes to `/login`. A 401 always
  means "log in again".
- `go_router` redirects on the auth state in `AuthNotifier`
  (`core/auth/auth_notifier.dart`). It does not use what a screen believes.
- On logout, the app calls `POST /auth/logout`. Then it clears the local
  token, also if the call failed. If the backend is not reachable, the
  person must not stay signed in.

## Server URL

The backend URL is not only a compile-time constant (`--dart-define=API_BASE_URL`,
see `core/api_config.dart`). The app also stores the URL on the device
(`core/server_url_provider.dart`). The URL has its own storage key, separate
from the token. This way, one released binary can use the self-hosted server
of any person.

- The user can edit the URL on the login screen. The app saves the URL just
  before the login or register call. This makes the call go to the URL that
  the field shows now.
- The user can edit the URL in Settings. Settings logs the user out first,
  because a token from one server is not valid on another server.
- For the user description, see
  [Getting started](../user-guide/getting-started.md).

Note: if the URL changes, the app rebuilds `AuthNotifier`. `AuthNotifier`
watches `dioProvider`, and `dioProvider` watches the URL. A login or logout
can be in progress on the new instance at that time. For this reason, a guard
protects every state change in `AuthNotifier._bootstrap`. The guard is
`state is AuthUnknown`. Without the guard, the call that finishes last wins.

## Secure storage can throw

On Linux, `flutter_secure_storage` uses the system keyring (libsecret). The
keyring can be not running or locked. This is common outside a full GNOME or
KDE session. In this case, every call throws `PlatformException`. It does not
return null.

- `TokenStorage`, `ServerUrlStorage` and `InsecureTlsStorage` catch the
  exception at every call. All three are in `frontend/lib/core/`. They treat
  the error as "nothing stored" or "could not persist". Once, the exception
  left the startup read of `main()`. The app then crashed before it showed a
  window. Do not remove these catches.
- All three classes use a small `SecureStore` interface
  (`core/secure_store.dart`). This lets a test give a fake store to them.
  `flutter test` has no platform channel.

## Insecure-TLS toggle

Login and Settings show a switch next to the server URL. The switch is for one
server. When it is on, the app does not verify the TLS certificate. It is for
homelab servers that use a reverse proxy with a self-signed certificate.

- **The switch is off by default.** It reduces security. When it is on, any
  network path can pretend to be the server.
- The code is in `core/insecure_tls_provider.dart`. The file
  `core/insecure_tls_configurator.dart` applies it to Dio.
- **It works on Android and Linux only.** A browser does its own TLS
  handshake. On web, the conditional export (`dart.library.io`) selects
  `insecure_tls_configurator_stub.dart`. This file does nothing on purpose.
- To learn when an operator must turn it on, see
  [Security and networking](../deploy/security-and-networking.md).

## CORS on the web target

A browser blocks a cross-origin request unless the server allows it. The
origin of the web build is seldom the origin of the backend. For this reason,
the backend installs `CORSMiddleware` (`backend/src/dinatos_backend/main.py`).
The setting `cors_allowed_origins` configures it. See
[Security and networking](../deploy/security-and-networking.md). Android and
Linux do not use CORS.

`flutter analyze` and `flutter test` cannot find a CORS failure, because they
do not use a browser. The symptom is `net::ERR_FAILED` or "could not reach the
server". To test a change to the web API, load the built app in a browser.
The `/docs` page has the same kind of problem. It only fails in a browser. See
[API documentation](backend.md#api-documentation).

## First-run tour

The code in `features/onboarding/` guides a new account. The tour helps the
user set the units, save a first routine and log a first workout. It dims the
screen, except the control that the user must press next.

The tour is an overlay. It is not a screen. `OnboardingOverlay` is the
`builder` of `MaterialApp.router`. It is above every route, so a screen does
not need to know about it. One thing is necessary. You must wrap each widget
that the tour points at in `OnboardingTarget`. This widget draws nothing. It
only reports its position.

The tour follows these design rules:

- **A step ends when the app did something. It does not end when the user
  pressed something.** A step advances when the router reaches a path
  (`advanceOnLocation`). It also advances when the app reports an event
  (`advanceOnEvent`), for example "profile saved". Do not put a pointer
  listener on the highlighted widget. Assistive technology and browser tests
  activate a control with a *semantic tap*. A pointer listener never sees a
  semantic tap. The tour then stops, and the people who need it most cannot
  continue.
- **Only a single-press step is modal.** The overlay is above the `Navigator`
  of the app. Dropdowns and bottom sheets (for example the exercise picker)
  show *below* the dimming. A step that needs typing or picking keeps the app
  usable. It draws only a ring and offers "Skip step".
- **A missing target never traps the user.** A modal step blocks input only
  when its target is visible. A target in an inactive tab is not visible,
  also if an `IndexedStack` keeps the tab alive. In that case, the card
  docks and the screen is not dimmed. "Skip step" and "Skip tour" always work.

More facts:

- The app stores the completion per account in `shared_preferences`. The key
  is `onboarding_seen_<user id>`. Settings has the action "Take the tour
  again".
- The steps are data in `onboarding_steps.dart`. To add or reorder a step,
  edit that list. Then add an `OnboardingTarget` where the step points.
- `e2e/` drives the tour in a real browser. See
  [CI and checks](../development/ci.md).

## Routines and activities share an editor shape

A routine and an activity both have a nested list of exercises. Each exercise
has sets. The app matches the backend schemas. See
[API surface](backend.md#api-surface). A save replaces the whole object with
`PUT`. The app does not send `PATCH` for each set.

"Start from a saved routine" runs on the client. It copies the exercises of
the routine and their target weights and reps into a new activity. The only
API link is the `routine_id` that the backend stores on the new activity.

## Supersets

Exercises with the same `supersetGroup` number happen back-to-back. A group
makes sense only as a run of *adjacent* exercises. Every edit goes through
`models/superset.dart`. The edits are link, unlink, move and remove. The
file normalizes the list again after each edit:

- Every run of neighbors with the same group has at least two members.
- The runs have the numbers 1, 2, and so on, in order.

This also repairs untidy numbers from a Hevy import or a restored backup. The
repair happens the first time that a user edits the list. The helpers take an
accessor. Because of this, the live workout, the manual activity form and the
routines use one implementation and one test suite.

Each row in these lists has a `uid`. A `uid` is an ID that is local to the
process (`models/uid.dart`). The app never sends it to the server. The app
uses it as the widget key. Without it, a removed or moved set leaves stale
text in the `TextFormField` of a neighbor, because Flutter reads
`initialValue` only once. The number fields also update their text when the
model changes from outside. An example is a suggestion that the app fills in.

## Live workout

The app keeps a live workout in `liveActivityProvider`. It writes the workout
to disk after every change
(`activities/live/live_session_storage.dart`). If the system stops the app, the
workout is not lost. The app does not need the server to log sets.

The app gets some extra data from the server in the background. If a request
fails, the data is not shown. This applies to these items: "last time" hints,
suggestions, trophies and the record check. A missing hint never blocks a
set.

### Saving offline

A save is the one step that needs the server. The summary screen
(`activity_summary_screen.dart`) handles the case that the save fails.

- **A failed save keeps the session.** The session stays on the screen and on
  disk. The screen shows a Save again button. A banner on every tab shows a workout that the user finished but did not save
  (`features/home/live_workout_banner.dart`).
- **No HTTP status means no response.** For example, the connection dropped or
  the request timed out. The server can have stored the workout. The backend
  recognizes a retry by the title, the start and the end. See
  [Retried saves](backend.md#retried-saves). After such a failure, the
  session records `pendingTitle` and locks the title field to it. The title
  is the one value that the user can change between attempts. The app saves
  `pendingTitle` to disk. Any definite answer from the server clears it. A
  definite answer is a success, or an error with a status.
- **The record check also needs the server.** If it fails, the summary says
  that it could not check. This is not the same as "no new records". The
  summary offers a retry, and only before the save. After the save, the
  "best" value from the server already includes this workout.

The tests are in these files:

- `test/features/activities/live/activity_summary_screen_test.dart` uses a
  mocked `Dio`.
- The storage tests use a real `SharedPreferences` and test a kill and a
  restore.

### Finishing drops what was not done

`LiveActivityNotifier.finish()` removes each exercise that has no completed
set. It also removes the sets that the user never ticked from the other
exercises. Only ticked sets count in records, history and totals. If the app
saved an untouched planned set, it would record work that did not happen.

- `LiveActivitySession.unfinished` counts what the app would drop.
  `finishedExercises` is the result.
- Exercises use the same `removeItem` path as the remove button. The app dissolves a superset with one member left.
- `_confirmFinish` asks the user first when the app would lose something.
  "Keep logging" does not change the session.

### Past sessions: hints, suggestions, plateaus, records

`GET /exercises/{id}/history` gives data to three features. Pure functions in
`features/progress/progression.dart` compute them on the client. This lets
tests run them without widgets.

- **Last time**: the sets of the previous session. The app shows them as hints
  in the fields.
- **Suggestion**: a simple double progression that uses the last session.
  - If every working set at the top weight got the same reps, add weight. Add
    2.5 kg, or 1 kg below 20 kg. Aim for those reps.
  - Otherwise, keep the weight. Aim for the reps of the best set on every set.
  - For a body-weight exercise, suggest one more rep.
  - A warm-up is never a baseline. A drop set or failure set is also not a
    baseline, unless no other set exists.
  - When the user taps *Use*, the app fills only the values that are still
    empty.
- **Plateau**: the best session is at least four sessions behind the latest
  session. The best session has the highest estimated one-rep max. If there
  is no load, it has the best reps. A result that beats the best by less than
  0.5% is noise. It is not progress.

Personal records use the same rules everywhere. The code is in
`models/exercise_records.dart`. The data comes from
`GET /exercises/{id}/records`.

- A set counts only if it beats the prior best *and* every earlier set in the
  same workout.
- A warm-up never counts.
- Reps count only for a set with no load.
- The live screen flags only the exercises that have a history. The summary
  screen counts a first-ever set as a record.

### Add many exercises from a typed list

*Add many* on the live screen opens `bulk_add_sheet.dart`. The user types
a list, for example "1 reverse lunges 2 bench press 3 pull ups". The user
reviews the matches and adds them all. The app adds them without sets, as for
a single *Add exercise*. The three steps stay on the screen. Each row shows
how sure the match is. A free-text box with a hidden format is where people
give up. The app adds nothing until the user presses the button.

- **Text only, fully on the device.** The exercise catalog is already in
  memory, so the feature has no endpoint. The keyboard does the dictation.
  The app has no speech recognition.
- **Splitting** (`splitExerciseList` in `exercise_text_matcher.dart`): the
  numbers are the separators. They can be digits or words. Dictation gives no
  punctuation. Only the *next expected* number splits. For this reason, "one
  arm dumbbell row" stays whole. A "1" at the start of a new line starts a
  new run. This is how a second dictation appends to the list. If there is
  no leading "1", the app splits on new lines, commas, and the words "and",
  "then" and "next".
- **Matching** (`ExerciseMatcher`): the matcher ignores word order, case,
  plurals and punctuation. It expands `db` and `bb`. It treats "pull ups" as
  "Pullup". It accepts a one-letter error in a long word. When two exercises
  tie, the exercise that the user logged most wins.

  | Result | Meaning | Ticked by default |
  | --- | --- | --- |
  | Matched | The whole name matches, with no extra words | yes |
  | Best guess | All words appear in a longer name | yes |
  | Not sure | Some words match | no |
  | No match | No word matches | no |

  The app does not tick the uncertain rows. A wrong exercise in the middle of a
  workout costs more than one extra tap.
- The tests are `test/features/exercise_text_matcher_test.dart` and
  `test/features/activities/live/bulk_add_sheet_test.dart`.

## Planned workouts and reminders

The backend stores a planned workout, not the client state. The code is in
`lib/features/calendar/`. For the backend side, see "Calendar feed" in
[Backend](backend.md) and the `/planned-workouts` endpoint. The client has
these points:

- **Reminders are local notifications. They are not push messages.**
  `workoutReminderSyncProvider` (the app root watches it) schedules the next
  50 reminders again whenever `plannedWorkoutListProvider` changes. It clears
  them on logout. It does *not* clear them while auth is `AuthUnknown` or
  when the fetch fails. For this reason, an offline start never cancels the
  reminder for tomorrow.
  - Android uses `AndroidScheduleMode.inexactAllowWhileIdle`. In doze mode, a
    reminder can be a few minutes late. The app does not need the
    exact-alarm permission, which Play restricts.
  - The time is an absolute instant, passed as UTC. The app does not need a
    timezone database.
  - `AndroidManifest.xml` must declare the two receivers of the plugin and
    `RECEIVE_BOOT_COMPLETED`. Without them, a scheduled notification never
    shows.
- **One tap callback serves two services.** `flutter_local_notifications` has
  one `onDidReceiveNotificationResponse`. A second `initialize()` call
  replaces the first one without a warning. For this reason, the live-workout
  notification and the reminders both pass `dispatchNotificationTap`
  (`core/notification_taps.dart`). Each registers a listener for its own
  payloads. The live notification has no payload. The payload of a reminder is
  `planned:<id>`.
- **A tap opens the route `/activities/plan/<id>/start`.** It does not call
  back into a widget. The notification can start the app cold, and a route
  survives the login redirect. `StartPlannedWorkoutScreen` loads the plan and
  its routine. Then it starts the live workout. `startPlannedWorkout` is the
  shared entry point. The Home card, the day sheet and the third option of the
  **Start activity** sheet also use it.
- **The live session carries `plannedWorkoutId`.** The app saves it with the
  session. The summary sends it with `POST /activities`. The *title* of the
  plan becomes the default activity title. The name of the routine does not.
- The Start activity sheet reads the plans that Home already loaded
  (`valueOrNull`). It does not wait for the network.

## Routine shortcuts (Android)

The user can pin a routine to the Android home screen. A tap on the shortcut
starts a workout from it. The Dart code is in `features/routines/routine_shortcuts.dart`. The
Kotlin side, in `MainActivity.kt`, is a thin bridge. All decisions are in Dart,
where tests can reach them.

- **One channel, three names.** The channel `dev.bergercookie.dinatos/shortcuts`
  has `pinShortcut` (Dart to Android), `initialRoutineId` (Dart to Android) and
  `routineLaunched` (Android to Dart). The shortcut fires an intent with the
  action `dev.bergercookie.dinatos.action.START_ROUTINE` and the extra
  `routine_id`. Both sides repeat these strings. `shortcut_contract_test.dart`
  reads `MainActivity.kt` and fails if one side changes alone.
- **The shortcut id is `routine-<id>`.** `requestPinShortcut` with an id that
  is already pinned updates it. A second request does not add a copy.
- **A launch is a pending value, not a navigation.** `MainActivity` hands over
  the routine id: once for a cold start (`initialRoutineId`) and through
  `routineLaunched` when the app is already running (`launchMode="singleTop"`
  calls `onNewIntent`). `routineShortcutLaunchProvider` (the app root watches
  it) stores it in `pendingRoutineLaunchProvider`. It opens
  `/routines/<id>/start` only when the user is `AuthAuthenticated`. A launch
  while signed out waits for the login. The provider clears the value first, so
  a later login change does not start the workout again.
- **A restored activity does not start a workout.** Android re-delivers the
  original intent when it recreates the activity (for example from the list of
  recent apps). `MainActivity` ignores the launch intent when `savedInstanceState`
  is not null, and it removes the extra after the first read.
- **`StartRoutineScreen` reuses the play-button flow.** It loads the routine
  and calls `startWorkoutFromRoutine`, which asks before it discards a workout
  in progress. A deleted routine (404) shows a message and no retry. The route
  is top level, outside the shell, so the screen goes away when the workout
  opens.
- **Only Android offers it.** `routineShortcutServiceProvider` returns a no-op
  service on web, desktop and iOS. The routine editor hides its "Add to home
  screen" button when `isSupported` is false. `flutter test` runs
  with the Android platform by default, so tests override the service.
- Nobody can compile the Kotlin in a plain `flutter test` run. The contract
  test checks the strings only. The pin prompt and a real tap need a device or
  emulator (`just android run`).

## "Which athlete do you resemble?"

The code in `features/personas/` compares the user with hand-picked archetypes.
The archetypes are sprinter, distance runner, weightlifter, powerlifter,
bodybuilder and gymnast. The feature draws two radar-chart shapes: body
closeness and training closeness. It has no endpoint. It uses data that the
app already loads: measurements, activities, the exercise catalog and the
height in the profile. The numbers in `persona_profiles.dart` are rough on
purpose. The feature is for fun and is easy to explain. It is not sports
science, and the page says so.

- **Body** (`computeBodyFeatures`):
  - It uses the latest value of *each* measurement field. It does not use
    only the newest entry, because people log partial sets.
  - It converts the values to ratios: FFMI, body fat, waist over height,
    thigh over height, arm over height and shoulders over waist. This lets
    short and tall people compare in the same way.
  - Each feature scores a bell curve around the typical value of the
    archetype. A value one tolerance away scores about 60%. The body score is
    the weighted mean. Height has half the weight.
  - If the app knows fewer than three features, there is no score. The page lists
    the inputs that would give more.
  - Smart-scale data adds a muscle index (muscle mass over height squared). It
    also adds the lower-body muscle share (leg muscle over arm-plus-leg
    segmental muscle). Scales define "muscle" in different ways. For this
    reason, the muscle-index targets are approximate.
- **Training** (`classifySet`):
  - Every set that is not a warm-up goes into exactly one of five focuses: max
    strength, muscle building, explosive, endurance, and bodyweight and skill.
    The inputs are weight, reps, distance, time and exercise name.
  - A cardio set counts as one set-equivalent for each 3 minutes. Without
    this, an hour of running would weigh the same as one bench set.
  - The score is 1 minus the total variation distance between the mix of the
    user and the mix of the archetype. This shows how much the two mixes
    overlap. Fewer than 10 set-equivalents give no score.
- **Known limitation:** the reference bodies have the proportions of a generic
  adult male, because the app does not know the sex of the user. The page
  warns about it. To fix it, add a profile field and targets for each sex.
