# AI_CONTEXT.md — read this first

Purpose: hand this project to another AI/developer so they can improve it safely.

## What the app is
"Contact Book" (Android only, Flutter). It looks like a normal contacts app but is a
**fake-call / escape-a-situation tool**:
1. Lists the phone's contacts.
2. User opens a contact and taps Call -> fake outgoing call screen (~7 s, then "Call ended").
3. After a delay (default 60 s) the same contact "calls back": ringtone + vibration + incoming call UI.
4. Answer -> in-call screen with timer; screen turns off when phone is at the ear
   (proximity sensor). Decline / 30 s timeout -> back to the contact list.
The app name/icon are deliberately neutral (not suspicious). Keep it that way.

## Owner's workflow (important constraints)
- The owner has NO local dev environment. Everything is built by GitHub Actions
  (`.github/workflows/build.yml`) and the APK is downloaded from the run's Artifacts.
- Therefore code is NOT compile-tested locally. Make small, careful changes and keep the
  workflow's error-printing step ("Show the real error") intact. If a build fails, the owner
  pastes the "What went wrong" log back to the AI.
- The `android/` folder is NOT in the repo. CI generates it with `flutter create` and then
  applies our files. Never expect `android/` to exist in the repo.

## Repo layout
```
.github/workflows/build.yml   CI: generate android project, apply files, build, upload APK
src/main.dart                 ALL Dart/UI code (single file, state machine)
src/pubspec.yaml              dependencies + app version (single source of truth for version)
src/android/MainActivity.kt   native bridge (contacts query, runtime permission, proximity lock)
src/icons/mipmap-*/           launcher icons copied over the generated ones
versions/vX.Y.Z/              snapshots of older releases (for rollback)
CHANGELOG.md                  release notes
AI_CONTEXT.md                 this file
```

## How the CI build works (build.yml)
1. Flutter pinned to **3.27.4** (Kotlin 1.8 / AGP 8.1 template). Do not use "latest".
2. `flutter create --platforms=android --org com.example --project-name contact_book /tmp/gen`
   -> package `com.example.contact_book`; `android/` copied into the repo workspace.
3. Copies `src/pubspec.yaml` -> `pubspec.yaml`, `src/main.dart` -> `lib/main.dart`.
4. Overwrites generated `MainActivity.kt` with `src/android/MainActivity.kt`
   (first line `package ...` is replaced with the generated one).
5. Copies launcher icons. `sed`-edits AndroidManifest.xml: adds VIBRATE, WAKE_LOCK,
   READ_CONTACTS and sets `android:label="Contact Book"`.
6. `flutter build apk --release`; APK renamed `ContactBook-v<version>.apk` and uploaded.

## Dependencies and known pitfalls
- `flutter_ringtone_player` (ringtone), `vibration` (pattern vibration), `wakelock_plus`
  (keep screen on).
- `wakelock_plus` is pinned to 1.2.8 and `package_info_plus` forced to 8.0.2 via
  `dependency_overrides`: newer versions need Kotlin 2.x and fail with
  "Class 'kotlin.Unit' was compiled with an incompatible version of Kotlin".
- Contacts and proximity are done with our own Kotlin MethodChannel
  (`contact_book/native`) instead of plugins, to avoid Kotlin/AGP/namespace plugin breakage.
  Methods: `hasContactsPermission`, `requestContactsPermission`, `getContacts`,
  `setProximityScreenOff({on: bool})`.
- Before adding any plugin, check it works with Kotlin 1.8 / AGP 8.1 (or raise the Kotlin
  version in the generated `android/settings.gradle` via sed in the workflow).

## App architecture (src/main.dart)
- One `HomePage` StatefulWidget with `enum Stage { list, detail, outgoing, ringing, inCall }`.
- `_callbackAt` (DateTime?) holds the scheduled call-back time; a 1 s `Timer.periodic`
  (`_ticker`) triggers `_startRinging()` when it passes (only while on list/detail).
- `_startCall` -> outgoing screen -> schedules callback. `_answer` starts call timer and
  proximity screen-off. `_endCall` / `_decline` return to list and release locks.
- `WakelockPlus` is kept enabled while a callback is pending or a call screen is shown
  (`_syncWakelock`).
- Contact = {name, number}; sorted A-Z with letter headers; search filters name/number.

## Known limitations / good next steps
1. **Callback only works while the app is open with the screen on** (Dart timer + wakelock).
   Next: Android foreground service or AlarmManager exact alarm + full-screen-intent
   notification so it rings from background/lock screen (needs POST_NOTIFICATIONS,
   USE_FULL_SCREEN_INTENT, SCHEDULE_EXACT_ALARM; implement natively in Kotlin).
2. Mute/Speaker/Keypad are visual only (no real audio).
3. Ringtone is the system default; no custom ringtone, no fake voice/audio playback.
4. Manually added contacts are not persisted (in-memory only).
5. Settings only has the call-back delay; per-contact delay/ringtone could be added.
6. Possible: contact photos, call history list, favorites, Material 3 polish.

## Rules for future changes
- Bump `version:` in `src/pubspec.yaml` (e.g. 1.2.0+3), add a `CHANGELOG.md` entry, and copy
  the previous `src/main.dart`, `src/pubspec.yaml`, `src/android/MainActivity.kt` and workflow
  into `versions/v<old>/` before big changes.
- Keep answers short and give full replacement files (owner uploads files via GitHub mobile/web).
- Do not make the UI/branding say "fake" or "escape" anywhere visible to others.
