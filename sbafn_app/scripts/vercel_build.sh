#!/usr/bin/env bash
set -e
git clone --depth 1 -b stable https://github.com/flutter/flutter.git
export PATH="$PWD/flutter/bin:$PATH"
flutter --version
flutter config --enable-web
flutter pub get
# Use the Vercel env var set in the dashboard
flutter build web --release --dart-define=MAPTILER_KEY="$MAPTILER_KEY"