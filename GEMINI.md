# Gemini Context: Vartalap Chat Application

## Project Overview
Vartalap is an open-source personal chat application built with Flutter. It emphasizes transparency and user control over data. The project is structured as a modular monorepo, separating core messaging logic from Flutter-specific implementations and the main UI application.

### Key Technologies
- **Frontend**: Flutter (v3.0.0+)
- **Core Messaging**: Custom `vartalap_messaging` package (platform-agnostic)
- **Persistence**: SQLite with **Drift ORM** (via `vartalap_messaging_flutter`)
- **Real-time**: WebSockets
- **Authentication**: Unified Auth Client (migrating to decouple from Firebase)
- **OTP Delivery**: Firebase Auth (Primary provider)
- **Services**: Firebase Messaging (Push), Performance, Crashlytics, App Check
- **State Management**: **Provider** pattern and Inherited Widgets
- **Task Management**: `taskq` (internal package)

### Architecture
- **lib/**: Main Flutter application UI and integration logic.
- **packages/vartalap_messaging/**: Core messaging client, models, and API definitions (pure Dart/Dio).
- **packages/vartalap_messaging_flutter/**: Flutter-specific implementation, including Drift database and secure storage.
- **packages/taskq/**: Internal task queue system for reliable message delivery.

---

## Building and Running

### Prerequisites
- Flutter SDK installed and configured.
- Android Studio / VS Code with Flutter extension.

### Key Commands
- **Install Dependencies**: 
  ```bash
  flutter pub get
  ```
- **Run in Mock Mode (Fastest for UI Dev)**:
  No server or Firebase setup required.
  ```bash
  flutter run --dart-define MOCK_MODE=true
  ```
- **Run Development (Local Server)**:
  Uses the script in `scripts/dev.sh`.
  ```bash
  ./scripts/dev.sh
  ```
- **Build Production APK**:
  ```bash
  ./scripts/build-prod.sh
  ```
- **Static Analysis**:
  ```bash
  flutter analyze
  ```
- **Run Tests**:
  ```bash
  flutter test
  ```

---

## Development Conventions

### Configuration
The app uses `--dart-define` for build-time configuration. Key variables are managed in `lib/config/app_config.dart`:
- `API_URL`: Backend API endpoint.
- `WS_URL`: WebSocket endpoint.
- `API_KEY`: API authentication key.
- `MOCK_MODE`: Boolean flag for offline development.

### Authentication Strategy
The project is currently implementing a **Unified Authentication Architecture** (see `UNIFIED_AUTH_IMPLEMENTATION_PLAN.md`).
- **VartalapAuthenticatedClient**: The single source of truth for auth state.
- **IOTPProvider**: Interface to allow switching OTP providers (currently Firebase).
- Avoid circular dependencies between `AuthService` and `VartalapClient`.

### Platform Support
- **Android**: Fully supported.
- **Linux Desktop**: Supported.
- **iOS**: Supported (requires Xcode).
- **Web**: **Unsupported** due to SQLite FFI limitations.

### Code Quality
- Follow standard Flutter/Dart linting rules (see `analysis_options.yaml`).
- Prefer `const` constructors where possible.
- Use `Provider.of` or `Consumer` for state access.
- All internal packages use `path` dependencies in `pubspec.yaml`.

---

## Key Files & Directories
- `lib/main.dart`: App entry point and auth initialization.
- `lib/config/app_config.dart`: Configuration management.
- `lib/services/vartalap_authenticated_client.dart`: Unified auth logic.
- `PROJECT_STATUS.md`: Detailed technical findings and roadmap.
- `docs/LOCAL_DEVELOPMENT.md`: Detailed guide for mock mode and local setup.

---

## Coordination Notes

Use `docs/AGENT_NOTES.md` as the shared handoff log between agents. Keep notes short, factual, and timestamped with the current date.

Recommended format:
```
## AgentName Notes (YYYY-MM-DD)
- Bullet summary of findings
```
