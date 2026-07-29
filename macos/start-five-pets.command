#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repository_dir="$(cd "$script_dir/.." && pwd)"
app_path="$repository_dir/dist/macos/Argentina Five Pets.app"

if [[ ! -d "$app_path" ]]; then
    "$script_dir/build-macos.sh"
fi

open "$app_path"
