# Importing from Hevy

If you've been tracking workouts in [Hevy](https://www.hevyapp.com/), you
can bring that history into Dinatos as a one-time import.

## From the app

1. In Hevy: **Settings -> Export**, to get two CSV files (workouts and
   measurements).
2. In Dinatos: **Profile -> Import from Hevy**, and upload each CSV in turn.

This is a one-shot migration, not an ongoing sync -- it doesn't watch Hevy
for new workouts, and there's no way to "re-sync." Uploading the exact same
file a second time is caught and asks you to confirm before re-importing,
rather than silently creating duplicate activities: you'll see a dialog
naming when the earlier import ran and what file it used. Confirming
re-imports it anyway; a good reason to do that is exporting from Hevy again
after logging more workouts there, where a *different* file (even one new
workout added) is not treated as a duplicate and imports normally.

Hevy's export carries no equipment or muscle information. Exercises that
match one of Dinatos's built-in ones are reused; any other is created as your
own custom exercise, and we try to fill in its equipment and muscle groups
automatically from similar built-in exercises. Some of those guesses may be
wrong, so when the import finishes the screen lists the new exercises --
tap one to review and edit it.

> **Note:** the import matches files by their exact content, not their
> filename -- Hevy names every export the same thing, so Dinatos can't tell
> two exports apart by name alone.

See [Hevy import](../architecture/backend.md#hevy-import) for exactly how
the CSV gets parsed into activities and exercises, if you're curious.

## Scripting it instead

If you're setting up a fresh instance and would rather not click through
the app, the same two endpoints work directly once you have a bearer token
(see [Running and testing](../development/workflow.md#creating-an-account-for-testing)
for getting one):

```bash
curl -F file=@workout_data.csv http://127.0.0.1:8000/imports/hevy/workouts \
    -H "Authorization: Bearer $token"
curl -F file=@measurement_data.csv http://127.0.0.1:8000/imports/hevy/measurements \
    -H "Authorization: Bearer $token"
```

Re-uploading the same file content is rejected with `409 Conflict`; add
`?force=true` to the URL to import it again anyway.
