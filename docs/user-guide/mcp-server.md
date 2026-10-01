# Using it from an LLM harness (MCP server)

`mcp_server/` runs an [MCP](https://modelcontextprotocol.io/) server that
turns a running Dinatos instance into tools an LLM harness (Claude Desktop,
or any other MCP client) can call directly: add a new exercise, create a
saved routine template, or log an activity, all without leaving the chat.

It's a plain client of the same REST API the app itself uses -- see
[MCP server](../architecture/backend.md#mcp-server) if you're curious how
it authenticates.

## Getting a token

The server needs a bearer token for whichever Dinatos account it should act
as. Get one the same way any other script would (see
[Creating an account for testing](../development/workflow.md#creating-an-account-for-testing)
for the full `curl` recipe):

```bash
curl -X POST http://127.0.0.1:8000/auth/login \
    -H "Content-Type: application/json" \
    -d '{"email": "you@example.com", "password": "your-password"}'
```

`access_token` from the response is what goes into `DINATOS_MCP_TOKEN`
below. Alternatively, set `DINATOS_MCP_EMAIL`/`DINATOS_MCP_PASSWORD` instead
and the server logs in for you the first time a tool is called.

## Configuring your harness

```bash
cd mcp_server && just install   # once, to create its virtualenv
```

Point your MCP client at `uv run --project mcp_server dinatos-mcp` (an
absolute path to the repo, if the harness's working directory won't be this
one) with the environment variables below. For Claude Desktop, that's an
entry in `claude_desktop_config.json`'s `mcpServers`:

```json
{
  "mcpServers": {
    "dinatos": {
      "command": "uv",
      "args": ["run", "--project", "/path/to/dinatos/mcp_server", "dinatos-mcp"],
      "env": {
        "DINATOS_MCP_BASE_URL": "http://127.0.0.1:8000",
        "DINATOS_MCP_TOKEN": "the-token-from-above"
      }
    }
  }
}
```

`DINATOS_MCP_BASE_URL` defaults to `http://127.0.0.1:8000` (the same
default `just backend run`/`just dev` serve on), so it only needs setting
for a remote instance.

## What it can do

- **`list_exercises`** / **`create_exercise`** -- browse or add to the
  shared exercise catalog.
- **`list_routines`** / **`create_routine`** -- saved routine templates:
  a name plus a prescribed list of exercises and target sets.
- **`list_activities`** / **`log_activity`** -- logged sessions: what was
  actually done, and when, optionally against one of your own routine
  templates.

Ask your harness to look up an exercise's id with `list_exercises` before
referencing it from `create_routine` or `log_activity` -- there's no
lookup-by-name on those two, the same as the REST API itself.
