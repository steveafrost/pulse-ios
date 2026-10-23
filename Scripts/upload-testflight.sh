#!/bin/sh
# Scripts/upload-testflight.sh — thin wrapper around `asc builds upload`.
#
# Exists so CI can upload without Ruby/bundler. The fastlane `beta` lane calls
# this; you can also run it by hand.
#
#   ./Scripts/upload-testflight.sh --dry-run
#   ./Scripts/upload-testflight.sh path/to/Pulse.ipa
#
# Credentials, in order of precedence:
#   1. ASC_KEY_ID + ASC_ISSUER_ID (+ ASC_KEY_PATH) in the environment -> asc uses them
#   2. an existing `asc auth list` account on this machine
# If neither is present the script exits 3 with the exact login command to run.
# It never prompts, never half-uploads, and never reads a password.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DRY_RUN=0
IPA=""

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -h|--help)
            sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*)
            echo "upload-testflight: unknown option $arg" >&2
            exit 2
            ;;
        *) IPA=$arg ;;
    esac
done

# --- version, read from the same source the build reads -----------------------
VERSION=$(sed -n 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"\{0,1\}\([0-9][0-9.]*\)"\{0,1\}[[:space:]]*$/\1/p' "$ROOT/project.yml")
BUILD=$(sed -n 's/^[[:space:]]*CURRENT_PROJECT_VERSION:[[:space:]]*"\{0,1\}\([0-9][0-9]*\)"\{0,1\}[[:space:]]*$/\1/p' "$ROOT/project.yml")
[ -n "$VERSION" ] && [ -n "$BUILD" ] || {
    echo "upload-testflight: could not read MARKETING_VERSION / CURRENT_PROJECT_VERSION from project.yml" >&2
    exit 1
}

APP_ID=${PULSE_ASC_APP_ID:-}
if [ -z "$APP_ID" ] && [ -f "$ROOT/fastlane/.env" ]; then
    APP_ID=$(sed -n 's/^PULSE_ASC_APP_ID=\(.*\)$/\1/p' "$ROOT/fastlane/.env" | tr -d '"' | tr -d "'")
fi

if [ "$DRY_RUN" -eq 0 ]; then
    [ -n "$IPA" ] || { echo "upload-testflight: no .ipa path given (try: ls build/*.ipa)" >&2; exit 2; }
    [ -f "$IPA" ] || { echo "upload-testflight: no file at $IPA" >&2; exit 2; }
fi

# --- credential gate ---------------------------------------------------------
have_env_key=0
if [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ]; then
    have_env_key=1
fi

have_stored_key=0
if command -v asc >/dev/null 2>&1; then
    if asc auth list 2>/dev/null | grep -q '"isActive"[[:space:]]*:[[:space:]]*true'; then
        have_stored_key=1
    fi
else
    echo "upload-testflight: the 'asc' CLI is not on PATH. Install it first: brew install asc" >&2
    exit 3
fi

if [ "$have_env_key" -eq 0 ] && [ "$have_stored_key" -eq 0 ]; then
    cat >&2 <<'MSG'
upload-testflight: no App Store Connect credentials.

Either log in once on this machine:

    asc auth login --key-id 38R6G5B784 \
                   --issuer-id 4e8ddd0a-9e6c-4877-ae9d-3f7168c02256 \
                   --key-path /path/to/AuthKey_38R6G5B784.p8

or export them for this shell / CI (see fastlane/.env.example):

    export ASC_KEY_ID=...
    export ASC_ISSUER_ID=...
    export ASC_KEY_PATH=/path/to/AuthKey_<KEYID>.p8

Then re-run this script. Nothing was uploaded.
MSG
    exit 3
fi

if [ -z "$APP_ID" ]; then
    if [ "$DRY_RUN" -eq 0 ]; then
        echo "upload-testflight: PULSE_ASC_APP_ID is empty." >&2
        echo "  The App Store Connect app record does not exist yet, so there is nothing to upload to." >&2
        echo "  Create it (App Store Connect -> My Apps -> + -> New App), then put the numeric id" >&2
        echo "  in fastlane/.env as PULSE_ASC_APP_ID=<id>. Nothing was uploaded." >&2
        exit 4
    fi
    APP_ID="<APP_ID>"
    echo "note: PULSE_ASC_APP_ID unset (no app record yet) - printing the command with a placeholder." >&2
fi

CMD="asc builds upload --app-id $APP_ID --file ${IPA:-<IPA>} --version $VERSION --build-number $BUILD --platform ios --wait"

if [ "$DRY_RUN" -eq 1 ]; then
    echo "dry run: would run:"
    echo "  $CMD"
    echo "  (version $VERSION, build $BUILD, app $APP_ID)"
    exit 0
fi

echo "uploading $IPA -> app $APP_ID, version $VERSION build $BUILD"
# shellcheck disable=SC2086 # intentional word splitting: this is the argv we built
exec $CMD
