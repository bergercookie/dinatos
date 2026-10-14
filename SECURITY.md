# Security policy

How to report a vulnerability in Dinatos, and a summary of its security design.

## Supported versions

Dinatos is pre-1.0 (`0.x`). Only the latest release and `main` receive security fixes. Reproduce on the latest release before reporting.

## Report a vulnerability

Do not open a public issue or pull request.

1. Go to the repository's **Security** tab.
2. Choose **Report a vulnerability**, or open <https://github.com/bergercookie/dinatos/security/advisories/new>.
3. Include the affected version or commit, how you deploy it (Docker image or native client), steps to reproduce, and the impact.

## What to expect

One individual maintains Dinatos. These are good-faith targets, not guarantees:

- Acknowledgement within about a week.
- A follow-up once the issue is confirmed or ruled out.
- A fix in a new release for confirmed issues, with credit in the advisory if you want it.

Please allow time for a fix before public disclosure.

## Security design

| Area | Behaviour |
|---|---|
| Sessions | `POST /auth/login` returns a random bearer token. Only its SHA-256 hash is stored. Every request checks the session in the database. |
| Logout | `POST /auth/logout` revokes only the session whose token you send. Revoked, expired and unknown tokens all return `401`. |
| Lifetime | 30 days by default (`DINATOS_SESSION_TTL_DAYS`). |
| Passwords | Hashed with Argon2. Never stored in the clear. |
| Registration | Open unless `DINATOS_ALLOW_REGISTRATION=false`. The first account becomes administrator. `/admin/*` needs the admin role. |
| API keys | `dnk_` keys for the MCP endpoint. Shown once, stored as a hash, revocable individually. They cannot manage keys or administer the server. |
| Cookies and CORS | Auth uses an `Authorization` header, not cookies, so CORS allows any origin by default (without credentials). Restrict it with `DINATOS_CORS_ALLOWED_ORIGINS`. |

For operators: see [Security and networking](https://github.com/bergercookie/dinatos/blob/main/docs/deploy/security-and-networking.md).
