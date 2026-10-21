# Architecture

## Timer

Both `IntervalTimer` (iPhone) and `WatchIntervalTimer` (watch) model one infinite loop of `work + rest` seconds. State is **derived from wall-clock deadlines**, not by counting ticks: a 50–100 ms `Timer` only reads `phaseEnd.timeIntervalSinceNow`, so a late tick never causes drift. If several phases elapsed while the app was suspended, `tick()` advances through all of them.

The loop position is expressed as `elapsed` seconds since the loop began. `loopPosition(elapsed:work:rest:)` (in `Shared/Connectivity.swift`) turns that into `(isWork, round, remaining)`, and `seek(to:)` applies it.

## Keeping the app running

| Device | Mechanism |
|---|---|
| iPhone | `UIBackgroundModes: audio`. `Cues` plays a silent looping buffer through an `AVAudioSession` (`.playback`, `.mixWithOthers`) so the app is not suspended. No audible sound. |
| Watch | `WKExtendedRuntimeSession` (background mode `physical-therapy`), about an hour at most. |

## Cues

- **Watch, foreground:** `Haptics` plays multi-pulse `WKInterfaceDevice` patterns: four pulses for work, three heavy pulses for rest, one tap per second for the last 3 s.
- **Watch, background:** `WKInterfaceDevice` haptics are dropped once the app is not frontmost, so `scheduleCues()` queues local notifications for the next 30 phase changes plus 3-2-1 ticks for the nearest 6 (about 48 of the 64 allowed). It rebuilds the queue on every phase change and clears it on pause/stop. In the foreground, `willPresent` returns no presentation so cues are not doubled.
- **iPhone:** haptics only while foregrounded (a platform limit). The Live Activity carries the countdown when locked.

## Live Activity

`HollyWidgets` is a widget extension. The app pushes a `WorkoutActivityAttributes.ContentState` (`isWork`, `round`, `phaseEnd`, `isPaused`, `secondsLeft`) at each phase change, pause and resume. The countdown text uses `Text(timerInterval:countsDown:)` so the system ticks it without updates. `staleDate` is `phaseEnd + 3 s`; if the app dies the card goes stale and shows "Stopped". Leftover activities are ended at the next launch. The `.small` supplemental family is the watch Smart Stack layout.

## Sync (`Shared/Connectivity.swift`)

WatchConnectivity carries one command type, `SyncCommand`: `kind` (`run`, `pause`, `stop`), `work`, `rest`, `elapsed`, plus `sentAt` and `stamp`.

- **Transport:** `sendMessage` when reachable (instant), and always `updateApplicationContext` so a device that is not running reads the latest state when it wakes. `reconcile()` re-reads it whenever an app returns to the foreground.
- **No shared clock.** The two devices' clocks can differ by seconds, so positions are relative:
  - `pause`/`stop` carry the exact `elapsed`.
  - `run` carries `elapsed` at send time. A live message is aged by the receiver's own stopwatch since arrival (`receivedAt`), which also covers the watch's slow startup. A context delivered later falls back to `sentAt` for ageing.
- **Ordering:** `stamp` is a Lamport-style counter: a sender stamps above everything it has seen (`max(now, lastSeen + 1 ms)`), and a receiver ignores any stamp not newer than its last. The last stamp is persisted so an old saved context cannot override a more recent local action.
- **No echo:** commands applied from the other device are not re-broadcast.
- **Persistence:** `LoopStore` saves `{running, epoch | elapsed, work, rest}` to `UserDefaults` on every change; each app restores it on launch and then reconciles against the other device's latest context. A `run` older than two hours is discarded.

## Why no HealthKit

An earlier version used `HKWorkoutSession` to keep the watch app alive and log workouts. It was removed by request, which also removed heart rate, Fitness logging, and the iPhone's ability to launch the watch app.

## Project file

`WorkoutTimer.xcodeproj/project.pbxproj` was written by hand (no XcodeGen/Tuist), so new source files must be added to the right targets in Xcode. `PulseView.swift` and `Connectivity.swift` belong to both app targets; `WorkoutActivityAttributes.swift` to the iPhone app and the widget.
