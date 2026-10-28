# Holly Workout

A minimal interval timer for iPhone and Apple Watch. It loops **45 seconds of work** and **15 seconds of rest** forever until you stop it, and keeps the two devices in sync.

- iPhone app, Apple Watch app, and a Live Activity (lock screen, Dynamic Island, watch Smart Stack)
- SwiftUI, no third-party dependencies, no HealthKit
- Work/rest lengths are adjustable (5–300 s, in 5 s steps)

> Personal development project, installed straight to devices with a development certificate. It is not on the App Store.

## Features

| | iPhone | Apple Watch |
|---|---|---|
| Infinite work/rest loop | yes | yes |
| Display | pulsing circle, round counter | progress fill behind a large countdown |
| Cues | haptics in the foreground | multi-pulse haptics, plus queued notifications when the app is not frontmost |
| Runs with screen locked / wrist down | yes (silent background audio) | yes (background runtime session + notifications) |
| Live Activity | yes | shown in the Smart Stack |
| Two-way sync of start / pause / stop | yes | yes |

No sounds are played. Cues are haptic only.

## Requirements

- Xcode 27 or later
- iOS 17+ (the Live Activity widget needs iOS 18+), watchOS 10+
- An Apple Developer account for signing

## Build and run

Open the project and run the `WorkoutTimer` scheme on an iPhone. The watch app is embedded and installs through the Watch app on the iPhone.

```sh
open WorkoutTimer.xcodeproj
```

Before building, change the signing team in all three targets (`WorkoutTimer`, `WorkoutTimerWatch`, `HollyWidgets`): set `DEVELOPMENT_TEAM` to your own team ID, and change the bundle identifiers if you need to.

| Target | Bundle ID |
|---|---|
| iPhone app | `com.mfuentesg.hollyworkout` |
| Watch app | `com.mfuentesg.hollyworkout.watchkitapp` |
| Live Activity widget | `com.mfuentesg.hollyworkout.widgets` |

### From the command line

```sh
# iPhone (also builds and embeds the watch app and widget)
xcodebuild -project WorkoutTimer.xcodeproj -scheme WorkoutTimer \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates build

# Install on a connected device
xcrun devicectl device install app --device <iphone-udid> "<path to Holly Workout.app>"

# Watch directly (also registers the watch with your team the first time)
xcodebuild -project WorkoutTimer.xcodeproj -scheme WorkoutTimerWatch \
  -destination 'id=<watch-udid>' -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
xcrun devicectl device install app --device <watch-udid> "<path to HollyWatch.app>"
```

The watch must be unlocked, on your wrist, and have **Developer Mode** enabled (Settings → Privacy & Security). Development installs to a watch can fail with `Connection invalid`; waking the watch and retrying usually works.

## Using it

- **iPhone:** play/pause and reset buttons; work and rest steppers are locked while a session is in progress.
- **Watch:** set work and rest with the − / + buttons, tap **START**. Pause and stop (✕) are at the bottom. The ✕ ends the session; swiping the app away does not.
- On first start the watch asks for **notification** permission. Allow it, otherwise cues will not fire while the wrist is down.
- Enable **Live Activities** for Holly Workout in iPhone Settings if the lock-screen card does not appear.

## Project layout

```
WorkoutTimer/          iPhone app (IntervalTimer, ContentView, Cues)
WorkoutTimerWatch/     watch app (WatchIntervalTimer, WatchContentView)
HollyWidgets/          Live Activity widget extension
Shared/                code compiled into several targets
  Connectivity.swift       WatchConnectivity sync + saved loop state
  PulseView.swift          the pulse animation
  WorkoutActivityAttributes.swift   Live Activity data
docs/ARCHITECTURE.md   how the timer, sync and background behaviour work
```

## Known limitations

- iOS does not allow vibration while an app is in the background or the phone is locked, so the iPhone only shows the countdown there (Live Activity); the watch provides the cues.
- The watch's background runtime session has a time limit of about an hour. After that, queued notifications still deliver the cues.
- A swiped-away iPhone app cannot clean up; its Live Activity goes stale and reads "Stopped".
- Sessions are not saved to Health or Fitness (HealthKit was removed on purpose).
- The two devices only sync when their apps can reach each other; a closed app catches up the next time it wakes or opens.

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): timer model, background behaviour, cues, Live Activity and sync
- [CHANGELOG.md](CHANGELOG.md): release notes
