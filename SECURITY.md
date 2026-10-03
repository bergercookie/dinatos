# Security policy

## Supported versions

Dinatos is pre-1.0 (`0.x`). Only the latest release, and `main`, receive
security fixes; please reproduce against the latest release before
reporting.

## Reporting a vulnerability

Please do not open a public issue or PR for a security problem. Report it
privately through GitHub's private vulnerability reporting: on the
repository's **Security** tab, choose **Report a vulnerability**
(<https://github.com/bergercookie/dinatos/security/advisories/new>).

Helpful to include: the affected version or commit, how it is deployed
(Docker image, native client), steps to reproduce, and the impact you see.

## What to expect

Dinatos is maintained by an individual, so these are good-faith targets, not
guarantees:

- an acknowledgement of your report within about a week;
- a follow-up once the issue is confirmed or ruled out;
- a fix in a new release for confirmed issues, and credit in the advisory
  if you want it.

Please allow time for a fix before any public disclosure.

## Security-relevant design

A short summary; `docs/architecture/backend.md` ("Authentication") has the
reasoning.

- **Server-side sessions with opaque tokens.** `POST /auth/login` returns a
  random high-entropy bearer token, not a JWT. Only its SHA-256 hash is
  stored (`AuthSession`), and every authenticated request looks the session
  up.
- **Real logout.** `POST /auth/logout` revokes exactly the session its token
  names; other sessions of the same account are unaffected. Revoked,
  expired and unknown sessions all produce the same `401`.
- **Session lifetime.** 30 days by default (`session_ttl_days`).
- **Password hashing.** Argon2 (`argon2-cffi`); passwords are never stored
  in the clear.
- **Registration control.** Anyone can register unless
  `DINATOS_ALLOW_REGISTRATION=false`; the first account becomes admin, and
  `/admin/*` routes require the admin role.
- **Bearer token, not cookies.** Auth is an `Authorization` header, so the
  default CORS policy allows any origin (`cors_allowed_origins`, without
  credentials). Operators can restrict it for a locked-down deployment.
