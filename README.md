# Contact Book

Contacts-style app (Android). See `AI_CONTEXT.md` for the full technical context and
`CHANGELOG.md` for versions.

## Build the APK
1. Upload everything in this folder to the GitHub repo (keep `.github/`, `src/`, `versions/`).
2. Actions tab > "Build Android APK" runs on push (or Run workflow).
3. Download artifact `contact-book-vX.Y.Z` > install `ContactBook-vX.Y.Z.apk`
   (allow unknown apps). Allow the Contacts permission on first launch.

## Use
Open a contact > Call. After the delay set in Settings (default 1 min) the same contact
calls you back. Answer to open the call screen; hold the phone to your ear and the screen
turns off. Keep the app open with the screen on while waiting.
