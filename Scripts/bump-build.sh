#!/bin/sh
# Scripts/bump-build.sh — increment CURRENT_PROJECT_VERSION in project.yml.
#
# project.yml is the single source of truth for the version pair (see
# docs/RELEASE.md). This script is the only thing that mutates the build number.
#
#   ./Scripts/bump-build.sh          # 1 -> 2, prints "2"
#   ./Scripts/bump-build.sh 41       # sets 41, prints "41"
#
# Safe in CI: set -eu, atomic rewrite via a temp file, refuses to run twice in one
# invocation, and a repeated `set` value is a no-op rather than a jump. Output on
# stdout is the build number only, so callers can do
# BUILD=$(./Scripts/bump-build.sh).
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
YML="$ROOT/project.yml"

[ -f "$YML" ] || { echo "bump-build: no project.yml at $YML" >&2; exit 1; }

current=$(sed -n 's/^[[:space:]]*CURRENT_PROJECT_VERSION:[[:space:]]*"\{0,1\}\([0-9][0-9]*\)"\{0,1\}[[:space:]]*$/\1/p' "$YML")
matches=$(printf '%s\n' "$current" | grep -c '^[0-9][0-9]*$' || true)

if [ "$matches" -ne 1 ]; then
    echo "bump-build: expected exactly one CURRENT_PROJECT_VERSION in project.yml, found $matches" >&2
    exit 1
fi

if [ "$#" -ge 1 ]; then
    # Explicit set: used when App Store Connect already holds a higher number
    # (asc builds next-number). Never go backwards.
    if ! printf '%s' "$1" | grep -qE '^[0-9]+$'; then
        echo "bump-build: '$1' is not a number" >&2
        exit 1
    fi
    if [ "$1" -lt "$current" ]; then
        echo "bump-build: refusing to move build number backwards ($current -> $1)" >&2
        exit 1
    fi
    next=$1
else
    next=$((current + 1))
fi

if [ "$next" -eq "$current" ]; then
    echo "$next"
    exit 0
fi

tmp="$YML.tmp.$$"
trap 'rm -f "$tmp"' EXIT INT TERM
sed 's/^\([[:space:]]*CURRENT_PROJECT_VERSION:[[:space:]]*\)"\{0,1\}[0-9][0-9]*"\{0,1\}[[:space:]]*$/\1"'"$next"'"/' "$YML" > "$tmp"
mv "$tmp" "$YML"
trap - EXIT INT TERM

echo "$next"
