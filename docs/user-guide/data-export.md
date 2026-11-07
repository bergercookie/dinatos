# Exporting and importing your data

You can save your own data to a file and load it into any Dinatos account. You can also delete all the data of your account. Use these functions to move between instances or to keep a personal backup.

## Export

1. Open **Settings -> Import and export -> Export my data**.
2. Save the JSON file.

The file holds your settings (height and units), routines, activities, body measurements, planned workouts, and the exercises that they use. The file never contains your password, your WorkoutX API key, or the data of other users.

## Import

1. Open **Settings -> Import and export -> Import my data**.
2. Choose a file that you exported from Dinatos.
3. Choose a mode.
4. Confirm.

| Mode | Effect |
|---|---|
| **Merge** (default) | Adds the items that are missing. Keeps all your existing items. If you import the same file twice, the app makes no duplicates. |
| **Replace my data** | First deletes **all** your routines, activities and body measurements. Then imports the file. |

In Merge mode, the app treats an item as already present when it matches an existing item as follows:

| Item | Match on |
|---|---|
| Routine | Same name |
| Activity | Same title and start time |
| Measurement | Same date and time |
| Planned workout | Same title and time |

All users of an instance share the exercises. The app matches each exercise in the file by name. If no exercise matches, the app makes a custom exercise. The settings in the file apply in both modes.

If the file is not a Dinatos export, or the data in it is not consistent, the app rejects the file. Nothing changes.

## Clear all account data

> [!WARNING]
> This action deletes your data. You cannot undo it.

1. In **Settings**, turn on **Advanced**.
2. Choose **Clear all account data**.
3. Confirm.

The app deletes your activities, routines, body measurements, planned workouts and import history. It also deletes the custom exercises that no other user uses. It keeps your settings and your account.

## Server backups

Administrators can back up the whole server. See [Upgrades and backups](../deploy/upgrades-and-backups.md).
