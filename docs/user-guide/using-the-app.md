# Using the app

## Exercises

Browse the shared exercise catalog from the Exercises tab. Tap an exercise
to see its tutorial -- a picture or animated GIF, instructions, target
muscles, and equipment, where available. If you don't see one you need,
add it -- it's immediately available to every account on the instance, not
just yours.

Exercises marked "Built-in" are the catalog Dinatos ships with and can't be
renamed, edited, or deleted -- if one doesn't fit, add your own custom
exercise instead. Anything you add yourself you can edit or delete freely.

## Building a routine

A routine is a reusable plan: give it a name, add exercises, and set a
target number of sets/reps/weight for each. Saving replaces the whole thing
as one unit -- there's no way to edit a single set within a saved routine
without re-saving the routine itself.

Tap the **play** button on a routine in the Routines list to start a live
workout pre-filled from it (its exercises and target sets, to adjust as you
go). If a workout is already in progress you're asked whether to resume it or
discard it for the routine.

## Logging an activity

An activity is what you actually did in the gym. Two ways to start one:

- **From a saved routine** -- pick one, and its exercises and target
  weights/reps are copied in as a starting point; adjust anything as you go
  (add a set, change the weight, skip an exercise entirely). This is a
  one-time copy, not a live link back to the routine -- editing the routine
  template later doesn't change activities already logged from it.
- **From scratch** -- build an ephemeral one on the spot for a session that
  doesn't match any saved plan.

Saving an activity, like a routine, replaces the whole thing at once.

## Measurements

Track body measurements (weight, and whatever else you choose) separately
from routines (the **Body** tab), each with its own date. Useful for watching
trends independent of any single gym session.

## Profile

Your account-level settings: change your Server URL, log out (ends the
session on the server, see [Getting started](getting-started.md#staying-signed-in)),
[import your history from Hevy](hevy-import.md), and open **"API
documentation"** (Swagger UI) or **"API reference"** (ReDoc) -- the
backend's own API reference, each opening in a new browser tab, useful if
you're scripting something against your instance rather than using the app.
**About** shows the software version (plus, in the installed apps -- `.deb`, AppImage, APK -- the app's own version) and the commit it was built from.
