# Security and networking

## Binds to localhost only, by design

`docker-compose.yml` publishes both Postgres (`5432`) and the app (`8000`,
API and web UI together) on `127.0.0.1` only -- not reachable from another
machine on your network, let alone the internet, without something in front
of it. Put your own reverse proxy (nginx, Caddy, Traefik, whatever you
already run for other self-hosted services) in front of it for anything
that needs to be reachable outside the host it runs on, and terminate TLS
there rather than in the backend itself -- the backend has no TLS support
of its own to configure.

## CORS

`DINATOS_CORS_ALLOWED_ORIGINS` (see
[Configuration reference](configuration.md)) defaults to `["*"]` -- any
origin can call the API from a browser. This is safe specifically because
authentication is a bearer token sent in a header, never a cookie: there's
no ambient session for a third-party site to ride along on, which is the
actual risk a wildcard origin usually creates. It doesn't affect the bundled
web UI at all (same origin as the API by construction, so the browser never
treats it as cross-origin); it only matters for a Flutter *web* build served
from a different origin than the backend (see [Clients](clients.md)) --
native clients (Android, Linux) never go through a browser and aren't
affected by this setting either way. Lock it down to a specific list of
origins if you'd rather not rely on that reasoning -- if you only ever use
the bundled UI, that list can be empty.

## API keys and the MCP endpoint

The server hosts an MCP endpoint at `/mcp` (see
[Using it from an LLM harness](../user-guide/mcp-server.md)) that accepts only
**API keys** (`Authorization: Bearer dnk_...`), which people create under
Settings > API keys. A key is a long-lived credential for that person's data, so
treat it like a password: it is shown once at creation and only a hash is stored,
but anyone who holds the plaintext can act as its owner (except for managing keys
and administering the server, which need a real login). Two consequences for your
reverse proxy:

- **Serve it over HTTPS.** Over plain `http://` the key crosses the network in the
  clear, exactly as a password would.
- **Pass the `Authorization` header through**, and don't buffer or cache `/mcp`
  responses. The endpoint is stateless -- no sticky sessions are needed -- so it
  works behind a load balancer as it is.

If you don't want the endpoint reachable from outside your network, block `/mcp`
at the proxy; nothing else in Dinatos depends on it.

## The insecure-TLS client toggle

If you terminate TLS with a self-signed certificate (no public CA), a
client app can't verify it and will refuse to connect. Rather than asking
everyone connecting to install a CA certificate on every device, each
client has an opt-in **"allow insecure connections"**-style toggle next to
the Server URL field that skips certificate verification for that specific
server -- see
[The insecure-TLS toggle](../architecture/frontend.md#the-insecure-tls-toggle)
for exactly how it's wired up, and tell whoever uses your instance whether
they need it. It's off by default and only affects Android/Linux clients
(the web client can't touch a browser's TLS handling at all); using a
proper CA-issued certificate (e.g. via Let's Encrypt, if your instance is
internet-reachable) avoids needing it in the first place.
