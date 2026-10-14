# Security and networking

How to expose Dinatos safely: reverse proxy and TLS, CORS, API keys, and self-signed certificates.

## Network exposure

`docker-compose.yml` publishes Postgres (`5432`) and the app (`8000`) on `127.0.0.1` only. Other machines cannot reach them.

To make Dinatos reachable elsewhere:

1. Put a reverse proxy (nginx, Caddy, Traefik) in front of port 8000.
2. Terminate TLS in the proxy. The app has no TLS of its own.

## CORS

CORS controls which web origins a browser lets call the API. Set it with `DINATOS_CORS_ALLOWED_ORIGINS` (see [Configuration reference](configuration.md)).

- Default `["*"]` allows any origin. This is safe here because login uses a bearer token in a header, not cookies, so there is no ambient session for another site to abuse.
- The built-in web app is same-origin and never needs CORS. Native apps do not use it either.
- It matters only for a web build on another origin (see [Clients](clients.md)). Restrict it to that origin:

  ```yaml
  DINATOS_CORS_ALLOWED_ORIGINS: '["https://app.example.com"]'
  ```

- To lock it down fully when you use only the built-in app, set `[]`.

## API keys and the MCP endpoint

`/mcp` serves the [MCP server](../user-guide/mcp-server.md). It accepts only API keys (`Authorization: Bearer dnk_...`) that users create under **Settings -> API keys**. A key is shown once and stored only as a hash. Anyone holding it can act as its owner, except for managing keys and administering the server.

Proxy requirements:

- Serve it over HTTPS. Over HTTP the key travels in the clear.
- Pass the `Authorization` header through.
- Do not buffer or cache `/mcp` responses. No sticky sessions are needed.

To keep MCP internal, block `/mcp` at the proxy. Nothing else depends on it.

## Self-signed certificates

Clients cannot verify a self-signed certificate and refuse to connect. On Android and Linux apps, users can turn on **Allow self-signed certificates** next to the Server URL. It is off by default and skips certificate checks for that server. Browsers have no such option. A CA-issued certificate, such as Let's Encrypt, avoids the problem.

## Accounts and sessions

- Passwords are hashed with Argon2.
- Logins last `DINATOS_SESSION_TTL_DAYS` (default 30) and can be ended individually by logging out.
- Anyone can register unless you set `DINATOS_ALLOW_REGISTRATION=false`. The first account is the administrator.

Report vulnerabilities as described in the [security policy](https://github.com/bergercookie/dinatos/blob/main/SECURITY.md).
