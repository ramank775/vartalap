# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Vartalap is an open-source personal messaging app built with Flutter, structured as a modular monorepo. The v3 migration is in progress — goal is to encapsulate all offline-first logic in `packages/vartalap_messaging_flutter/` so the UI layer can be swapped. Web platform is **not supported** (SQLite FFI limitation).

The chat server lives at `../chat-server` (microservice architecture with nginx gateway). Client uses v3.0 API paths; nginx strips version prefixes and routes to backend services.

## Build & Run Commands

```bash
flutter pub get                                          # Install dependencies
flutter run --dart-define MOCK_MODE=true                 # Mock mode (no server/Firebase needed)
./scripts/dev.sh                                         # Run with local server
flutter analyze                                          # Static analysis
flutter test                                             # Run all tests
flutter test test/utils/chat_message_helper_test.dart     # Run a single test
./scripts/build-prod.sh                                  # Production APK
```

VS Code: press F5 to use preconfigured launch configs in `.vscode/launch.json` (Mock Mode is the default).

## Architecture

```
UI (lib/screens/, lib/widgets/)
  └─ Provider<VartalapChatClientFlutter> (from main.dart)
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

- **`packages/vartalap_messaging/`** — Core server client, models, API definitions (pure Dart, no Flutter dependency)
- **`packages/vartalap_messaging_flutter/`** — Flutter offline-first wrapper: Drift database, DAOs, repositories, auth, entity-to-model mappers, task queue integration. All business logic should live here.
- **`packages/taskq/`** — Dependency-aware task queue for reliable message delivery
- **`packages/vartalap_testing/`** — Mock client and scenario engine for offline development and testing

### Key patterns

- **Client access**: `context.read<VartalapChatClientFlutter>()` via Provider package
- **Client creation**: Shared factory in `lib/config/client_factory.dart` (used by both app and background tasks)
- **Database access**: Always through DAO classes, never direct table queries
- **Configuration**: Build-time via `--dart-define` flags (`API_URL`, `WS_URL`, `API_KEY`, `MOCK_MODE`), managed in `lib/config/app_config.dart`
- **Mock mode**: Dependency injection at app boundary (`client_factory.dart`) swaps real implementations for mocks; rest of app is unaware. Mock OTP code is `123456`.
- **Two build variants needed**: Play Store (with Firebase) and open source (without Google dependencies). Interfaces like `IOTPProvider` exist to support this.

### Database

Drift ORM with SQLite. Schema defined in `packages/vartalap_messaging_flutter/lib/db/chat_db.dart`. Tables: Channels, Messages, Contacts, Members, Assets, MessageAssets, UserProfiles, Tasks, TaskDependencies.

## Platform targets

- **Android**: Primary release target (Kotlin 2.1.0, Java 17, product flavors: `dev`/`prod`)
- **Linux Desktop**: Supported
- **iOS**: Supported (requires Xcode)
