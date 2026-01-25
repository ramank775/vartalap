# Vartalap Testing Strategy

This document outlines the architectural approach for testing the Vartalap monorepo, covering local logic verification and the End-to-End (E2E) simulation framework.

## 1. Core Philosophy: Reactive & Decoupled
Tests must verify that the **UI remains a pure reflection of the Local Database**. 
- **Unidirectional Data Flow**: UI Action -> Logic/Task -> Database -> Reactive Stream -> UI Update.
- **No Mockito for UI**: We prefer **Fake Implementations** (in-memory databases and stateful mock clients) over behavior mocking to ensure data consistency.

---

## 2. Phase 1: Local Sanity Suites (Low Hanging Fruit)
Before the full framework is ready, we focus on high-value unit tests for pure logic:

### A. Data Mappers (`packages/vartalap_messaging_flutter/lib/mapper/`)
Ensures database entities (Drift) correctly map to UI domain models (`ChatMessage`, `ChannelModel`).
- **Goal**: Verify that IDs (`rid`, `cid`), timestamps, and media attachment fields are never lost.

### B. UI Helpers (`lib/utils/chat_message_helper.dart`)
Verifies the complex logic for message grouping, date header insertion, and avatar visibility.
- **Goal**: Prevent regressions in the visual chat flow.

### C. Task Serialization
Verifies that background tasks (`SendMessageTask`, etc.) can be correctly serialized to JSON and reconstructed.
- **Goal**: Ensure reliable message delivery across app restarts.

---

## 3. Phase 2: The "Virtual Server" Framework (`packages/vartalap_testing`)
A dedicated package to simulate a live backend without needing a network.

### A. The Simulator Engine
The `MockVartalapChatClient` acts as a **Virtual Server**. It processes requests and emits events through the `eventStream` based on active "Scripts."

### B. Scenario-Based Testing (`MockScenario`)
Scenarios define how the server reacts to events.
- `StandardScenario`: Automatically handles the `sent -> delivered -> read` lifecycle.
- `FlakyScenario`: Simulates random network timeouts and errors.
- `BotScenario`: Triggers automatic "typing" and "reply" events from specific mock users.

### C. Manual Takeover & Bug Replay
When a bug is found:
1. **Manual Reproduction**: Switch to `ManualScenario` and use the `SimulatorController` to precisely trigger the edge case (e.g., "Inject an incoming message exactly while I'm sending one").
2. **Replay Codification**: Once the bug is reproduced, capture the sequence into a new `BugReplayScenario`.
3. **Automated Fix Verification**: Use the new scenario in a standard Flutter `testWidgets` or `IntegrationTest` to ensure the bug never returns.

---

## 4. Testing Stack
- **Unit Tests**: `flutter_test` for Mappers and Helpers.
- **Widget Tests**: Verifying UI components in isolation with `StandardScenario`.
- **Integration Tests**: Running full E2E flows on real devices/simulators using the `SimulatorController`.

---

## 5. Workflow Implementation Plan
1. [ ] **Local Sanity Suites**: Implement tests for Mappers, UI Helpers, and Task Serialization.
2. [ ] **Testing Package Scaffolding**: Create `packages/vartalap_testing`.
3. [ ] **Migration**: Move `MockVartalapChatClient` to the testing package.
4. [ ] **Scenario Engine**: Implement `MockScenario` base class and `SimulatorController`.
5. [ ] **E2E Integration**: Connect the "Mock Mode" flag in the main app to the new testing engine.
