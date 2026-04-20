#!/usr/bin/env bash
# Snapshot the canonical simulation source files from the repo root into
# webapp/backend/sim/ so the webapp directory is self-contained for
# deployment. Run this whenever the sim files change.
#
# Usage:  ./webapp/sync-sim.sh
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
dest="$script_dir/backend/sim"
mkdir -p "$dest"

files=(
    advgames.jl
    advgames_network.jl
    advgames_analysis.jl
    base_params.jl
    peer_selection.jl
)

for f in "${files[@]}"; do
    src="$repo_root/$f"
    if [ ! -f "$src" ]; then
        echo "ERROR: missing source file $src" >&2
        exit 1
    fi
    cp "$src" "$dest/$f"
    echo "  synced $f"
done

echo
echo "Wrote $dest"
echo "Remember to commit these copies (or include them in your deploy rsync)."
