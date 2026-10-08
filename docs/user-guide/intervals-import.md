# Importing from Intervals.icu

If you track training in [Intervals.icu](https://intervals.icu), you can bring
chosen activities from there into Dinatos as a one-time import. Unlike the
[Hevy import](hevy-import.md) you don't export a file: Dinatos reads your
activities straight from Intervals.icu with your API key, shows you the list,
and imports only the ones you tick.

## From the app

1. In Intervals.icu: **Settings -> Developer Settings**, and create (or copy)
   your **API key**.
2. In Dinatos: **Profile -> Import from Intervals.icu**.
3. Paste the API key. Leave **Athlete ID** at `0` (that means "the owner of
   this key"), unless you want an account you have been given access to --
   then use its ID, e.g. `i12345`. Pick the **From** date -- the range ends
   today -- and press **Fetch activities**.
4. Tick the activities to import. Press **Import**.

Your API key is sent to your Dinatos server only for those two requests (the
fetch and the import), is used to talk to Intervals.icu, and is **never
stored** -- not in your profile, not in a backup, not in a log.

## Not duplicating what Hevy already has

Hevy can sync its workouts to Intervals.icu, so the same session may exist in
both places. To keep you from importing a workout you already have, the list
marks each activity and leaves it **unticked** when:

- **Possible duplicate of "..."** -- one of your Dinatos activities (typically
  one imported from Hevy) started within 30 minutes of it;
- **Already imported** -- you imported it from Intervals.icu before;
- it **can't be imported** -- Intervals.icu doesn't pass on activities that
  came from Strava (only a stub), so there is nothing to import.

Those are suggestions: you can tick a "possible duplicate" yourself if it
really is a different session. **All** and **None** change the whole selection.

## Importing a second time

An activity from Intervals.icu is remembered by its own ID, so importing is
safe to repeat -- overlapping date ranges, or pressing the button again, never
create a second copy by accident:

- the list marks what you already imported, and leaves it unticked;
- if a request still includes one (say you ticked it by hand), Dinatos stops
  and asks, naming what was already imported -- the same *"Already imported --
  import again anyway?"* question as re-uploading a Hevy file. Nothing is
  imported until you confirm, and then everything selected is. Confirming
  creates a second copy of those activities;
- if you **delete** an imported activity in Dinatos, it is no longer
  "already imported" and you can import it again normally;
- **Clear all account data** and **Replace my data** forget what was imported
  too, since the activities are gone.

New activities logged in Intervals.icu since last time simply show up as new
in the next list: there is no ongoing sync, and Dinatos never pulls anything
in by itself.

## What an imported activity looks like

Each Intervals.icu activity becomes one Dinatos activity, with:

- its **name** as the title, and its description (if any) as the description;
- its **start time**, and an end time from its elapsed time. Times are the
  local time Intervals.icu shows (`start_date_local`), stored as the same
  wall-clock time -- exactly as the Hevy import treats times;
- one exercise named after its sport (`Run` -> **Running**, `Ride` ->
  **Cycling**, `WeightTraining` -> **Weight Training**, ...) with one set
  holding its moving time and, if it has one, its distance. A sport with no
  exercise of that name yet gets one created as your own custom exercise
  (tracking duration, and distance when the activity had one); an existing
  exercise of that name is reused.

Imported runs, rides and other cardio count as **endurance** training in the
Personas page (and the MCP `get_persona_stats` tool) like any other completed
set: roughly one set-equivalent per three minutes, or per distance if there is
no time. A timed strength session is classified the same way, so it also reads
as endurance there -- another reason to leave strength sessions to Hevy.

Intervals.icu records no per-exercise sets for strength sessions, so those come
over as a single timed "Weight Training" entry -- if you log strength in Hevy,
leave its duplicates out as described above.

## Scripting it instead

Both steps are plain endpoints; the key goes in the request body (it is a
`POST` so it never ends up in a URL or an access log):

```bash
# 1. list what's there (writes nothing)
curl -X POST http://127.0.0.1:8000/imports/intervals/preview \
    -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
    -d '{"api_key": "'"$INTERVALS_KEY"'", "athlete_id": "0", "oldest": "2026-01-01"}'

# 2. import the ones you chose, from the same window
curl -X POST http://127.0.0.1:8000/imports/intervals/activities \
    -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
    -d '{"api_key": "'"$INTERVALS_KEY"'", "oldest": "2026-01-01", "activity_ids": ["i123", "i124"]}'
```

`newest` defaults to today. Importing something already imported is rejected
with `409 Conflict` (nothing is written); add `?force=true` to import it again
anyway. An id that is not in the window, or can't be imported, is a `422`; a
bad key is a `400`; Intervals.icu being unreachable is a `502`.

See [Intervals.icu import](../architecture/backend.md#intervals-icu-import) for
how it works and why it differs from the Hevy import.
