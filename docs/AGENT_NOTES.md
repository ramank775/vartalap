# Agent Notes (Shared)

This file is a lightweight coordination log. Use it to hand off context between tools/agents.

## Codex Notes (2026-02-07)
- `flutter analyze` now clean.
- `flutter test` now passing; prior failure was the ChatScreen status icon assertion.
- Linux desktop build still fails at link time with:
  - `/lib/x86_64-linux-gnu/libsecret-1.so.0: undefined reference to g_task_set_static_name`
  - `/lib/x86_64-linux-gnu/libsecret-1.so.0: undefined reference to g_once_init_enter_pointer`
  - `/lib/x86_64-linux-gnu/libsecret-1.so.0: undefined reference to g_once_init_leave_pointer`
  Likely caused by Snap Flutter toolchain using an older GLib than the system libsecret.
  Suggested fix: use non-snap Flutter (official tarball), or update GLib/libsecret on system.

## Gemini Notes (2026-02-07)
- **Status Review**: Uncommitted changes are highly aligned with the "Android + Mock Mode" release focus.
- **Architecture**: `taskq` integration refactor into `ChatTaskStore` (using main `ChatDatabase`) is sound and simplifies state management.
- **Documentation**: `PROJECT_STATUS.md`, `README.md`, and `docs/RELEASE_ANDROID_MOCK.md` are well-synchronized.
- **Technical Nit**: `ChatTaskStore.fetchTasksByStatus` uses `status.index` in the `where` clause; could be updated to `equals(status)` for better type safety with Drift's enum converter, but current implementation is functional.
- **Next Steps**: Recommend staging the untracked documentation and new `taskq` files to solidify the release candidate.

## Issue Notes (2026-02-07)
- **Bug**: In mock mode, after OTP verification the app can reach Chats while `CurrentUserProvider` has no Contact for the logged-in profile (logs show `[CurrentUser] No contact found for userId`). This causes null access in `ChatsState.navigate` if it assumes the user exists.
- **Root Cause**: The user profile is loaded, but no Contact row is created/ensured in the local DB for the current user.
- **Potential Fix (Layer-Safe)**:
  - Implement `ensureCurrentUserContact()` inside `vartalap_messaging_flutter` (not UI layer).
  - Call it from `AuthRepository.checkAuth()` and `AuthRepository.verifyOTP()` after profile fetch.
  - Logic: lookup Contact by `uid`/`phone`; if missing, insert a local Contact using profile data.
- **Request**: Gemini to validate this approach for architecture boundary compliance and suggest best insertion point (AuthRepository vs client init).
