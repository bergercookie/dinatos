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

Both the Exercises tab and the exercise picker (when adding an exercise to a
routine or workout) have All / Built-in / Custom chips next to the search box,
to find only the catalog's exercises or only the ones you added.

## Building a routine

A routine is a reusable plan: give it a name, add exercises, and set a
target number of sets/reps/weight for each. Saving replaces the whole thing
as one unit -- there's no way to edit a single set within a saved routine
without re-saving the routine itself.

To do two exercises back-to-back, open the **⋮** menu on the first one and
choose **Superset with next exercise** (you can build longer ones the same way).
Supersets are outlined and labelled A, B, ...; the same menu moves an exercise
up or down, or takes it out of its superset.

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

### During a live workout

Each exercise shows what you did **last time** and, once there is something to
build on, a suggestion for this time -- add weight if every set hit its reps,
otherwise aim for the best set's reps on all of them. **Use** fills it into the
sets that are still empty. The weight and reps fields hint at the same set
from last time.

Tap an exercise's name (or the arrow beside it) to **collapse** it to a single
line -- its name and how many sets are done -- and tap again to expand it.
Handy for tucking away finished exercises in a long workout; collapsing hides
nothing from the workout itself, and it resets if you leave and reopen the
screen.

Tick the box at the end of a set when you have done it: its row turns green,
and only ticked sets count -- towards the workout's totals, your records, the
statistics and what the app suggests next time. A set you have not ticked is
treated as not done.

The small letter beside a set's number is its type (**W**armup, **N**ormal,
**D**rop set, **F**ailure); tap it to step to the next one. A trophy appears on a
ticked set that beats your all-time best weight for that exercise (warm-ups
never count). The **⋮** next to a set opens the **plate calculator** -- which
plates to put on each side of the bar for that weight (a 20 kg bar by default;
change it for yours) -- or removes the set. The exercise's own **⋮**
menu adds a note, and opens its **progress** page.

### If you lose your connection

Everything above except the hints works without one, and your workout is kept
on the device as you go. If **Save workout** can't reach the server it says so
and keeps the workout; a banner on every tab brings you back to it. Try again
when you're online -- the title is locked after a failed attempt so a retry
can't save the workout twice.

## Progress

The chart icon next to an exercise (Exercises tab, or **View progress** in its
menu during a workout) shows how it is going over time: estimated one-rep
max, heaviest set, volume or most reps per session, a suggestion for next
time, and a note when your best is several sessions behind -- a nudge to try
a lighter week, a different rep range, or more rest.

## Measurements

Track body measurements (weight, and whatever else you choose) separately
from routines (the **Body** tab), each with its own date. Useful for watching
trends independent of any single gym session.

Every field is optional, so an entry holds only what you measured that day.
The form groups them into three sections:

- **Body composition** -- weight and body fat %, plus what a smart scale
  reports as a whole: muscle mass, bone mass, water %, BMI, visceral fat,
  DCI (daily calorie intake, kcal) and metabolic age.
- **Segmental analysis** -- fat % and muscle mass (kg) of each arm, each leg
  and the trunk, as a smart scale's segmental readout gives them.
- **Tape measurements** -- circumferences: neck, shoulders, chest, biceps,
  forearms, abdomen, waist, hips, thighs and calves.

A weigh-in on a gym scale fills the first two; a tape session only the third.
Values are stored exactly as you type them; nothing is calculated or
cross-checked (BMI, say, is whatever the scale told you).

## Profile

Your account-level settings: change your Server URL, log out (ends the
session on the server, see [Getting started](getting-started.md#staying-signed-in)),
[import your history from Hevy](hevy-import.md) or
[chosen activities from Intervals.icu](intervals-import.md), and open **"API
documentation"** (Swagger UI) or **"API reference"** (ReDoc) -- the
backend's own API reference, each opening in a new browser tab, useful if
you're scripting something against your instance rather than using the app.
**About** shows the software version (plus, in the installed apps -- `.deb`, AppImage, APK -- the app's own version) and the commit it was built from.
