#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repository_dir="$(cd "$script_dir/.." && pwd)"
distribution_dir="$repository_dir/dist/macos"
app_dir="$distribution_dir/Argentina Five Pets.app"
contents_dir="$app_dir/Contents"

sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
binary_dir="$script_dir/.build/release"
module_cache="$script_dir/.build/module-cache"
mkdir -p "$binary_dir" "$module_cache"

clang \
    -fobjc-arc \
    -fmodules \
    -fmodules-cache-path="$module_cache" \
    -mmacosx-version-min=11.0 \
    -isysroot "$sdk_path" \
    -arch arm64 \
    -arch x86_64 \
    -O2 \
    "$script_dir/src/PetCore.m" \
    "$script_dir/src/main.m" \
    -framework AppKit \
    -framework CoreGraphics \
    -o "$binary_dir/ArgentinaFivePets"

mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources/assets"
cp "$binary_dir/ArgentinaFivePets" "$contents_dir/MacOS/ArgentinaFivePets"
cp "$script_dir/Info.plist" "$contents_dir/Info.plist"
cp "$repository_dir"/assets/*.png "$contents_dir/Resources/assets/"

if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$app_dir"
fi

archive_path="$distribution_dir/Argentina-Five-Pets-macOS.zip"
rm -f "$archive_path"
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$archive_path"

printf '%s\n' "$app_dir"
printf '%s\n' "$archive_path"
