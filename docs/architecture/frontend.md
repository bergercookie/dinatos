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

```
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
its own tour; Profile's "Take the tour again" restarts it. Its steps are
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
screen thinks it's logged in. Logging out (the profile screen's app bar
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
from the profile screen (which logs out first, since a session token from
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
