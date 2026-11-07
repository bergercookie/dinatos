# Using Dinatos from an AI assistant (MCP)

An MCP client is a tool that lets an AI assistant use other services. Claude is an example. This page shows how to connect an MCP client to Dinatos. The assistant can then manage exercises, routines, activities and planned workouts. It can also read your persona statistics.

You do not need to install anything. The MCP server is part of the app, at `/mcp`. It is on by default. An administrator of your instance can turn it off in **Settings -> Administration**. In this case, `/mcp` answers 404 and these steps do not work.

## 1. Create an API key

An MCP client needs an **API key**. Do not give it your password or a login token. You can revoke an API key alone. An API key cannot manage keys, log out or administer the server.

1. Open **Settings -> API keys -> Create key**.
2. Enter a name for the key, for example "Claude on my laptop".
3. Copy the key immediately.

> [!WARNING]
> The app shows the key only once. You cannot recover it later. After this step, the app shows only the name and the last three characters (`dnk_…abc`).

To stop a client from using Dinatos, delete its key on the same screen.

## 2. Connect your client

Use the address of your instance plus `/mcp`. Send the key in an `Authorization: Bearer` header. For Claude Code, use this command:

```bash
claude mcp add --transport http dinatos https://dinatos.example.com/mcp \
    --header "Authorization: Bearer dnk_your-key-here"
```

Other clients that support a remote ("streamable HTTP") MCP server need the same URL and header. Use `https://` for all connections except those on your own machine. The `http://` protocol sends the key without encryption.

### Clients that can only run a local program

Some clients can only start a command. Claude Desktop, with its config file, is an example. The `mcp_server/` folder of the Dinatos repository has a small adapter for these clients. The adapter sends requests to the server. It offers the same tools.

1. Clone the repository.
2. Run `cd mcp_server && just install` one time.
3. Add this text to the config of the client:

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
| `DINATOS_MCP_BASE_URL` | The address that you open in a browser, for example `https://dinatos.example.com` | None (required) |
| `DINATOS_MCP_API_KEY` | Your API key | None (required) |

## Tools

| Tool | Purpose |
|---|---|
| `list_exercises`, `create_exercise` | Browse the shared exercise catalog, or add to it. |
| `list_routines`, `create_routine` | Work with saved routines. A routine has a name, exercises and target sets. |
| `list_activities`, `log_activity` | Work with logged workouts. A workout can be for one of your routines. The tool counts logged sets as done, unless you pass `completed: false`. |
| `list_planned_workouts`, `schedule_workout`, `update_planned_workout`, `delete_planned_workout` | Manage your training calendar. `scheduled_at` needs a timezone offset. `reminder_minutes` is 30 by default. Use `null` for no reminder. |
| `get_persona_stats` | Get the Personas page as data. It gives a score from 0 to 100 for each athlete persona. The score uses your measurements, the height in your profile, and your completed sets over `month`, `quarter` (default), `year` or `all`. It also gives your best matches and the measurements to add. |

Every tool acts as the owner of the key. A tool can do only what that person can do in the app.

The tools `create_routine` and `log_activity` take exercise IDs, not names. Ask the assistant to find an exercise with `list_exercises` first.
