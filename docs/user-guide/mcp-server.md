# Using Dinatos from an AI assistant (MCP)

Connect an MCP client (a tool that lets an AI assistant use other services, such as Claude) to Dinatos. The assistant can then manage exercises, routines, activities and planned workouts, and read your persona statistics. Nothing to install: the MCP server is built in at `/mcp`.

## 1. Create an API key

MCP clients need an **API key**, not your password or a login token. A key can be revoked alone and cannot manage keys, log out or administer the server.

1. Open **Settings -> API keys -> Create key**.
2. Name it, for example "Claude on my laptop".
3. Copy the key immediately. It is shown once and cannot be recovered. Afterwards only the name and last three characters (`dnk_…abc`) are shown.

To cut a client off, delete its key on the same screen.

## 2. Connect your client

Use your instance address plus `/mcp`, and send the key in an `Authorization: Bearer` header. For Claude Code:

```bash
claude mcp add --transport http dinatos https://dinatos.example.com/mcp \
    --header "Authorization: Bearer dnk_your-key-here"
```

Any client that supports a remote ("streamable HTTP") MCP server needs the same URL and header. Use `https://` for anything beyond your own machine: plain `http://` sends the key unencrypted.

### Clients that can only run a local program

Some clients, such as Claude Desktop's config file, can only launch a command. The `mcp_server/` folder of the Dinatos repository is a small adapter for these. It forwards to the server and offers the same tools.

1. Clone the repository and run `cd mcp_server && just install` once.
2. Add this to the client's config:

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

| Variable | Meaning | Default |
|---|---|---|
| `DINATOS_MCP_BASE_URL` | Address you open in a browser | `http://127.0.0.1:8000` |
| `DINATOS_MCP_API_KEY` | Your API key | none (required) |

## Tools

| Tool | Purpose |
|---|---|
| `list_exercises`, `create_exercise` | Browse or add to the shared exercise catalog. |
| `list_routines`, `create_routine` | Saved routines: a name plus exercises and target sets. |
| `list_activities`, `log_activity` | Logged workouts, optionally against one of your routines. Logged sets count as done unless you pass `completed: false`. |
| `list_planned_workouts`, `schedule_workout`, `update_planned_workout`, `delete_planned_workout` | Your training calendar. `scheduled_at` needs a timezone offset. `reminder_minutes` defaults to 30 (`null` for none). |
| `get_persona_stats` | The Personas page as data: a 0-100 score per athlete persona from your measurements, profile height and completed sets over `month`, `quarter` (default), `year` or `all`, plus your best matches and which measurements to add. |

Every tool acts as the key's owner and can do only what that person can do in the app.

`create_routine` and `log_activity` take exercise ids, not names. Ask the assistant to look an exercise up with `list_exercises` first.
