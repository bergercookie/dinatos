# Using the app

How to browse exercises, build routines, log and plan workouts, and track progress and body measurements. New terms are explained in [Concepts](concepts.md).

The bottom bar (a side bar on wide screens) has five tabs: **Exercises**, **Routines**, **Home**, **Body**, **Settings**.

## Exercises

1. Open the **Exercises** tab and tap an exercise to see its tutorial, where available.
2. Use the **All / Built-in / Custom** chips next to the search box to filter. The same chips appear in the exercise picker.
3. Add a missing exercise with the add button. It becomes available to everyone on the instance.

Built-in exercises cannot be changed. Add a custom one instead. You can edit or delete your own.

## Build a routine

1. Open **Routines** and add a routine.
2. Name it, add exercises, and set target sets, reps and weight for each.
3. Save.

Saving replaces the whole routine. To change one set, edit the routine and save again.

**Supersets:** open the **⋮** menu on an exercise and choose **Superset with next exercise**. Repeat to chain more. Superset exercises are outlined and labelled A, B, and so on. The same menu moves an exercise or removes it from its superset.

**Start a workout from a routine:** tap its **play** button. If a workout is already running, choose to resume it or discard it.

## Log an activity

Press **Start activity** and choose one:

- **From a routine:** copies its exercises and targets. This is a one-time copy. Editing the routine later does not change logged activities.
- **From scratch:** build the workout as you go.
- **Planned workout:** appears on the day you scheduled one. See [Plan workouts](#plan-workouts).

### During a workout

- **Last time:** each exercise shows what you did before and a suggestion. The suggestion adds weight if every set hit its reps, otherwise it aims for your best set's reps. Press **Use** to fill it into empty sets.
- **Tick a set** when done. Only ticked sets count toward totals, records, statistics and suggestions.
- **Set type:** tap the letter beside the set number to cycle **W**armup, **N**ormal, **D**rop set, **F**ailure.
- **Trophy:** a ticked set that beats your all-time best weight for that exercise. Warm-ups never count.
- **Set menu (⋮):** opens the plate calculator (which plates go on each side; the bar defaults to 20 kg and can be changed) or removes the set.
- **Exercise menu (⋮):** add a note or open its progress page.
- **Collapse:** tap an exercise name to shrink it to one line. Tap again to expand.

Press **Finish workout** to save. Unticked sets, and exercises with no ticked set, are removed. If anything would be removed, the app tells you and asks you to confirm. **Keep logging** takes you back.

### Without a connection

Your workout is kept on the device as you go. If **Save workout** cannot reach the server, it says so and keeps the workout. A banner on every tab returns you to it. Retry when online. The title is locked after a failed attempt, so a retry cannot save the workout twice.

## Plan workouts

1. On **Home**, tap **Schedule** in the *Upcoming* card, or tap a day on the calendar and choose **Schedule workout**.
2. Pick a routine (or none for a free-form session), day, time, duration and reminder. Add notes if you like.
3. Save.

Days with a pending workout show a dot. Page forward to see future months.

- **Reminders (Android):** a notification arrives 30 minutes before by default. Tap it to start the workout. Allow notifications when asked. Reminders can arrive a few minutes late while the phone is idle.
- **On the day:** **Start activity** offers **Planned workout**. If several are planned, it asks which.
- **Done:** saving a workout started from a plan marks the plan done. A plan does not count toward stats or streaks until you do the workout.
- An AI assistant connected through [MCP](mcp-server.md) can manage planned workouts too.

### Show your calendar in another app

1. Open **Settings -> Calendar feed** and create the link.
2. Subscribe to it by URL in Google Calendar ("From URL"), Apple Calendar ("New Calendar Subscription") or Outlook.

Your planned workouts appear as events with reminders. Calendar apps re-check about hourly. Google can take several hours.

Anyone with the link can see your planned workouts. Do not share it. If it leaks, choose **Create a new link** (the old one stops working) or **Turn the feed off**.

## Progress

Tap the chart icon next to an exercise (in **Exercises**, or **View progress** in a workout menu). It shows, over time:

- estimated one-rep max
- heaviest set
- volume per session
- most reps per session
- a suggestion for next time
- a note if your best is several sessions old, suggesting a lighter week, a different rep range, or more rest

## Body measurements

The **Body** tab stores dated measurements, separate from workouts. Every field is optional, so an entry holds only what you measured that day.

| Section | Fields |
|---|---|
| Body composition | Weight, body fat %, muscle mass, bone mass, water %, BMI, visceral fat, DCI (daily calorie intake, kcal), metabolic age |
| Segmental analysis | Fat % and muscle mass (kg) for each arm, each leg and the trunk |
| Tape measurements | Neck, shoulders, chest, biceps, forearms, abdomen, waist, hips, thighs, calves |

Values are stored as typed. Nothing is calculated or cross-checked.

## Settings

| Option | What it does |
|---|---|
| Server URL | Change which instance the app uses. |
| Allow self-signed certificates | Skip certificate checks for this server. Android and Linux only. |
| Preferences, Appearance | Units, height, and Light, Dark or System theme. |
| WorkoutX API key | Optional. Your own [WorkoutX](https://workoutxapp.com) key for animated tutorials. Without it, built-in exercise images are used. |
| Import from Hevy / Intervals.icu | See [Hevy import](hevy-import.md) and [Intervals.icu import](intervals-import.md). |
| Export / Import my data | See [Exporting and importing your data](data-export.md). |
| Calendar feed | See [above](#show-your-calendar-in-another-app). |
| API keys | Keys for [MCP](mcp-server.md) and other tools. |
| API documentation, API reference | The server's REST API reference, for scripting. Opens in a browser tab. |
| Take the tour again | Replays the first-run tour. |
| About | Software version, commit, and update check. |
| Administration | Administrators only: add users, back up or restore the server. |
