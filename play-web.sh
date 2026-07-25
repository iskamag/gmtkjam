#!/usr/bin/env sh
set -eu

# Always build this project, even when invoked from another working directory.
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$project_dir"

build_id=$(date +%s)
export_dir="build/web-$build_id"
mkdir -p "$export_dir"

godot --headless --path . --export-release Web "$export_dir/index.html"

printf '%s\n' "Chronosword's Last Day was rebuilt from:"
printf '  %s\n' "$project_dir"
printf 'Build ID: %s\n' "$build_id"
printf 'Export:   %s\n' "$export_dir/index.pck"
exec python3 scripts/serve_web.py "$export_dir" 8000 "$build_id"
