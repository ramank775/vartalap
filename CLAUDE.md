# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Vartalap is an open-source Flutter chat application structured as a modular monorepo. Web platform is **not supported** (SQLite FFI limitation).

## Build & Run Commands

```bash
# Install dependencies
flutter pub get

# Run in mock mode (no server/Firebase needed — best for UI dev)
flutter run --dart-define MOCK_MODE=true

# Run with local server
./scripts/dev.sh

# Static analysis
flutter analyze

# Run all tests
flutter test

# Run a single test file
flutter test test/utils/chat_message_helper_test.dart

# Build production APK
./scripts/build-prod.sh
```

VS Code: press F5 to use preconfigured launch configs in `.vscode/launch.json` (Mock Mode is the default).

## Architecture

```
UI (lib/screens/, lib/widgets/)
  └─ VartalapClientManager (Provider)
       └─ VartalapChatClientFlutter (packages/vartalap_messaging_flutter/)
            ├─ DAOs → Drift/SQLite database
            ├─ Event system
            └─ TaskQ scheduler (packages/taskq/)
                 └─ VartalapChatClient (packages/vartalap_messaging/)
                      ├─ HTTP (Dio)
                      └─ WebSocket
```

**Local-first**: all operations work offline; background tasks handle sync to server.

### Package breakdown

- **`packages/vartalap_messaging/`** — Core messaging client, models, API definitions (pure Dart, no Flutter dependency)
- **`packages/vartalap_messaging_flutter/`** — Flutter-specific: Drift database, DAOs, repositories, auth, entity-to-model mappers, task queue integration
- **`packages/taskq/`** — Dependency-aware task queue for reliable message delivery
- **`packages/vartalap_testing/`** — Mock client and scenario engine for offline development and testing

### Key patterns

- **State management**: Provider pattern + Inherited Widgets (`VartalapClientProvider`, `CurrentUser`)
- **Database access**: Always through DAO classes, never direct table queries
- **Configuration**: Build-time via `--dart-define` flags (`API_URL`, `WS_URL`, `API_KEY`, `MOCK_MODE`), managed in `lib/config/app_config.dart`
- **Mock mode**: Dependency injection at app boundary (`main.dart`) swaps real implementations for mocks; rest of app is unaware. Mock OTP code is `123456`.
- **Internal packages**: Use `path` dependencies in `pubspec.yaml`

### Database

Drift ORM with SQLite. Schema defined in `packages/vartalap_messaging_flutter/lib/db/chat_db.dart`. Tables: Channels, Messages, Contacts, Members, Assets, MessageAssets, UserProfiles, Tasks, TaskDependencies.

## Platform targets

- **Android**: Primary release target (Kotlin 2.1.0, Java 17, product flavors: `dev`/`prod`)
- **Linux Desktop**: Supported
- **iOS**: Supported (requires Xcode)
