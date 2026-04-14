#!/usr/bin/env bash
#
# degoogle_gate.sh — Pre-merge CI gate enforcing V3_ARCHITECTURE.md decision 1:
# ZERO Firebase and ZERO Google-specific runtime dependencies.
#
# This script is intentionally strict. It fails fast on the first check that
# detects a forbidden string or artifact, but prints per-check diagnostic
# output so developers can see exactly which file and which line triggered
# the failure.
#
# Scope: pre-merge only. The release-APK dex inspection (verifying no Google
# classes end up in the shipped artifact) is a separate release-time gate.

set -e

# Resolve repo root relative to this script so the gate works regardless of
# where CI invokes it from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PUBSPEC="$REPO_ROOT/pubspec.yaml"
APP_GRADLE="$REPO_ROOT/android/app/build.gradle"
ROOT_GRADLE="$REPO_ROOT/android/build.gradle"
GOOGLE_SERVICES_JSON="$REPO_ROOT/android/app/google-services.json"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# Check 1: pubspec.yaml must not contain firebase_* dependencies.
if [ -f "$PUBSPEC" ]; then
    if grep -q 'firebase_' "$PUBSPEC"; then
        echo "FAIL: pubspec.yaml contains firebase_* dependencies:" >&2
        grep -n 'firebase_' "$PUBSPEC" >&2
        exit 1
    fi
else
    fail "pubspec.yaml not found at $PUBSPEC"
fi

# Check 2: android/app/build.gradle must not reference Firebase/Google plugins.
if [ -f "$APP_GRADLE" ]; then
    if grep -q -E 'google-services|firebase-perf|firebase\.crashlytics' "$APP_GRADLE"; then
        echo "FAIL: android/app/build.gradle references Firebase/Google plugins:" >&2
        grep -n -E 'google-services|firebase-perf|firebase\.crashlytics' "$APP_GRADLE" >&2
        exit 1
    fi
else
    fail "android/app/build.gradle not found at $APP_GRADLE"
fi

# Check 3: android/build.gradle must not pull in Google/Firebase classpath
# entries. NOTE: the google() Maven repo is NOT forbidden — it's Google's
# public artifact hosting for the Android SDK tooling itself. We look for the
# group IDs com.google.gms and com.google.firebase, which only appear in
# classpath/implementation/api lines.
if [ -f "$ROOT_GRADLE" ]; then
    if grep -q -E 'com\.google\.gms|com\.google\.firebase' "$ROOT_GRADLE"; then
        echo "FAIL: android/build.gradle references Firebase/Google classpaths:" >&2
        grep -n -E 'com\.google\.gms|com\.google\.firebase' "$ROOT_GRADLE" >&2
        exit 1
    fi
else
    fail "android/build.gradle not found at $ROOT_GRADLE"
fi

# Check 4: google-services.json must not be present.
if [ -e "$GOOGLE_SERVICES_JSON" ]; then
    fail "android/app/google-services.json exists and must be removed"
fi

echo "OK: degoogle gate passed — no Firebase/Google-specific Android or Dart deps detected."
exit 0
