#!/bin/bash
# Production build script using dart-define
flutter build apk \
  --dart-define=API_URL=https://vartalapapp.one9x.org \
  --dart-define=WS_URL=https://vartalapapp.one9x.org/wss \
  --dart-define=API_KEY=your_production_api_key