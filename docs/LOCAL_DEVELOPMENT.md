# Local Development Guide - Mock Mode

## Overview

Vartalap supports **Mock Mode** for fast local development without requiring a backend server or Firebase. This mode allows frontend developers to work on UI/UX, test features, and iterate quickly without any external dependencies.

## Features

✅ **No Server Required** - Works completely offline
✅ **No Firebase Required** - Skip Firebase initialization and OTP
✅ **Realistic Mock Data** - Sample channels, messages, and contacts
✅ **Fast Iteration** - No network delays, instant responses
✅ **Full Functionality** - All UI features work with mock data

## Quick Start

### Running in Mock Mode

```bash
# Run the app in mock mode (offline development)
flutter run --dart-define MOCK_MODE=true

# Or with specific device
flutter run --dart-define MOCK_MODE=true -d <device-id>
```

### Running in Production Mode

```bash
# Run the app in production mode (requires server)
flutter run

# This is the default mode, connects to real backend
```

## How It Works

### Architecture

Mock mode uses **dependency injection at the app boundary** (in `main.dart`) to swap implementations:

```
┌─────────────────────────────────────────────────┐
│              main.dart (App Boundary)           │
│  ┌──────────────────────────────────────────┐   │
│  │  if (AppConfig.isMockMode)               │   │
│  │    → MockVartalapChatClient              │   │
│  │    → TestOTPProvider                     │   │
│  │  else                                    │   │
│  │    → VartalapChatClient (real)           │   │
│  │    → FirebaseOTPProvider (real)          │   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│         VartalapAuthenticatedClient             │
│         (No knowledge of mock mode)             │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│              Rest of the App                    │
│         (No knowledge of mock mode)             │
└─────────────────────────────────────────────────┘
```

### Key Components

1. **AppConfig.isMockMode**
   - Build-time flag from `--dart-define MOCK_MODE=true`
   - Located in `lib/config/app_config.dart`

2. **MockVartalapChatClient**
   - Drop-in replacement for `VartalapChatClient`
   - Located in `packages/vartalap_messaging/lib/client/mock_client.dart`
   - Provides realistic mock data for all API calls

3. **TestOTPProvider**
   - Drop-in replacement for `FirebaseOTPProvider`
   - Located in `lib/services/otp/iotp_provider.dart`
   - **Correct OTP**: `123456` (any other OTP will fail)
   - Allows testing both success and error cases
   - Returns the actual phone number you entered

## Mock Data

### Default Mock User
- **Phone Number**: `+1234567890`
- **Name**: "You (Test User)"

### Sample Contacts (5 users)
1. Alice Johnson - `+9876543210`
2. Bob Smith - `+1122334455`
3. Charlie Brown - `+5566778899`
4. Diana Prince - `+9988776655`
5. Eve Martinez - `+4433221100`

### Sample Channels
- **3 x 1-on-1 Chats** - With Alice, Bob, and Charlie
- **1 x Group Chat** - "Team Vartalap" with 4 members

All channels come pre-populated with realistic message history.

## Development Workflow

### 1. Start Development
```bash
# Start in mock mode
flutter run --dart-define MOCK_MODE=true

# Login with any phone number
# Enter any OTP (all OTPs are accepted in mock mode)
```

### 2. Develop Features
- All UI screens work normally
- Channels and messages are pre-populated
- Send messages, create channels, etc.
- Changes reflect immediately in local database

### 3. Hot Reload/Restart
```bash
# Hot reload (r)
r

# Hot restart (R)
R

# Mock data persists across hot reloads
```

### 4. Switch to Production Mode
```bash
# Test with real server
flutter run

# Ensure features work with real backend
```

## Testing Scenarios

### Authentication Flow
```bash
# Mock Mode
1. Enter any phone number (e.g., +1234567890)
2. Check debug console for the correct OTP:
   [TEST OTP] Use OTP: 123456
3. Enter OTP: 123456 ✅
   - Correct: Login succeeds
   - Wrong OTP: Error shown (allows testing error handling)
4. The phone number you entered will be your user ID
```

### Messaging
```bash
# Mock Mode
1. View pre-populated chats
2. Send messages (stored locally)
3. Messages appear instantly
4. No network required
```

### Contacts
```bash
# Mock Mode
1. All sample contacts appear as "available"
2. Can create new channels with any contact
3. Changes persist in local database
```

## Troubleshooting

### Issue: App still trying to connect to server

**Solution**: Ensure you're passing the flag correctly
```bash
flutter run --dart-define MOCK_MODE=true
```

Check logs for: `🎭 [MOCK] Running in MOCK MODE - no server required!`

### Issue: Firebase errors in mock mode

