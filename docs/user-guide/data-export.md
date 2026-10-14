# Exporting and importing your data

Save your own data to a file, load it into any Dinatos account, or wipe your account. Use this to move between instances or keep a personal backup.

## Export

1. Open **Settings -> Export my data**.
2. Save the JSON file.

It holds your settings (height, units), routines, activities, body measurements, planned workouts and the exercises they use. It never contains your password, your WorkoutX API key or anyone else's data.

## Import

1. Open **Settings -> Import my data** and choose a file exported from Dinatos.
2. Choose a mode.
3. Confirm.

| Mode | Effect |
|---|---|
| **Merge** (default) | Adds what is missing. Keeps everything you already have. Importing the same file twice creates no duplicates. |
| **Replace my data** | First deletes **all** your routines, activities and body measurements, then imports the file. |

Merge treats these as already present:

| Item | Match on |
|---|---|
| Routine | Same name |
| Activity | Same title and start time |
| Measurement | Same date and time |
| Planned workout | Same title and time |

Exercises are shared across the instance. Each exercise in the file is matched by name. If none matches, a custom exercise is created. Settings in the file apply in both modes.

A file that is not a Dinatos export, or is inconsistent, is rejected and nothing changes.

## Clear all account data

1. In **Settings**, turn on **Advanced**.
2. Choose **Clear all account data** and confirm.

This deletes your activities, routines, body measurements, planned workouts, import history and any custom exercises nobody else uses. It keeps your settings and account. **It cannot be undone.**

## Server backups

Administrators can back up the whole server. See [Upgrades and backups](../deploy/upgrades-and-backups.md).
