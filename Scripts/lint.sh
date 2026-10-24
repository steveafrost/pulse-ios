#!/usr/bin/env bash
#
# Lint and format check for Third Hand iOS.
#
#   bash Scripts/lint.sh          # check only, exits non-zero on findings
#   bash Scripts/lint.sh --fix    # rewrite files, then check
#
# Design note: when the tools are missing this script PRINTS AN INSTALL HINT and
# exits 0. A fresh clone must not be blocked by tooling it never asked for; CI
# installs both via Homebrew and runs the same script, so the real gate lives
# there. Use `--strict-tools` to make a missing tool an error in CI-like
# contexts.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

FIX=0
STRICT_TOOLS=0
for arg in "$@"; do
  case "$arg" in
    --fix) FIX=1 ;;
    --strict-tools) STRICT_TOOLS=1 ;;
    -h|--help)
      sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "lint.sh: unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

missing=()
have_swiftformat=0
have_swiftlint=0

if command -v swiftformat >/dev/null 2>&1; then
  have_swiftformat=1
else
  missing+=(swiftformat)
fi

if command -v swiftlint >/dev/null 2>&1; then
  have_swiftlint=1
else
  missing+=(swiftlint)
fi

if [ "${#missing[@]}" -gt 0 ]; then
  echo "lint.sh: missing tool(s): ${missing[*]}"
  echo
  echo "Install them with Homebrew:"
  echo
  echo "    brew install swiftlint swiftformat"
  echo
  echo "Then re-run:  bash Scripts/lint.sh"
  echo
  if [ "$STRICT_TOOLS" -eq 1 ]; then
    echo "lint.sh: --strict-tools set, treating missing tools as failure." >&2
    exit 1
  fi
  echo "lint.sh: skipping checks (exit 0 so a fresh clone is not blocked)."
  exit 0
fi

status=0

# 1. Format check first: a formatting diff explains most downstream lint noise.
if [ "$FIX" -eq 1 ]; then
  echo "==> swiftformat (writing)"
  swiftformat . || status=1
else
  echo "==> swiftformat --lint"
  swiftformat --lint . || status=1
fi

# 2. Lint with --strict: warnings are errors.
echo
echo "==> swiftlint --strict"
swiftlint lint --strict || status=1

echo
if [ "$status" -eq 0 ]; then
  echo "lint.sh: clean"
else
  echo "lint.sh: findings above (run 'bash Scripts/lint.sh --fix' to auto-format)"
fi

exit "$status"
