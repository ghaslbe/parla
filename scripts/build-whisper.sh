#!/usr/bin/env bash
# Fetch and build whisper.cpp as static libraries with the Metal backend
# embedded, then stage the libs + public headers for SwiftPM to link against.
#
# Idempotent: skips the build if the staged libs already exist. Pass "clean"
# to force a rebuild.
set -euo pipefail

WHISPER_TAG="v1.9.5"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/third_party/whisper.cpp"
BUILD="$SRC/build"
LIBDIR="$ROOT/third_party/lib"
INCDIR="$ROOT/Sources/CWhisper/include"

if [ "${1:-}" = "clean" ]; then
    rm -rf "$BUILD" "$LIBDIR" "$INCDIR"
fi

# Already staged? Nothing to do.
if [ -f "$LIBDIR/libwhisper.a" ] && [ -f "$INCDIR/whisper.h" ]; then
    echo "==> whisper.cpp already built ($LIBDIR). Use 'clean' to rebuild."
    exit 0
fi

# 1. Fetch source at the pinned tag.
if [ ! -d "$SRC/.git" ]; then
    echo "==> cloning whisper.cpp $WHISPER_TAG"
    rm -rf "$SRC"
    git clone --depth 1 --branch "$WHISPER_TAG" \
        https://github.com/ggml-org/whisper.cpp "$SRC"
fi

# 2. Configure + build static libs with Metal embedded.
echo "==> building whisper.cpp (Release, Metal embedded, static)"
cmake -S "$SRC" -B "$BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DGGML_ACCELERATE=ON \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_SERVER=OFF >/dev/null
cmake --build "$BUILD" --config Release -j"$(sysctl -n hw.ncpu)"

# 3. Stage static libraries.
echo "==> staging static libraries -> $LIBDIR"
mkdir -p "$LIBDIR"
find "$BUILD" -name '*.a' -exec cp {} "$LIBDIR/" \;
ls "$LIBDIR"

# 4. Stage public headers for the CWhisper module.
echo "==> staging headers -> $INCDIR"
mkdir -p "$INCDIR"
cp "$SRC/include/whisper.h" "$INCDIR/"
cp "$SRC/ggml/include/"*.h "$INCDIR/"

echo "==> whisper.cpp ready."
