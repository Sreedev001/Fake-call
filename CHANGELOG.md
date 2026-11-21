# Changelog

Version format: `MAJOR.MINOR.PATCH+BUILD` in `src/pubspec.yaml`.
Old source snapshots live in `versions/vX.Y.Z/` (restore by copying back to `src/`).

## 1.1.1+3
- Fix: "Allow access" button did nothing after the permission was denied twice. It now
  re-asks, and if Android blocks the dialog it opens the app's Settings page; contacts load
  automatically when you return.
- Fix: call screens only filled the left ~third of the screen; they are now full width.

## 1.1.0+2
- Renamed app to "Contact Book" (was "Fake Call"), new neutral blue contacts icon.
- Reads the phone's real contacts (native Kotlin bridge, READ_CONTACTS) and shows them
  like a contacts app: search, A-Z headers, colored avatars, contact detail page.
- Manual "add contact" button (in-memory) as a fallback.
- Calling a contact shows an outgoing call, then the SAME contact calls back after a
  delay (default 60 s, configurable in Settings: 15 s / 30 s / 1 / 2 / 5 min).
- Answer / Decline work; incoming call auto-misses after 30 s.
- After answering, the in-call screen appears and the screen turns off when the phone
  is held to the ear (proximity wake lock). Mute / Speaker toggles are visual only.
- APK artifact is now named with the version (ContactBook-vX.Y.Z.apk).

## 1.0.0+1
- First working build: manual caller name/number + delay, ringtone, vibration,
  incoming and in-call screens.
- Fixed CI failure by pinning Flutter 3.27.4 and wakelock_plus 1.2.8 with
  package_info_plus 8.0.2 (newer one needs Kotlin 2.x).
- Source snapshot: `versions/v1.0.0/` (note: its workflow uses the old project name).
