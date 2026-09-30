# Android Device Installation

- For physical Android device installs, do not use `flutter run` or `flutter install`.
- Build the APK first, then install or update it with `adb install -r <path-to.apk>` so the existing app data is preserved.
- If `adb install -r` fails because of a signing-key mismatch, version downgrade, or another install error, report the failure and do not uninstall the existing app unless explicitly asked.
