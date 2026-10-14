# Importing from Intervals.icu

One-time import of chosen activities from [Intervals.icu](https://intervals.icu). Dinatos reads them with your API key, lists them, and imports the ones you tick. It is not a sync.

## Steps

1. In Intervals.icu, open **Settings -> Developer Settings** and create or copy your **API key**.
2. In Dinatos, open **Settings -> Import from Intervals.icu**.
3. Paste the API key.
4. Leave **Athlete ID** at `0` (the key's owner). To use an account you were given access to, enter its ID, such as `i12345`.
5. Choose the **From** date. The range ends today.
6. Press **Fetch activities**.
7. Tick the activities you want and press **Import**.

Your API key is used only for these two requests. It is never stored: not in your profile, a backup or a log.

## Avoiding duplicates

Hevy can sync workouts to Intervals.icu, so a session may exist in both. The list leaves these **unticked**:

| Label | Meaning |
|---|---|
| **Possible duplicate of "..."** | One of your Dinatos activities (often from Hevy) started within 30 minutes. |
| **Already imported** | You imported it from Intervals.icu before. |
| Cannot be imported | Strava activities arrive from Intervals.icu as empty stubs. |

You can still tick a possible duplicate if it is a different session. **All** and **None** change the whole selection.

## Importing again

Imports are safe to repeat. Overlapping date ranges do not create copies by accident.

- If a request includes an already-imported activity, Dinatos asks "Already imported -- import again anyway?". Confirming imports everything selected, creating second copies of those.
- Deleting an imported activity in Dinatos lets you import it again.
- **Clear all account data** and **Replace my data** also reset what counts as imported.
- New Intervals.icu activities show up as new in the next list.

## What you get

Each activity becomes one Dinatos activity:

| Dinatos field | Source |
|---|---|
| Title, description | Activity name, description |
| Start time | Local start time shown in Intervals.icu |
| End time | Start plus elapsed time |
| Exercise | Named after the sport (`Run` becomes Running, `Ride` Cycling, `WeightTraining` Weight Training) |
| Set | One set with moving time and, if present, distance |

A sport with no matching exercise creates a custom exercise. An existing one is reused.

Intervals.icu records no sets for strength sessions, so they arrive as one timed "Weight Training" entry. Log strength in Hevy and leave those out here.

Imported cardio counts as **endurance** training on the Personas page (about one set-equivalent per three minutes, or per distance if there is no time). A timed strength entry is classified the same way.

## Scripting it

Both steps are plain endpoints. The key goes in the request body, so it never appears in a URL or access log. You need a login token (see [Running and testing](../development/workflow.md)).

```bash
# 1. List activities (writes nothing)
curl -X POST http://127.0.0.1:8000/imports/intervals/preview \
    -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
    -d '{"api_key": "'"$INTERVALS_KEY"'", "athlete_id": "0", "oldest": "2026-01-01"}'

# 2. Import the chosen ones
curl -X POST http://127.0.0.1:8000/imports/intervals/activities \
    -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
    -d '{"api_key": "'"$INTERVALS_KEY"'", "oldest": "2026-01-01", "activity_ids": ["i123", "i124"]}'
```

`newest` defaults to today.

| Status | Meaning |
|---|---|
| `409` | Already imported. Nothing written. Add `?force=true` to import anyway. |
| `422` | An id is outside the window or cannot be imported. |
| `400` | Bad API key. |
| `502` | Intervals.icu is unreachable. |
