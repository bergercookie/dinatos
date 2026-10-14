# Importing from Hevy

One-time import of your workouts and measurements from [Hevy](https://www.hevyapp.com/). It is not a sync: new Hevy workouts need a new import.

## Steps

1. In Hevy, open **Settings -> Export**. You get two CSV files: workouts and measurements.
2. In Dinatos, open **Settings -> Import from Hevy**.
3. Upload each CSV in turn.
4. When the import finishes, review the list of new exercises (see below).

## Duplicates

Dinatos recognises a file by its content, not its name. Hevy names every export the same.

- Uploading the identical file again shows a dialog with the earlier import's date. Confirm to import it anyway, which creates duplicate activities.
- A different file, even one with a single new workout, imports normally.
- To pick up new workouts, export from Hevy again and import the new file. Expect the older workouts to appear twice.

## Exercises

Hevy exports carry no equipment or muscle data.

- Exercises matching a built-in one are reused.
- Others are created as your own custom exercises. Dinatos guesses equipment and muscles from similar built-in exercises. Some guesses will be wrong. Tap an exercise in the post-import list to fix it.

Also use Intervals.icu? See [Importing from Intervals.icu](intervals-import.md). It can skip activities already imported from Hevy.

## Scripting it

Use this for a fresh instance if you prefer the command line. You need a login token from `POST /auth/login` (see [Running and testing](../development/workflow.md)).

```bash
curl -F file=@workout_data.csv http://127.0.0.1:8000/imports/hevy/workouts \
    -H "Authorization: Bearer $token"
curl -F file=@measurement_data.csv http://127.0.0.1:8000/imports/hevy/measurements \
    -H "Authorization: Bearer $token"
```

A repeated file returns `409 Conflict`. Add `?force=true` to the URL to import it anyway.
