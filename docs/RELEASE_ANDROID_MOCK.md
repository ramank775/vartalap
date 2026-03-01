# Android Mock Mode Release Checklist

This checklist targets the current release goal: **Android + Mock Mode** (offline, no server required).

## Build/Run Commands
```bash
# Run on an Android device/emulator
flutter run -d android --dart-define MOCK_MODE=true
```

## Smoke Test (Must Pass)
1. App launches without Firebase/network errors
2. Login flow works with any phone number
3. OTP verification succeeds with `123456`
4. Chat list renders sample chats
5. Open a chat and send a message (message appears in UI)
6. App restarts without crashing

## Pre-Release Checks
1. `flutter analyze` is clean
2. `flutter test` (core tests) passes
3. `README.md` and `docs/LOCAL_DEVELOPMENT.md` reflect mock mode instructions

## Out of Scope for This Release
1. Production server connectivity
2. API key provisioning
3. iOS release readiness
