#!/usr/bin/env bash
# Install the Android SDK command-line tools (sdkmanager) and accept its
# licenses non-interactively, for building frontend/ Android targets
# (`flutter build apk`, etc.) without Android Studio.
#
# The Gradle build picks its own compileSdk/targetSdk/NDK versions from the
# installed Flutter SDK (see frontend/android/app/build.gradle.kts's
# `flutter.compileSdkVersion` etc.) -- this script does not pin those. It
# only provisions sdkmanager itself and accepts all licenses, then lets
# Gradle auto-download whatever specific platform/build-tools/NDK packages
# a given build asks for.
#
# Usage:
#   ./tools/install-android-sdk.sh
#
# Respects an existing ANDROID_HOME/ANDROID_SDK_ROOT if already set (e.g. an
# apt-installed `android-sdk` at /usr/lib/android-sdk); otherwise installs
# under ~/Android/Sdk. Override the command-line tools package with
# ANDROID_CMDLINE_TOOLS_URL if the version below has been superseded --
# check https://developer.android.com/studio#command-line-tools-only for
# the current one.

set -euo pipefail

ANDROID_CMDLINE_TOOLS_URL="${ANDROID_CMDLINE_TOOLS_URL:-https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip}"
SDK_ROOT="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"

echo "Installing Android SDK command-line tools into: $SDK_ROOT"

if [ -e "$SDK_ROOT" ] && [ ! -w "$SDK_ROOT" ]; then
    echo "Error: $SDK_ROOT exists but is not writable by $(whoami)." >&2
    echo "Either fix its permissions, or point ANDROID_HOME at a writable directory and re-run." >&2
    exit 1
fi

CMDLINE_TOOLS_DIR="$SDK_ROOT/cmdline-tools/latest"
SDKMANAGER="$CMDLINE_TOOLS_DIR/bin/sdkmanager"

if [ -x "$SDKMANAGER" ]; then
    echo "sdkmanager already installed at $SDKMANAGER"
else
    WORK_DIR="$(mktemp -d)"
    trap 'rm -rf "$WORK_DIR"' EXIT

    echo "Downloading command-line tools from $ANDROID_CMDLINE_TOOLS_URL..."
    curl -fsSL -o "$WORK_DIR/cmdline-tools.zip" "$ANDROID_CMDLINE_TOOLS_URL"

    echo "Extracting..."
    unzip -q "$WORK_DIR/cmdline-tools.zip" -d "$WORK_DIR"

    # The zip's top-level folder is always named "cmdline-tools" -- sdkmanager
    # refuses to run unless it lives one level deeper, under a "latest" (or
    # otherwise version-named) directory.
    mkdir -p "$SDK_ROOT/cmdline-tools"
    rm -rf "$CMDLINE_TOOLS_DIR"
    mv "$WORK_DIR/cmdline-tools" "$CMDLINE_TOOLS_DIR"
fi

export ANDROID_HOME="$SDK_ROOT"
export ANDROID_SDK_ROOT="$SDK_ROOT"

echo "Installing platform-tools..."
"$SDKMANAGER" --sdk_root="$SDK_ROOT" "platform-tools" >/dev/null

echo "Accepting all SDK licenses..."
yes | "$SDKMANAGER" --sdk_root="$SDK_ROOT" --licenses >/dev/null

echo
echo "Done. sdkmanager is installed and its licenses are accepted."
echo "Add these to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
echo
echo "  export ANDROID_HOME=\"$SDK_ROOT\""
echo "  export ANDROID_SDK_ROOT=\"$SDK_ROOT\""
echo "  export PATH=\"\$ANDROID_HOME/cmdline-tools/latest/bin:\$ANDROID_HOME/platform-tools:\$PATH\""
echo
echo "Then retry the Android build (e.g. 'flutter build apk' in frontend/)."
echo "Gradle will auto-download whatever platform/build-tools/NDK version"
echo "your installed Flutter SDK requests, now that licenses are accepted."
