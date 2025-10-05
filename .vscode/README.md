# VS Code Launch Configurations

This workspace includes pre-configured launch profiles for easy development.

## Available Configurations

### 🎭 Mock Mode (Offline Development)

**Best for:**
- Frontend/UI development
- Working without internet
- Fast iteration cycles
- Learning the app

**What it does:**
- Runs app in offline mock mode
- No server or Firebase required
- Pre-populated with sample data
- Data persists across restarts

**How to use:**
1. Press `F5` or click Run → Start Debugging
2. Select "🎭 Mock Mode (Offline Development)"
3. App launches with mock data
4. Login with any phone number and any OTP

**Debug console will show:**
```
🎭 [MOCK] Running in MOCK MODE - no server required!
[MOCK] Loaded persisted state: 4 channels, 6 profiles
```

---

### 🚀 Production Mode (With Server)

**Best for:**
- Backend integration testing
- Full feature testing
- Production-like environment

**What it does:**
- Connects to real chat server
- Uses Firebase for OTP
- Full authentication flow
- Real-time messaging

**How to use:**
1. Ensure chat server is running
2. Press `F5` or click Run → Start Debugging
3. Select "🚀 Production Mode (With Server)"
4. Login with real phone number and OTP

**Debug console will show:**
```
✅ [PERF] Firebase deferred to lazy initialization
```

---

### Vartalap-Dev

Legacy development configuration with flavor support.

---

### Flutter:profile

Performance profiling mode for optimization work.

---

## Quick Switching

You can quickly switch between configurations:

1. Click the dropdown next to the Run button in VS Code
2. Select your desired configuration
3. Press `F5` to launch

## Keyboard Shortcuts

- `F5` - Start Debugging (with current configuration)
- `Ctrl+F5` - Run Without Debugging
- `Shift+F5` - Stop Debugging

## Tips

- **Mock Mode** is selected by default for fastest startup
- Use **Production Mode** only when you need to test server integration
- Check debug console for `[MOCK]` logs to confirm which mode is active
- Mock data is stored in app documents and persists between runs

## Troubleshooting

**Issue:** "🎭 Mock Mode" still trying to connect to server
- Check debug console for the mock mode log
- Ensure you selected the correct launch configuration
- Try hot restart (`Shift+R` in debug console)

**Issue:** Cannot connect in Production Mode
- Verify chat server is running
- Check `API_URL` and `WS_URL` environment variables
- Review Firebase configuration

## Learn More

See [Local Development Guide](../docs/LOCAL_DEVELOPMENT.md) for comprehensive mock mode documentation.
