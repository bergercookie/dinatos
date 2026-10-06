# Using it from an LLM harness (MCP)

Dinatos has a built-in [MCP](https://modelcontextprotocol.io/) server. Point an
MCP client (Claude, or any other that takes a URL) at your Dinatos server and it
can add exercises, build routine templates, log activities and read your
[persona statistics](#what-it-can-do), all without leaving the chat. There is
**nothing to install**: the server is part of Dinatos, at `/mcp`.

## 1. Create an API key

An MCP client **must be configured with an API key** -- not your email and
password, and not a login token. A key can be revoked on its own without
changing your password or logging you out anywhere, and it cannot manage keys,
log out or administer the server.

In the app: **Settings > API keys > Create key**. Give it a name (say, "Claude on
my laptop") so you can tell your keys apart later, then copy the key straight
away. **It is shown once and never again** -- afterwards only the name and the
last three characters (`dnk_…abc`) are kept, and a lost key cannot be
recovered: delete it and create another.

Delete a key in the same screen to cut that client off immediately.

## 2. Point your client at the server

The address is your Dinatos server's, plus `/mcp`, and the key goes in an
`Authorization: Bearer` header. For Claude Code:

```bash
claude mcp add --transport http dinatos https://dinatos.example.com/mcp \
    --header "Authorization: Bearer dnk_your-key-here"
```

Any client that supports a remote ("streamable HTTP") MCP server takes the same
two things: the URL and that header. Use `https://` for anything beyond your
own machine -- the key is a credential, and a plain `http://` URL sends it in
the clear (see [Security and networking](../deploy/security-and-networking.md)).

### Clients that can only run a local program

Some clients (Claude Desktop's config file, for one) can only launch a command.
For those, `mcp_server/` is a small stdio server that forwards to the one
above -- it has no tools of its own, so it always offers exactly what your
server does:

```bash
cd mcp_server && just install   # once, to create its virtualenv
```

```json
{
  "mcpServers": {
    "dinatos": {
      "command": "uv",
      "args": ["run", "--project", "/path/to/dinatos/mcp_server", "dinatos-mcp"],
      "env": {
        "DINATOS_MCP_BASE_URL": "https://dinatos.example.com",
        "DINATOS_MCP_API_KEY": "dnk_your-key-here"
      }
    }
  }
}
```

`DINATOS_MCP_BASE_URL` is the address you open in a browser (default
`http://127.0.0.1:8000`); `DINATOS_MCP_API_KEY` is the only credential it
takes. The old `DINATOS_MCP_TOKEN`, `DINATOS_MCP_EMAIL` and
`DINATOS_MCP_PASSWORD` settings no longer exist.

## What it can do

- **`list_exercises`** / **`create_exercise`** -- browse or add to the
  shared exercise catalog.
- **`list_routines`** / **`create_routine`** -- saved routine templates:
  a name plus a prescribed list of exercises and target sets.
- **`list_activities`** / **`log_activity`** -- logged sessions: what was
  actually done, and when, optionally against one of your own routine
  templates. Sets you log count as done unless you pass `completed: false`.
- **`get_persona_stats`** -- the Personas page as data: how closely your body
  (from your measurements and profile height) and your training (the sets you
  completed over the last `month`, `quarter` -- the default -- `year`, or `all`
  time) match each athlete persona, with a 0-100 score per persona, the
  numbers behind it, your best matches, and which measurements to log to
  sharpen the result.

Every tool acts as the owner of the key and can do only what that person can in
the app. Ask your client to look up an exercise's id with `list_exercises`
before referencing it from `create_routine` or `log_activity` -- there's no
lookup-by-name on those two, the same as the REST API itself.
