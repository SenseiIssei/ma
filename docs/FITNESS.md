# Fitness goal and the Garmin feed

The fitness goal lives in the Balance tab. You enter your weight and a goal weight. Ma then works out how much sport a week gets you there, plans the rest of the week and gives you experience points for every workout.

## The math

- A kilo of body fat holds about 7,700 kcal. For a pace of `p` kg a week without changing what you eat, you need to burn `p × 7,700` kcal a week on top of what you already do.
- "What you already do" (the baseline) is the average workout calories of the four whole weeks before you start. If your weight was steady then, that amount keeps it steady. You can change the baseline on the goal screen.
- Weekly target = baseline + extra. The plan splits whatever is still missing this week into sessions of about 500 kcal. Your favourite activities take turns, you get one rest day when four or more days are left, and no session is longer than two hours.
- Minutes per session come from your own sessions once the feed has two of the same kind that are at least ten minutes long. Until then Ma uses MET values from the Compendium of Physical Activities for your weight (`MET × 3.5 × kg / 200` kcal a minute).
- Weight is smoothed: each weigh-in moves the trend a third of the way towards the new value.
- Food is deliberately not part of the plan yet.

## Experience, levels, quests

| Source | XP |
|---|---|
| Workout | calories / 10 + minutes / 2 (at least 5) |
| Steps | 3 per 1,000 steps a day (up to 30,000), +15 when the watch's step goal is met |
| Weigh-in | 10 (one a day) |
| Weekly quests | 150 for the weekly burn, 75 for the planned number of sessions, 50 for the rotating one |

To reach level `L` you need `50 × L × (L − 1)` XP: 100 for level 2, 300 for level 3, 1,000 for level 5, 4,500 for level 10. XP is always worked out again from your data, so removing a workout also removes its points. Workouts from before the goal count too, which is why you may start above level 1.

## The feed

Ma reads any `https` URL that returns this JSON. Every field is optional:

```json
{
  "latest": {
    "date": "2026-09-29",
    "steps": 4568,
    "stepGoal": 5770,
    "activeCalories": 466,
    "moderateIntensityMinutes": 40,
    "vigorousIntensityMinutes": 5
  },
  "activity": [ { "date": "2026-09-28", "steps": 8123 } ],
  "workouts": [
    { "id": "24544002914", "type": "strength training", "date": "2026-09-29",
      "minutes": 77, "km": null, "calories": 415, "averageHeartRate": 124 }
  ]
}
```

That is the shape of the Garmin snapshot senseiissei.dev publishes at `/api/public/garmin`, filled every five minutes by a sync script (python-garminconnect). `activity` is an optional list of earlier days for feeds that keep a history. Without it, Ma collects one day each time it syncs. Ma fetches the feed when the app comes to the front, at most every five minutes, and when you pull to refresh. Workouts you remove stay hidden, even after the next sync.

Everything stays on the phone in the App Group container (`fitness-*.json`). Ma sends nothing anywhere; it only reads the feed.
