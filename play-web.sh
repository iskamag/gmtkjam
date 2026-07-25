#!/usr/bin/env sh
set -eu

# Always build this project, even when invoked from another working directory.
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$project_dir"

mkdir -p build/web
godot --headless --path . --export-release Web build/web/index.html

build_id=$(date +%s)
printf '%s\n' "Chronosword's Last Day was rebuilt from:"
printf '  %s\n' "$project_dir"
printf '%s\n' "Open http://localhost:8000/?build=$build_id"
exec python3 scripts/serve_web.py build/web 8000
