# FloorSense Flutter Client

An unofficial Flutter client for accessing FloorSense locker services with an existing account.

This repository contains independently maintained client code. It is not affiliated with, endorsed by, or supported by FloorSense or Smartalock.

## Features

- Password and SSO/OIDC sign-in
- Site selection
- Locker availability and reservations
- Locker unlock/release actions
- Session restoration and reconnect handling
- Android background refresh and notifications

## Requirements

- Flutter 3.47 or newer
- A valid FloorSense account
- Android, iOS, Linux, macOS, Windows, or web tooling as required by Flutter

## Development

```bash
cd app
flutter pub get
flutter analyze
flutter test
flutter run
```

The Android Gradle wrapper is committed so a clean clone has the normal Android build tooling.

## Credentials

Do not commit real credentials, tokens, site identifiers, or captured API responses.

The optional Python smoke client reads `credentials.json`, which is ignored by Git. Start from `credentials.example.json` and keep the populated file local.

## Protocol notes

The client interoperates with the public-facing service used by the official application. High-level implementation notes are in [docs/PROTOCOL.md](docs/PROTOCOL.md). Security-sensitive bypass instructions and extracted proprietary application material are intentionally not distributed in this repository.

## Security

See [SECURITY.md](SECURITY.md) for reporting guidance. Do not open public issues containing credentials, tokens, reservation PINs, private site information, or vulnerability details that could enable unauthorized physical access.

## License

Original code in this repository is licensed under the MIT License. See [LICENSE](LICENSE).

Third-party services, trademarks, APIs, and applications remain the property of their respective owners.
