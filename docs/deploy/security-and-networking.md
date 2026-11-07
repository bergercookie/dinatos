# Security and networking

This page shows how to make a Dinatos instance safe on a network. It covers the reverse proxy, TLS, CORS, API keys and self-signed certificates.

## Network exposure

`docker-compose.yml` publishes Postgres (port `5432`) and the app container (port `8000`) on `127.0.0.1` only. Other machines cannot reach them.

To make the instance reachable from other machines:

1. Put a reverse proxy in front of port 8000. nginx, Caddy and Traefik are possible choices.
2. Terminate TLS in the proxy. The app has no TLS of its own.

## CORS

CORS controls which web origins can call the API from a browser. To set it, use `DINATOS_CORS_ALLOWED_ORIGINS`. See the [Configuration reference](configuration.md).

- The default `["*"]` allows any origin. This is safe because login uses a bearer token in a header, not a cookie. No session exists for another site to misuse.
- The built-in web app uses the same origin as the API, so it does not need CORS. Native apps do not need CORS either.
- You need CORS only for a web app on a different origin. See [Clients](clients.md).

To allow only the origin of that web app, set:

```yaml
DINATOS_CORS_ALLOWED_ORIGINS: '["https://app.example.com"]'
```

If you use only the built-in web app, you can block all other origins. Set the value to `[]`.

## API keys and the MCP endpoint

`/mcp` serves the [MCP server](../user-guide/mcp-server.md). It accepts only API keys, in the form `Authorization: Bearer dnk_...`. Users make API keys in **Settings -> API keys**.

Dinatos shows a key one time and stores only a hash of it. Anyone who has a key can act as its owner. The key cannot manage keys or administer the server.

Your reverse proxy must follow these rules for `/mcp`:

- Serve `/mcp` over HTTPS. Over HTTP, the key travels in plain text.
- Pass the `Authorization` header through.
- Do not buffer or cache `/mcp` responses.

The MCP server does not need sticky sessions.

To keep MCP internal, use one of these methods:

- Block `/mcp` at the proxy.
- Set `DINATOS_MCP_ENABLED=false` in the app. See the [Configuration reference](configuration.md). `/mcp` then answers 404. Nothing else depends on it.

## Self-signed certificates

A client cannot verify a self-signed certificate, so it refuses to connect.

On the Android and Linux apps, users can turn on **Allow self-signed certificates** next to **Server URL**. This option is off by default. It skips the certificate checks for that server. Browsers have no such option.

A certificate from a certificate authority, for example Let's Encrypt, removes this problem.

## Accounts and sessions

- Dinatos hashes passwords with Argon2.
- A login lasts `DINATOS_SESSION_TTL_DAYS` days (default 30). A user can end a login at any time with a logout.
- Anyone can register, until an administrator turns registration off in **Settings -> Administration**, or you set `DINATOS_ALLOW_REGISTRATION=false`. The variable overrides the administrator.
- The first account is the administrator.

To report a vulnerability, follow the [security policy](https://github.com/bergercookie/dinatos/blob/main/SECURITY.md).
