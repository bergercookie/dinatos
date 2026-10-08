# Exporting and importing your data

**Settings -> Data -> Export my data** saves a JSON file with your own
settings (height, units), routines, activities, body measurements, and the
exercises they use. It never includes your password or your WorkoutX API key,
and never anyone else's data.

**Import my data** loads such a file into your account (the same server or
another one). You choose how:

- **Merge** (the default) adds what is missing and leaves everything you
  already have alone. A routine counts as already there if you have one with
  the same name, an activity if the title and start time match, a measurement
  if the date and time match -- so importing the same file twice does not
  create duplicates.
- **Replace my data** first deletes *all* your routines, activities and body
  measurements, then imports the file. Use it to make an account match a file
  exactly.

To start over entirely, turn on **Advanced** in Settings and use **Clear all
account data**. It deletes your activities, routines, body measurements, Hevy and
Intervals.icu import history and any custom exercises nobody else uses, and keeps your
settings and account. It cannot be undone.

Exercises are shared by everyone on a server: an exercise in the file is matched
to the one with the same name; if there is none, it is created as a custom
exercise. Your settings in the file are applied in both modes.

A file that is not a Dinatos export, or is internally inconsistent, is rejected
with a message and nothing is changed.

Administrators additionally have a whole-server backup, see
[Upgrades and backups](../deploy/upgrades-and-backups.md).
