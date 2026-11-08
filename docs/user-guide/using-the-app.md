# Using the app

This page shows how to browse exercises, build routines, log and plan workouts, and track progress and body measurements. [Concepts](concepts.md) explains the terms.

The bottom bar has five tabs: **Exercises**, **Routines**, **Home**, **Body** and **Settings**. On a wide screen, the bar is at the side.

Your routines, activities and measurements are private to your account. No other user of the instance sees them. All users share the exercises.

## Exercises

1. Open the **Exercises** tab.
2. Tap an exercise to see its tutorial, if it has one.
3. To filter the list, use the **All**, **Built-in** and **Custom** chips next to the search box. The exercise picker has the same chips.
4. To add a missing exercise, use the add button. Everyone on the instance can then use it.

You cannot change a built-in exercise. Add a custom exercise instead. You can edit or delete your own custom exercises.

## Build a routine

1. Open **Routines** and add a routine.
2. Enter a name.
3. Add exercises. For each exercise, set the target sets, reps and weight.
4. Save the routine.

When you save, the app replaces the whole routine. To change one set, edit the routine and save it again.

To make a superset, open the **⋮** menu on an exercise. Choose **Superset with next exercise**. Repeat this step to add more exercises to the superset. The app outlines the exercises of a superset and labels them A, B and so on. The same menu moves an exercise or removes it from its superset.

To start a workout from a routine, tap the **play** button of the routine. If a workout is already running, choose to resume it or discard it.

### Add a routine to your home screen (Android)

In the Android app, you can put a shortcut to a routine on your home screen. When you tap the shortcut, Dinatos opens and starts a workout from that routine at once.

1. Open **Routines** and open the routine.
2. Tap **Add to home screen** at the top of the screen.
3. Confirm in the prompt that Android shows.

> [!NOTE]
> Android launchers differ. If your launcher cannot add shortcuts, the app tells you.

Adding the same routine again updates its shortcut. It does not make a copy. The shortcut uses the name that the routine had when you added it. To change the label, add the shortcut again.

If you are not signed in, the app asks you to sign in first and then starts the workout. If a workout is already running, the app asks you to resume it or discard it, as for the **play** button. If you deleted the routine, the app tells you that it no longer exists. Remove the old shortcut from your home screen yourself.

This option is not in the web app or the Linux app. They have no home-screen shortcuts.

## Log an activity

Press **Start activity**. Then choose one of these options:

