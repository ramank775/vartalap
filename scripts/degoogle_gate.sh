#!/usr/bin/env bash
#
# degoogle_gate.sh — CI gate enforcing V3_ARCHITECTURE.md decision 1 as
# amended by DECISIONS 121: ZERO Firebase anywhere; the `foss` build carries
# no Google code at all; the `gms` build adds exactly one library, UnifiedPush's
# embedded FCM distributor (`gmsImplementation`), and Google-specific code
# lives only in android/app/src/gms/.
#
# This script is intentionally strict. It fails fast on the first check that
# detects a forbidden string or artifact, but prints per-check diagnostic
# output so developers can see exactly which file and which line triggered
# the failure.
#
#   scripts/degoogle_gate.sh                     source/config checks (pre-merge)
#   scripts/degoogle_gate.sh apk <file> foss|gms the built APK's dex (release)

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
# Google, Firebase or embedded-distributor class; gms no Google or Firebase
# class (the distributor talks to Play services over IPC, not a library)
# and, as a sanity check, the distributor itself.
if [ "${1:-}" = "apk" ]; then
    APK="${2:?usage: degoogle_gate.sh apk <file.apk> foss|gms}"
    VARIANT="${3:?usage: degoogle_gate.sh apk <file.apk> foss|gms}"
    DEX_DIR="$(mktemp -d)"
    trap 'rm -rf "$DEX_DIR"' EXIT
    unzip -q -o -j "$APK" 'classes*.dex' -d "$DEX_DIR"
    FORBIDDEN='Lcom/google/firebase/|Lcom/google/android/gms/'
    EMBEDDED='Lorg/unifiedpush/android/embedded_fcm_distributor/'
    case "$VARIANT" in
        foss) FORBIDDEN="$FORBIDDEN|$EMBEDDED" ;;
        gms) strings "$DEX_DIR"/*.dex | grep -q "$EMBEDDED" ||
            fail "$APK has no embedded FCM distributor classes" ;;
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
# plugins or libraries.
GOOGLE_DEPS='google-services|firebase-perf|firebase\.crashlytics|com\.google\.firebase|com\.google\.android\.gms|play-services'
if [ -f "$APP_GRADLE" ]; then
    if grep -q -E "$GOOGLE_DEPS" "$APP_GRADLE"; then
        echo "FAIL: android/app/build.gradle references Firebase/Google plugins or libraries:" >&2
        grep -n -E "$GOOGLE_DEPS" "$APP_GRADLE" >&2
        exit 1
    fi
else
    fail "android/app/build.gradle not found at $APP_GRADLE"
fi

# Check 2b: the one allowed exception — the embedded FCM distributor — is
# declared exactly once, and only for the gms flavor.
EMBEDDED_LINES="$(grep -rn -E 'embedded[-_]fcm' "$REPO_ROOT/android" "$PUBSPEC" \
    --include='*.gradle' --include='*.kts' --include='pubspec.yaml' || true)"
ALLOWED="^$APP_GRADLE:[0-9]+:[[:space:]]*gmsImplementation 'org\.unifiedpush\.android:embedded-fcm-distributor:[0-9.]+'[[:space:]]*$"
if [ "$(printf '%s\n' "$EMBEDDED_LINES" | grep -c .)" -ne 1 ] ||
    ! printf '%s\n' "$EMBEDDED_LINES" | grep -q -E "$ALLOWED"; then
    echo "FAIL: the embedded FCM distributor must be one gmsImplementation line in android/app/build.gradle; found:" >&2
    printf '%s\n' "$EMBEDDED_LINES" >&2
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

# Check 4: no google-services.json, in any source set.
GOOGLE_SERVICES_JSON="$(find "$REPO_ROOT/android" -name google-services.json)"
if [ -n "$GOOGLE_SERVICES_JSON" ]; then
    fail "google-services.json must not exist: $GOOGLE_SERVICES_JSON"
fi

echo "OK: degoogle gate passed — no Firebase; Google code only as the gms-scoped embedded FCM distributor."
exit 0
