#!/bin/bash
# Development run script using dart-define
flutter run \
  --dart-define=API_URL=http://localhost:3000 \
  --dart-define=WS_URL=ws://localhost:3000/wss \
  --dart-define=API_KEY=