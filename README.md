# Vartalap

[Vartalap](https://vartalap.one9x.org) is an open source personal chat application. It is design to provide the level of transparency in the personal messaging application with your data.

## Supported Platform

- [x] Android
- [ ] Ios

## Features
- Texts with emoji 
- Group Chat

## Quick Start for Developers 🚀

### Option 1: Mock Mode (No Server Required) - Fastest Way to Start!

Perfect for frontend development, UI/UX work, or trying out the app without server setup:

```bash
# Clone the repo
git clone https://github.com/ramank775/vartalap.git
cd vartalap

# Get dependencies
flutter pub get

# Run in mock mode (offline, no server needed!)
flutter run --dart-define MOCK_MODE=true
```

**Features in Mock Mode:**
- ✅ No server setup required
- ✅ No Firebase configuration needed
- ✅ Pre-populated with sample chats and contacts
- ✅ Perfect for UI development and testing
- ✅ Works completely offline
- ✅ Data persists across restarts

**VS Code Users:** Press `F5` and select **"🎭 Mock Mode (Offline Development)"** from the launch configurations dropdown.

**Login:** Use any phone number, then enter OTP `123456` (check console for details).

👉 **See [Local Development Guide](docs/LOCAL_DEVELOPMENT.md) for detailed mock mode documentation**

### Option 2: Full Setup (With Server)

For backend development or full production-like environment:

- Download or clone the repo `https://github.com/ramank775/vartalap.git`
- Get the required dependencies `flutter pub get`
- Setup local chat-sever by following instruction in [chat-server](https://www.github.com/ramank775/chat-server) repo.

### Configuration

The app uses `--dart-define` for configuration instead of JSON files. This provides better performance and security.

#### Required Configuration Variables:
- `API_URL` - Your chat server API URL
- `WS_URL` - Your chat server WebSocket URL
- `API_KEY` - Your API key (optional, can be empty)

#### Development Setup:
```bash
# Run with development server
flutter run \
  --dart-define=API_URL=http://localhost:3000 \
  --dart-define=WS_URL=ws://localhost:3000/wss \
  --dart-define=API_KEY=your_dev_api_key
```

#### Production Build:
```bash
# Build for production
flutter build apk \
  --dart-define=API_URL=https://vartalapapp.one9x.org \
  --dart-define=WS_URL=https://vartalapapp.one9x.org/wss \
  --dart-define=API_KEY=your_production_api_key
```

#### Optional Configuration Variables:
- `APP_DESCRIPTION` - Custom app description
- `SHARE_MESSAGE` - Custom share message
- `PRIVACY_POLICY` - Privacy policy URL

#### Environment Scripts (Recommended):
Convenience scripts are provided in the `scripts/` folder:

**Development:**
```bash
./scripts/dev.sh
```

**Production Build:**
```bash
./scripts/build-prod.sh
```

You can customize these scripts with your own server URLs and API keys.

#### Legacy Configuration (Deprecated):
The old `config.json` and `config.local.json` files are no longer used. Please migrate to `--dart-define` for better performance.


### Setup with Gitpod
Click on the Gitpod badge to start cloud IDE 

[![Gitpod ready-to-code](https://img.shields.io/badge/Gitpod-ready--to--code-blue?logo=gitpod)](https://gitpod.io/#https://github.com/ramank775/vartalap) 

Localhost command
- Feel free to use your own ports configuration

    `SMARTPHONE_INTERNAL_IP = 192.168.0.10`

    `SMARTPHONE_INTERNAL_PORT = 5555`

-  To switch adb on your device to work over the network using port 5555

    `adb tcpip SMARTPHONE_INTERNAL_PORT`

- Check connection from localhost

    `adb connect SMARTPHONE_INTERNAL_IP:SMARTPHONE_INTERNAL_PORT`

-  Ngrok tcp forward to your mobile or Forward a chosen port on your router

    `ngrok tcp SMARTPHONE_INTERNAL_IP:SMARTPHONE_INTERNAL_PORT`

Gitpod command
- Connect from your Gitpod to your localhost for debugging
    `adb connect NGROK_ADDRESS:NGROK_PORT`

    `flutter run`

Chat Server
- Start chat-sever by following instruction in [chat-server](https://www.github.com/ramank775/chat-server) repo.
- Use the `--dart-define` configuration method as described above to set your server URLs



# Contribution
[Vartalap](https://vartalap.one9x.org) is an open source project. We are looking for building the community around the project, welcoming everyone or anyone who is interested in contributing.

- Facing any issue? Raise an issue [here](https://github.com/ramank775/vartalap/issues/new?assignees=&labels=bug&template=bug_report.md&title=%5BBUG%5D) with the necessary details.

- Looking for a new feature? Raise an feature request [here](https://github.com/ramank775/vartalap/issues/new?assignees=&labels=enhancement&template=feature_request.md&title=%5BFEAT%5D).

- Found a security issue? Report it responsibility, view our security policy [here](https://github.com/ramank775/vartalap/security/policy).

- Wants to resolve an issue? **Thanks!** initiate the discussion on issue of your choice.

## Code Of Conduct

[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](./CODE_OF_CONDUCT.md)

Vartalap has adopted [Contributor Covenant](./CODE_OF_CONDUCT.md), we expect project participants to adhere to. Please read the [full text](./CODE_OF_CONDUCT.md) to understand what action will and will not be tolerated.


# LICENSE
[GNU GENERAL PUBLIC LICENSE](./LICENCE)

# Contact us
- Twitter [@vartalap_app](https://twitter.com/vartalap_app).

