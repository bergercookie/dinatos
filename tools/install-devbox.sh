#!/usr/bin/env bash
# Install devbox for Dinatos development.
#
# Devbox provides a reproducible development environment with the tools needed
# by Dinatos: Python, uv, just, Docker, Flutter, CMake, and Git.
#
# Usage:
#   ./tools/install-devbox.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Installing devbox for Dinatos development..."

if command -v devbox >/dev/null 2>&1; then
    echo "devbox is already installed: $(devbox --version)"
else
    echo "Downloading and installing devbox..."
    curl -fsSL https://get.jetpack.io/devbox | bash
fi

if [ ! -f "$REPO_ROOT/devbox.json" ]; then
    echo "Error: devbox.json not found in $REPO_ROOT" >&2
    exit 1
fi

cd "$REPO_ROOT"
echo "Installing the pinned devbox environment..."
devbox install

echo
echo "Setup complete. Enter the environment with:"
echo "  devbox shell"
echo
echo "Then run 'just --list' to see available development tasks."
