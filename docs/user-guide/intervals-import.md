# Importing from Intervals.icu

You can import chosen activities from [Intervals.icu](https://intervals.icu) one time. Dinatos reads the activities with your API key and shows a list. Dinatos imports the activities that you tick. This is not a sync.

## Steps

1. In Intervals.icu, open **Settings -> Developer Settings**. Create or copy your **API key**.
2. In Dinatos, open **Settings -> Import and export -> Import from Intervals.icu**.
3. Paste the API key.
4. Leave **Athlete ID** at `0`. This value means the owner of the key. To use an account that you have access to, enter the ID of that account, for example `i12345`.
5. Choose the **From** date. The range ends today.
6. Press **Fetch activities**.
7. Tick the activities that you want.
8. Press **Import**.

Dinatos uses your API key only for these two requests. Dinatos never stores the key. It is not in your profile, a backup or a log.

## Avoid duplicates

Hevy can sync workouts to Intervals.icu. A session can then exist in both places. The list leaves these activities **unticked**:

| Label | Meaning |
|---|---|
| **Possible duplicate of "..."** | One of your Dinatos activities, often from Hevy, started within 30 minutes. |
| **Already imported** | You imported the activity from Intervals.icu before. |
| No import possible | Strava activities arrive from Intervals.icu as empty stubs. |

If a possible duplicate is a different session, you can tick it. The **All** and **None** buttons change the whole selection.

## Import again

It is safe to import again. Date ranges that overlap do not make copies by accident.

- If your selection has an activity that you already imported, Dinatos asks "Already imported -- import again anyway?". If you confirm, Dinatos imports everything that you selected. This makes second copies of the activities that you already imported.
- If you delete an imported activity in Dinatos, you can import it again.
- **Clear all account data** and **Replace my data** also reset the list of imported activities.
- New Intervals.icu activities show as new in the next list.

## What you get

Each Intervals.icu activity becomes one Dinatos activity:

| Dinatos field | Source |
|---|---|
| Title, description | Name and description of the activity |
| Start time | Local start time shown in Intervals.icu |
| End time | Start time plus elapsed time |
| Exercise | Named after the sport. `Run` becomes Running, `Ride` becomes Cycling, and `WeightTraining` becomes Weight Training. |
| Set | One set with the moving time and, if present, the distance |

If no exercise matches the sport, Dinatos makes a custom exercise. If one exists, Dinatos uses it.

Intervals.icu records no sets for strength sessions. These sessions arrive as one timed "Weight Training" entry. Log strength sessions in Hevy. Do not import them from Intervals.icu.

Dinatos counts imported cardio as **endurance** training on the Personas page. One set-equivalent is about 3 minutes. If the activity has no time, Dinatos uses the distance. Dinatos classifies a timed strength entry in the same way.
