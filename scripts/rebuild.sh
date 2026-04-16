#!/bin/bash
# Rebuild and restart c11mux app

set -e

cd "$(dirname "$0")/.."

# Kill existing app if running
pkill -9 -f "cmux" 2>/dev/null || true

# Build
swift build

# Copy to app bundle
cp .build/debug/cmux .build/debug/c11mux.app/Contents/MacOS/

# Open the app
open .build/debug/c11mux.app
