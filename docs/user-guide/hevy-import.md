# Importing from Hevy

You can import your workouts and measurements from [Hevy](https://www.hevyapp.com/) one time. This is not a sync. To get new Hevy workouts, you must import again.

## Steps

1. In Hevy, open **Settings -> Export**. Hevy gives you two CSV files: one for workouts and one for measurements.
2. In Dinatos, open **Settings -> Import from Hevy**.
3. Upload each CSV file, one after the other.
4. When the import ends, look at the list of new exercises. See [Exercises](#exercises).

## Duplicates

Dinatos recognizes a file by its content, not by its name. Hevy gives the same name to every export.

- If you upload the identical file again, a dialog shows the date of the earlier import. If you confirm, Dinatos imports the file again and makes duplicate activities.
- If the file is different, Dinatos imports it normally. This is true even if the file has only one new workout.
- To bring in later workouts, export from Hevy again. Then import the new file.

## Exercises

Hevy exports have no data about equipment or muscles.

- If an exercise matches a built-in exercise, Dinatos uses the built-in exercise.
- For all other exercises, Dinatos makes custom exercises for you. Dinatos guesses the equipment and muscles from similar built-in exercises. Some guesses are wrong. To correct an exercise, tap it in the list after the import.

Do you also use Intervals.icu? See [Importing from Intervals.icu](intervals-import.md). That import can skip activities that you already imported from Hevy.

## Use the command line

You can import with the command line, for example on a new instance. You need a login token from `POST /auth/login`. See [Running and testing](../development/workflow.md).

```bash
curl -F file=@workout_data.csv http://127.0.0.1:8000/imports/hevy/workouts \
    -H "Authorization: Bearer $token"
curl -F file=@measurement_data.csv http://127.0.0.1:8000/imports/hevy/measurements \
    -H "Authorization: Bearer $token"
```

If you send a file again, the server returns `409 Conflict`. To import the file anyway, add `?force=true` to the URL.
