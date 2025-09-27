# VartalapMessagingFlutter Architecture

## Overview
Local-first messaging core built with Drift database and event-driven architecture. Provides instant UI updates with background server synchronization.

## Architecture Layers

```
┌─────────────────────────────────────────────────────────────┐
│                        UI Layer                             │
│  - Flutter Widgets                                         │
│  - Device Contacts (flutter_contacts)                      │
│  - User Interactions & Permissions                         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Client Layer                            │
│  - VartalapChatClientFlutter (main client)                 │
│  - ChatClient (per-channel operations)                     │
│  - Business logic & orchestration                          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     DAO Layer                              │
│  - ChatDao (messages, members)                             │
│  - ChannelDao (channels, contacts)                         │
│  - Pure database operations                                │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  Database Layer                            │
│  - Drift ORM                                               │
│  - SQLite storage                                          │
│  - Reactive queries                                        │
└─────────────────────────────────────────────────────────────┘
```

## Core Principles

### 1. Local-First Architecture
- **Instant Updates**: All operations update local database immediately
- **Optimistic UI**: UI shows changes before server confirmation
- **Offline Support**: App works completely offline
- **Background Sync**: Server synchronization happens asynchronously

### 2. Clean Architecture
- **Separation of Concerns**: Each layer has specific responsibilities
- **Dependency Inversion**: Lower layers don't know about upper layers
- **Interface Segregation**: Clean, focused interfaces
- **Single Responsibility**: Each class has one clear purpose

### 3. Data Flow
```
UI Input → Client Logic → DAO Operations → Database Storage
Database Changes → Reactive Streams → UI Updates
```

## Key Components

### VartalapChatClientFlutter
**Purpose**: Main client for application-level operations
**Responsibilities**:
- Channel management (create, update, delete)
- Contact synchronization
- User profile management
- Database initialization

**Key Methods**:
```dart
Future<ChannelModel> createChannel(ChannelModel, List<Member>)
Future<void> syncContacts(List<Contact> contacts)
Selectable<Contact> getContacts({ContactFilter?})
Future<ChatClient> chat({required ChannelModel, required Contact})
```

### ChatClient
**Purpose**: Per-channel operations
**Responsibilities**:
- Message operations (send, edit, delete)
- Read status management
- Member management
- Channel-specific streams

**Key Methods**:
```dart
Future<void> sendMessage(List<ChatMessage>)
Future<void> editMessage(int messageId, String newText)
Future<void> markAsRead({int? messageId})
Stream<List<ChatMessage>> get messagesStream
```

### ChatDao
**Purpose**: Message and member database operations
**Key Methods**:
```dart
Future<int> sendMessage(ChatMessage, ChannelModel)
Future<void> updateMessage(int messageId, ChatMessage)
Future<void> markMessagesAsRead(List<int> messageIds)
Selectable<ChatPreview> getChatPreviews({ChannelFilter?})
```

### ChannelDao
**Purpose**: Channel and contact database operations
**Key Methods**:
```dart
Future<ChannelModel> createChannel(ChannelModel, List<Member>)
Future<void> syncContacts(List<Contact>)
Selectable<ChannelModel> getChannels({ChannelFilter?})
```

## Message State Flow
```
pending → sent → delivered → read
```

## Development Guidelines

### ✅ DO
- Use DAO pattern for all database operations
- Provide reactive streams for UI binding
- Make operations local-first with instant feedback
- Use transactions for multi-table operations
- Document interfaces with clear examples
- Pass external data as parameters (no hardcoding)

### ❌ DON'T
- Add direct database operations to Client classes
- Hardcode data in business logic layers
- Mix UI concerns with data layer
- Block UI waiting for server responses
- Add permission-level dependencies to core packages

## Testing Strategy
- **Unit Tests**: Test DAO operations with in-memory database
- **Integration Tests**: Test complete workflows through Client layer
- **Mock Data**: Use dependency injection for testable interfaces

## Future Enhancements
- Server synchronization with conflict resolution
- End-to-end encryption
- File/media upload with progress tracking
- Push notification integration
- Advanced search and filtering

## File Structure
```
lib/
├── client/           # Business logic layer
│   ├── client.dart   # Main client
│   └── chat.dart     # Per-chat client
├── dao/              # Data access layer
│   ├── chat_dao.dart # Message operations
│   └── channel_dao.dart # Channel operations
├── models/           # Data models
├── entity/           # Database entities
└── db/               # Database setup
```