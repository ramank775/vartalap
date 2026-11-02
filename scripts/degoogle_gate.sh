#!/usr/bin/env bash
#
# degoogle_gate.sh — CI gate enforcing V3_ARCHITECTURE.md decision 1 as
# amended by DECISIONS 121 and 209: the `foss` build carries no Google code at
# all; the `gms` build adds exactly one library, Firebase Cloud Messaging
# (`gmsImplementation`, decision 209), Google-specific code lives only in
# android/app/src/gms/, and no Firebase config file is ever committed.
#
# This script is intentionally strict. It fails fast on the first check that
# detects a forbidden string or artifact, but prints per-check diagnostic
# output so developers can see exactly which file and which line triggered
# the failure.
#
#   scripts/degoogle_gate.sh                     source/config checks (pre-merge)
#   scripts/degoogle_gate.sh apk <file> foss|gms the built APK's or AAB's dex

set -e

# Resolve repo root relative to this script so the gate works regardless of
# where CI invokes it from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PUBSPEC="$REPO_ROOT/pubspec.yaml"
APP_GRADLE="$REPO_ROOT/android/app/build.gradle"
ROOT_GRADLE="$REPO_ROOT/android/build.gradle"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# Release-time half: class descriptors in the APK's dex. foss must hold no
# Google, Firebase or embedded-distributor class; gms must hold Firebase
# Messaging (a sanity check that it is the gms build) and not the retired
# embedded distributor.
if [ "${1:-}" = "apk" ]; then
    APK="${2:?usage: degoogle_gate.sh apk <file.apk> foss|gms}"
    VARIANT="${3:?usage: degoogle_gate.sh apk <file.apk> foss|gms}"
    DEX_DIR="$(mktemp -d)"
    trap 'rm -rf "$DEX_DIR"' EXIT
    # an APK keeps its dex at the root, an AAB under base/dex/
    unzip -q -o -j "$APK" '*classes*.dex' -d "$DEX_DIR"
    FORBIDDEN='Lcom/google/firebase/|Lcom/google/android/gms/'
    EMBEDDED='Lorg/unifiedpush/android/embedded_fcm_distributor/'
    case "$VARIANT" in
        foss) FORBIDDEN="$FORBIDDEN|$EMBEDDED" ;;
        gms) strings "$DEX_DIR"/*.dex | grep -q 'Lcom/google/firebase/messaging/' ||
            fail "$APK has no Firebase Messaging classes"
            FORBIDDEN="$EMBEDDED" ;;
        *) fail "variant must be foss or gms, not $VARIANT" ;;
    esac
    HITS="$(strings "$DEX_DIR"/*.dex | grep -o -E "($FORBIDDEN)[^;]*" | sort -u || true)"
    if [ -n "$HITS" ]; then
        echo "$HITS" | head -20 >&2
        fail "$APK ($VARIANT) contains forbidden classes (listed above)"
    fi
    echo "OK: $APK ($VARIANT) has no forbidden classes."
    exit 0
fi

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

# Check 2: android/app/build.gradle must not reference Firebase/Google
# plugins or libraries, apart from the one gms line checked next.
GOOGLE_DEPS='google-services|firebase-perf|firebase\.crashlytics|com\.google\.firebase|com\.google\.android\.gms|play-services'
FCM_LINE="^[[:space:]]*gmsImplementation 'com\.google\.firebase:firebase-messaging:[0-9.]+'[[:space:]]*$"
if [ -f "$APP_GRADLE" ]; then
    if grep -v -E "$FCM_LINE" "$APP_GRADLE" | grep -q -E "$GOOGLE_DEPS"; then
        echo "FAIL: android/app/build.gradle references Firebase/Google plugins or libraries:" >&2
        grep -n -E "$GOOGLE_DEPS" "$APP_GRADLE" >&2
        exit 1
    fi
else
    fail "android/app/build.gradle not found at $APP_GRADLE"
fi

# Check 2b: the one allowed exception — Firebase Cloud Messaging (decision
# 209) — is declared exactly once, and only for the gms flavor.
FCM_LINES="$(grep -rn -E 'firebase-messaging|embedded[-_]fcm' "$REPO_ROOT/android" "$PUBSPEC" \
    --include='*.gradle' --include='*.kts' --include='pubspec.yaml' || true)"
if [ "$(printf '%s\n' "$FCM_LINES" | grep -c .)" -ne 1 ] ||
    ! printf '%s\n' "$FCM_LINES" | sed -E 's/^[^:]+:[0-9]+://' | grep -q -E "$FCM_LINE"; then
    echo "FAIL: Firebase Messaging must be one gmsImplementation line in android/app/build.gradle; found:" >&2
    printf '%s\n' "$FCM_LINES" >&2
    exit 1
fi

# Check 2c: Google-specific code and manifest entries live only in the gms
# source set; main and foss stay clean.
GOOGLE_SRC="$(grep -rln -E 'com\.google\.android\.gms|com\.google\.firebase' \
    "$REPO_ROOT/android/app/src" --exclude-dir=gms || true)"
if [ -n "$GOOGLE_SRC" ]; then
    echo "FAIL: Google-specific references outside android/app/src/gms:" >&2
    echo "$GOOGLE_SRC" >&2
    exit 1
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

# Check 4: no Firebase config committed (the Play build's is generated from
# a git-ignored google-services.json, decision 209).
FIREBASE_CONFIG="$(git -C "$REPO_ROOT" ls-files -- '*google-services.json' 'android/app/src/*/res/values/firebase.xml')"
if [ -n "$FIREBASE_CONFIG" ]; then
    fail "Firebase config must not be committed: $FIREBASE_CONFIG"
fi

echo "OK: degoogle gate passed — Google code only as the gms-scoped Firebase Messaging."
exit 0
