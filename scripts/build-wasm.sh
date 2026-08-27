#!/bin/bash
set -euo pipefail

echo "🔨 Building ghostty-vt.wasm..."

# Check for Zig (Ghostty requires 0.15.x; 0.16+ has breaking API changes)
ZIG_BIN=""

# First try zig on PATH
if command -v zig &> /dev/null; then
    ver=$(zig version 2>/dev/null || true)
    if [[ "$ver" == 0.15.* ]]; then
        ZIG_BIN=zig
    fi
fi

# Fall back to asdf-managed Zig 0.15.x
if [ -z "$ZIG_BIN" ]; then
    for z in ~/.asdf/installs/zig/0.15.*/zig; do
        if [ -x "$z" ]; then
            ZIG_BIN="$z"
            break
        fi
    done
fi

if [ -z "$ZIG_BIN" ]; then
    echo "❌ Error: Zig 0.15.x not found"
    echo ""
    echo "Install Zig 0.15.2+:"
    echo "  macOS:   brew install zig@0.15"
    echo "  Linux:   https://ziglang.org/download/"
    echo ""
    exit 1
fi

ZIG_VERSION=$($ZIG_BIN version)
echo "✓ Found Zig $ZIG_VERSION ($ZIG_BIN)"

# Initialize/update submodule
if [ ! -d "ghostty/.git" ]; then
    echo "📦 Initializing Ghostty submodule..."
    git submodule update --init --recursive
else
    echo "📦 Ghostty submodule already initialized"
fi

# Apply patch
echo "🔧 Applying WASM API patch..."
cd ghostty
git apply --check ../patches/ghostty-wasm-api.patch || {
    echo "❌ Patch doesn't apply cleanly"
    echo "Ghostty may have changed. Check patches/ghostty-wasm-api.patch"
    exit 1
}
git apply ../patches/ghostty-wasm-api.patch

# Build WASM
echo "⚙️  Building WASM (takes ~20 seconds)..."
$ZIG_BIN build lib-vt -Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall

# Copy to project root
cd ..
cp ghostty/zig-out/bin/ghostty-vt.wasm ./

# Revert patch to keep submodule clean
echo "🧹 Cleaning up..."
cd ghostty
git apply -R ../patches/ghostty-wasm-api.patch
# Remove new files created by the patch
rm -f include/ghostty/vt/terminal.h
rm -f src/terminal/c/terminal.zig
cd ..

SIZE=$(du -h ghostty-vt.wasm | cut -f1)
echo "✅ Built ghostty-vt.wasm ($SIZE)"
