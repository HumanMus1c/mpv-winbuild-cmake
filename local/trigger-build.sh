#!/usr/bin/env bash
# Cloud build trigger for the diagnostic mpv toolchain.
#
# Usage (from Git Bash):
#   local/trigger-build.sh                 # push-less check: trigger only if the mpv
#                                          # HEAD commit message contains the [build] marker
#   local/trigger-build.sh --push          # git push the mpv branch to the fork first, then check
#   local/trigger-build.sh --force         # trigger regardless of the marker
#   local/trigger-build.sh --ref <branch>  # build this mpv ref (default: current branch of $MPV_LOCAL)
#   local/trigger-build.sh --repo <url>    # mpv repository URL (default: the HumanMus1c/mpv fork)
#
# Convention: append [build] to a commit subject to mark "this commit is worth a
# cloud build". WIP commits without the marker never trigger anything.
set -euo pipefail

MPV_LOCAL="${MPV_LOCAL:-/d/Documents/GitHub/mpv}"
FORK_SLUG="${FORK_SLUG:-HumanMus1c/mpv-winbuild-cmake}"

DO_PUSH=0
FORCE=0
REF=""
REPO_URL=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --push) DO_PUSH=1 ;;
        --force) FORCE=1 ;;
        --ref) REF="$2"; shift ;;
        --repo) REPO_URL="$2"; shift ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

BRANCH=$(git -C "$MPV_LOCAL" branch --show-current)
REF="${REF:-$BRANCH}"
[[ -n "$REF" ]] || { echo "cannot determine mpv ref (detached HEAD?); pass --ref" >&2; exit 1; }

if [[ "$DO_PUSH" == 1 ]]; then
    git -C "$MPV_LOCAL" push fork "$REF"
fi

if [[ "$FORCE" == 0 ]]; then
    MSG=$(git -C "$MPV_LOCAL" log -1 --pretty=%B "$REF")
    if ! grep -q '\[build\]' <<<"$MSG"; then
        echo "no [build] marker on HEAD of '$REF' - not triggering."
        git -C "$MPV_LOCAL" log -1 --pretty='  (%h %s)' "$REF"
        exit 0
    fi
fi

TOKEN=$(printf "protocol=https\nhost=github.com\n\n" | git credential fill 2>/dev/null | grep '^password=' | cut -d= -f2-)
[[ -n "$TOKEN" ]] || { echo "no git credential available for github.com" >&2; exit 1; }

REPO_URL="${REPO_URL:-https://github.com/HumanMus1c/mpv.git}"
PAYLOAD=$(printf '{"event_type":"build-mpv","client_payload":{"mpv_ref":"%s","mpv_repo":"%s"}}' "$REF" "$REPO_URL")
HTTP=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$FORK_SLUG/dispatches" -d "$PAYLOAD")
echo "repository_dispatch -> $FORK_SLUG (ref=$REF): HTTP $HTTP (204 = accepted)"
[[ "$HTTP" == "204" ]]

# Fetch the run link (run creation lags the dispatch by a few seconds).
for _ in 1 2 3 4; do
    sleep 5
    URL=$(curl -s -H "Authorization: token $TOKEN" \
        "https://api.github.com/repos/$FORK_SLUG/actions/runs?per_page=1" \
        | grep -m1 -o 'https://github.com/[^"]*actions/runs/[0-9]*' || true)
    if [[ -n "$URL" ]]; then
        echo "run: $URL"
        exit 0
    fi
done
echo "dispatch accepted but run link not visible yet - check the Actions page."
