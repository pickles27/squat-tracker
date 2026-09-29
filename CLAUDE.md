# Squat Tracker

Native SwiftUI iPhone app (iOS 17+) for running barbell programs — currently Jim Wendler's
5/3/1 for Beginners (squat, bench, deadlift; no overhead press). Product spec and progress: `PLAN.md`.

## Commands

```sh
# Core logic tests (models, program engine, scheduling, streaks, sync merge, export, OAuth helpers)
swift test

# Build the app (use a DerivedData path inside the repo; `.build/` is gitignored)
xcodebuild -project Squats.xcodeproj -scheme Squats \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/DerivedData build -quiet
```

Always pass `-project Squats.xcodeproj` (the repo root also has `Package.swift`).

## Layout

- `Squats/Core/` — platform-independent logic, compiled into the app **and** into the `SquatsCore`
  Swift package for `swift test`. No SwiftUI/UIKit imports here. Any behavior change needs tests in
  `SquatsCoreTests/`.
  - `Store/WorkoutStore.swift` — the single source of truth (`@MainActor @Observable`). Every read
    and write goes through it; views never mutate models directly. Persisted as one JSON file per
    account and synced as a whole (`Sync/SyncMerge.swift`: newest `updatedAt` wins, tombstones for deletes).
  - `Engine/` — data-driven `ProgramTemplate`; `FiveThreeOneBeginners` builds the built-in template;
    `ProgramEngine` turns a program + session index into a `SessionPrescription`.
- `Squats/App/` — app entry, root/tab views, `SessionCoordinator` (focused/expanded workout),
  `Route` navigation, `Theme` (appearance, `Color.appBackground`/`.cardBackground`, `.card()`,
  `ProgramPalette`, `DisplayStatus` colors).
- `Squats/Shared/` — small views used across features (`WorkoutRow`, `StatusBadge`, `FlameView`).
- `Squats/Auth/`, `Squats/Sync/` — Google sign-in (OAuth + PKCE) and Google Drive appDataFolder sync.
- `Squats/Features/<Area>/` — screens.

The Xcode project uses a synchronized folder: any file added under `Squats/` is compiled automatically
(no project file edits needed).

## Conventions

- Swift 5 language mode, SwiftUI only, no third-party dependencies.
- Models are value types; get fresh values from the store each render (`store.workout(id)`), and
  pass IDs (not copies) between views.
- Environment objects: `WorkoutStore`, `SyncManager`, `SessionCoordinator`, `AuthManager`.
- Every set is **expected vs actual**: expected comes from the program (or last time, for accessories);
  the user can always change the actual weight and reps.
- Must look right in light and dark mode: use semantic colors and the `Theme` helpers, never hard-coded
  black/white backgrounds. Icon-only buttons need accessibility labels.
- Only offer "Start early" for a program's *next* planned workout (`store.nextWorkout(programID:)`).