**Solution**: Firebase should be lazily initialized. If you see Firebase errors:
1. Check that `AppConfig.isMockMode` is properly set
2. Verify `TestOTPProvider` is being used
3. Check for any hardcoded Firebase calls

### Issue: No mock data appearing

**Solution**:
1. Ensure app is fully initialized
2. Check that `MockVartalapChatClient._initializeMockData()` is called
3. Verify local database is working

### Issue: Changes not persisting

**Solution**:
- Mock data is stored in local database
- Use hot reload (r) instead of hot restart (R) to preserve data
- Full restart will reset to initial mock data

## Adding Custom Mock Data

### Customize Mock User

Edit `packages/vartalap_messaging/lib/client/mock_client.dart`:

```dart
MockVartalapChatClient({
  this.mockUserId = "+YOUR_PHONE_NUMBER",  // Change this
}) : super(...);
```

### Add More Sample Contacts

In `_initializeMockData()` method:

```dart
final contacts = [
  // Add your custom contacts here
  MockProfile(
    userId: "+1111111111",
    name: "Your Friend",
    email: "friend@example.com",
  ),
  // ... existing contacts
];
```

### Modify Sample Messages

In `_generateSampleMessages()` method:

```dart
final sampleTexts = [
  "Your custom message 1",
  "Your custom message 2",
  // ... more messages
];
```

## Production Deployment

### Important Notes

1. **Never deploy with MOCK_MODE=true**
   ```bash
   # Production builds should NOT include --dart-define MOCK_MODE=true
   flutter build apk
   flutter build ios
   ```

2. **Tree Shaking**
   - Mock code is automatically removed from production builds
   - When `MOCK_MODE=false`, mock classes are not included

3. **Verification**
   ```bash
   # Verify production mode
   flutter run --release

   # Should NOT see: "Running in MOCK MODE"
   ```

## IDE Integration

### VS Code

Create `.vscode/launch.json`:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Flutter (Mock Mode)",
      "type": "dart",
      "request": "launch",
      "program": "lib/main.dart",
      "args": [
        "--dart-define",
        "MOCK_MODE=true"
      ]
    },
    {
      "name": "Flutter (Production)",
      "type": "dart",
      "request": "launch",
      "program": "lib/main.dart"
    }
  ]
}
```

### Android Studio / IntelliJ

1. Run → Edit Configurations
2. Additional run args: `--dart-define MOCK_MODE=true`
3. Save as "Mock Mode" configuration

## Benefits for Development

### For Frontend Developers
- ✅ Work independently without backend team
- ✅ No server setup or configuration
- ✅ Instant app startup and responses
- ✅ Predictable, consistent data

### For Backend Developers
- ✅ Test UI changes without affecting backend
- ✅ Develop API changes in parallel
- ✅ Clear contract through mock implementation

### For QA Team
- ✅ Test UI flows without network dependency
- ✅ Predictable test data
- ✅ Fast test execution
- ✅ Edge case testing with custom mock data

## Technical Details

### Build-time Constant

```dart
// lib/config/app_config.dart
static const bool isMockMode = bool.fromEnvironment('MOCK_MODE', defaultValue: false);
```

- Evaluated at **compile time**
- Zero runtime overhead when `false`
- Tree-shaking removes unused code

### Dependency Injection

```dart
// lib/main.dart - ONLY file that knows about mock mode
final chatClient = AppConfig.isMockMode
  ? MockVartalapChatClient()       // Mock implementation
  : VartalapChatClient(...);        // Real implementation

final otpProvider = AppConfig.isMockMode
  ? OTPProviderFactory.createTest()  // Test OTP
  : FirebaseOTPProvider();           // Real OTP
```

### Clean Architecture

- ✅ Service layer has **zero knowledge** of mock mode
- ✅ Business logic remains **completely untouched**
- ✅ Mock logic **isolated to app boundary**
- ✅ Easy to maintain and extend

## Future Enhancements

### Planned Features

1. **Configurable Mock Data**
   - JSON files for custom mock scenarios
   - UI to switch between mock data sets

2. **Network Simulation**
   - Simulate network delays
   - Simulate network errors
   - Test offline scenarios

3. **Mock Data Persistence**
   - Save/load mock data states
   - Share mock data between team members

4. **Integration with Tests**
   - Use same mocks for widget tests
   - Use same mocks for integration tests

## Support

If you encounter issues with mock mode:

1. Check this documentation
2. Review logs for `[MOCK]` tagged messages
3. Verify `AppConfig.isMockMode` value
4. Check GitHub issues: https://github.com/ramank775/vartalap/issues
5. Contact: vartalap@one9x.org

## Contributing

To improve mock mode:

1. Add realistic mock data
2. Improve mock implementations
3. Add more mock scenarios
4. Improve documentation

See [CONTRIBUTING.md](../CONTRIBUTING.md) for guidelines.
