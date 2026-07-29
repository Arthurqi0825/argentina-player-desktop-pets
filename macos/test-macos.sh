#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
build_dir="$script_dir/.build/tests"
module_cache="$script_dir/.build/module-cache"
mkdir -p "$build_dir" "$module_cache"

clang \
    -fobjc-arc \
    -fmodules \
    -fmodules-cache-path="$module_cache" \
    -mmacosx-version-min=11.0 \
    -isysroot "$sdk_path" \
    "$script_dir/src/PetCore.m" \
    "$script_dir/Tests/PetCoreTests.m" \
    -framework Foundation \
    -o "$build_dir/PetCoreTests"

"$build_dir/PetCoreTests"
