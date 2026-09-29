# Squat Tracker — plan

Agreed with the product owner on 2026-09-28. Checked items are done and on `main`.

## Program: 5/3/1 for Beginners (built-in)

Source: thefitness.wiki "5/3/1 for Beginners" (+ "5/3/1 Primer" for the TM test).

- Lifts: squat, bench press, deadlift. **No overhead press** (the user does accessories instead).
- Exactly **3 days a week**; the user picks which 3 weekdays (multi-select, starts with none selected,
  must pick exactly 3).
  - Day 1: Squat, then Bench · Day 2: Deadlift · Day 3: Bench, then Squat.
  - Every workout in a week uses that week's percentages.
- Starting training max (TM): work up to a set of 3–5 good reps → estimated 1RM
  (weight × reps × 0.0333 + weight) → TM = 90%. Known 1RM or TM can be entered directly too.
- Optional warm-up: 40%×5, 50%×5, 60%×3.
- 3-week cycles (% of TM; last main set is AMRAP), each followed by 5×5 First Set Last at the first set's %:
  - Week 1: 65×5, 75×5, 85×5+ · Week 2: 70×3, 80×3, 90×3+ · Week 3: 75×5, 85×3, 95×1+
- After each cycle: TM +5 kg / +10 lb (squat, deadlift), +2.5 kg / +5 lb (bench), regardless of AMRAP reps.
- TM test week (on by default) every 10th week: 70%×5, 80%×5, 90%×3, 100%×3–5.
  Pass (≥3 reps) → keep TM; fail → offer TM reset to 90% of the e1RM from that set.
- Stalling: missing the rep target on every AMRAP set of a lift for a whole cycle → offer TM −3 increments.
- Rounding: nearest 2.5 kg / 5 lb, exact halves round down (matches the article's worked example).
- No deload week (outdated per the primer).

## Programs in general

- Programs are the top level: settings, lifts/TMs, schedule, history, future workouts. Multiple at once.
- Program types define allowed days per week (exact or range). Built-ins now; **custom program builder
  comes last** (same data-driven `ProgramTemplate` format). Smolov is *not* planned yet.

## Schedule

- Calendar auto-filled ~12 weeks ahead on the chosen weekdays.
- Today card (Home and program screen): **Start** and **Rest another day**.
  - Rest another day: workout moves to tomorrow; toggle "also push back all following workouts".
  - No workout today: "Rest day" + **Start early** on the next workout; toggle "also move following
    workouts earlier".
- Move any future workout to another date; option to shift all following workouts by the same number
  of days (backward or forward). Whole-program shift ±N days.
- Nothing auto-snaps back to particular weekdays; after a shift the new weekdays stick. Changing the
  workout days re-plans upcoming workouts onto them.
- Skipping drops the day; the program continues from the same step.

## Streak (animated flame)

- Counts planned workouts completed in a row.
- A workout breaks it if not done or moved by the end of the day after it was scheduled (one grace day).
- Skipping by the end of the scheduled day does **not** break it; skipping later does.

## Workout mode

- Full-screen, simplified, big buttons; minimize to a bar above the tabs; several workouts can be in
  progress at once (one focused).
- Every set shows expected vs actual; actual weight and reps are editable. Plate calculator, rest timer
  (article: 1.5–3 min), summary at the end (AMRAP result, e1RM, PRs, new TMs, TM suggestions).
- Accessories: not programmed. Add/remove during a workout; per-set weight and reps; expected = last time.
  Exercise library (built-in Push/Pull/Single-Leg-Core lists + your own; add/remove/restore).
  Quick add shows your most-used exercises.

## Account, sync, export

- Sign in with Google (OAuth + PKCE, no backend). Local account for development.
- Data backed up and synced to the hidden app folder in the user's Google Drive (`drive.appdata` scope);
  offline-first; newest change wins; deletions propagate.
- Export all data as CSV (one row per set) or JSON; optionally include planned workouts.
- Light/dark mode (System / Light / Dark setting).

## Build order / checklist

- [x] Core: models, data-driven engine, 5/3/1 for Beginners, scheduling (move/shift/rest/start early),
      streaks, exercise library, sync merge, export, OAuth helpers — with tests
- [x] Xcode project + app shell (tabs, navigation, theme, session coordinator, placeholders)
- [ ] Auth & Sync: Google sign-in, Keychain, Drive appDataFolder sync, sync status, setup guide
- [ ] Home & Programs: streak flame, today card, program setup, program detail, workout detail, reschedule
- [ ] Workout mode: expected vs actual sets, accessories + quick add, plate calc, rest timer, summary, mini bar
- [ ] Calendar & Settings: month calendar, exercise library, export, appearance, 5/3/1 guide
- [ ] Integration pass: merge, build, run on simulator, fix
- [ ] Custom program builder