- **From a routine:** The app copies the exercises and targets of the routine. This copy is a one-time copy. If you edit the routine later, the logged activities do not change.
- **From scratch:** You build the workout as you go.
- **Planned workout:** The option appears on the day that you scheduled the workout. See [Plan workouts](#plan-workouts).

### During a workout

- **Last time:** Each exercise shows what you did before, and a suggestion. If every set reached its reps, the suggestion adds weight. Otherwise, it aims for the reps of your best set. Press **Use** to put the suggestion in the empty sets.
- **Tick a set** when you finish it. Only ticked sets count for totals, records, statistics and suggestions.
- **Set type:** Tap the letter next to the set number to change the type. The types are **W** (warm-up), **N** (normal), **D** (drop set) and **F** (failure).
- **Trophy:** A ticked set gets a trophy if it has more weight than your best weight for that exercise. A body-weight set (no weight) gets a trophy if it has more reps than your best reps. Warm-up sets never get a trophy.
- **Set menu (⋮):** Open the plate calculator or remove the set. The plate calculator shows which plates to put on each side of the bar. The default bar weight is 20 kg. You can change it.
- **Exercise menu (⋮):** Add a note or open the progress page of the exercise.
- **Exercise name:** Tap the name to open the page of the exercise. The page shows your records, a progress chart and your recent sessions. The play button in the top bar opens the instructions and the video tutorial.
- **Collapse:** Tap the arrow next to an exercise name to show the exercise on one line. Tap the arrow again to expand it.

To save the workout, press **Finish workout**. The app removes unticked sets and exercises that have no ticked set. If the app must remove anything, it tells you and asks you to confirm. To go back to the workout, press **Keep logging**.

If you did not start the workout from a saved routine, the summary shows **Also save as a routine**. Tick it to keep the workout for later. The app then makes a routine with the same title as the workout. Each ticked set becomes a set in the routine. The weight, reps, distance and duration of the set become suggestions. The app makes the routine right after it saves the workout. If this step fails, the app still keeps the workout. A **Retry saving as routine** button then appears.

### Without a connection

The app keeps your workout on the device while you log it. If **Save workout** cannot reach the server, the app tells you and keeps the workout. A banner on every tab takes you back to the workout. Try again when you have a connection. After a failed attempt, the app locks the title. This prevents a double save when you try again.

## Plan workouts

1. On **Home**, tap **Schedule** in the *Upcoming* card. Or tap a day on the calendar and choose **Schedule workout**.
2. Choose a routine. For a free-form session, choose no routine.
3. Set the day, time, duration and reminder. You can also add notes.
4. Save the planned workout.

A dot shows each day that has a pending workout. To see future months, page forward.

- **Reminders (Android):** By default, a notification arrives 30 minutes before the workout. Tap the notification to start the workout. Allow notifications when the app asks. While the phone is idle, a reminder can arrive a few minutes late.
- **On the day:** **Start activity** offers **Planned workout**. If you planned more than one workout, the app asks which one to start.
- **Done:** When you save a workout that you started from a plan, the app marks the plan as done. A plan does not count for statistics or streaks until you do the workout.
- An AI assistant that connects through [MCP](mcp-server.md) can also manage planned workouts.

### Show your calendar in another app

1. Open **Settings -> Calendar feed** and create the link.
2. In your calendar app, subscribe to the link by URL. In Google Calendar, use "From URL". In Apple Calendar, use "New Calendar Subscription". Outlook also supports this.

Your planned workouts appear as events with reminders. Calendar apps check for changes about once each hour. Google Calendar can take a few hours.

> [!WARNING]
> Anyone who has the link can see your planned workouts. Do not share the link. If the link leaks, choose **Create a new link**. The old link then stops working. You can also choose **Turn the feed off**.

## Progress

Tap the chart icon next to an exercise. The icon is in **Exercises**. In a workout menu, the option is **View progress**. The page shows these items over time:

- the estimated one-rep maximum
- the heaviest set
- the volume of each session
- the most reps in a session
- a suggestion for the next session
- a note if your best result is a few sessions old

The note suggests a lighter week, a different rep range, or more rest.

## Body measurements

The **Body** tab stores measurements with a date. They are separate from workouts. All fields are optional. An entry holds only what you measured that day.

| Section | Fields |
|---|---|
| Body composition | Weight, body fat %, muscle mass, bone mass, water %, BMI, visceral fat, DCI (daily calorie intake, in kcal), metabolic age |
| Segmental analysis | Fat % and muscle mass (in kg) for each arm, each leg and the trunk |
| Tape measurements | Neck, shoulders, chest, biceps, forearms, abdomen, waist, hips, thighs, calves |

The app stores the values as you type them. It does not calculate or check them.

## Settings

| Option | What it does |
|---|---|
| Server URL | Changes the instance that the app uses. |
| Allow self-signed certificates | Turns off certificate checks for this server. Only in the Android and Linux apps. |
| Preferences, Appearance | Sets units, height, and the Light, Dark or System theme. |
| WorkoutX API key | Optional. Your own [WorkoutX](https://workoutxapp.com) key for animated tutorials. Without a key, the app shows built-in exercise images. |
| Import and export | Opens a page for all data transfer. It has **Import from Hevy** ([Hevy import](hevy-import.md)), **Import from Intervals.icu** ([Intervals.icu import](intervals-import.md)), **Import my data** and **Export my data** ([Exporting and importing your data](data-export.md)). |
| Calendar feed | See [Show your calendar in another app](#show-your-calendar-in-another-app). |
| API keys | Keys for [MCP](mcp-server.md) and other tools. |
| API documentation | The REST API of the server, for scripts. Press the tile to see two choices: **Swagger UI**, where you can try the API, and **ReDoc**, a read-only view. Each opens in a browser tab. |
| Take the tour again | Shows the first-run tour again. |
| About | Shows the server version, the app version and commit, and checks for updates. |
| Administration | Only for administrators. Adds users, turns self-registration and the MCP server on or off, and backs up or restores the server. If the operator set `DINATOS_ALLOW_REGISTRATION` or `DINATOS_MCP_ENABLED`, that switch is locked. |
