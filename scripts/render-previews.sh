#!/usr/bin/env bash
# Draws states of the main window to PNG files without putting a window on screen, for pull
# request evidence. Nothing appears, nothing takes focus, and it needs no Screen Recording
# permission, so an agent can run it without asking the owner. See `PreviewRenderer`.
#
#   scripts/render-previews.sh                              every state, light and dark
#   scripts/render-previews.sh page-4826-decision-first     only the states named
#   scripts/render-previews.sh --list                       lists the states
#   scripts/render-previews.sh --pr 3 page-4826-decision-first
#                                                           renders, then attaches the PNGs to
#                                                           pull request 3 in a comment
#
# Options:
#   --out <folder>          where the PNGs go, build/renders by default
#   --appearances "dark"    light and dark by default
#   --pr <number>           attach the PNGs to that pull request with `gh pr comment --attach`
#   --title "<text>"        the comment's first line, "Renders" by default
#
# It uses a debug build, copied to build/render, stamped with the SDK as bundle.sh does (or it
# draws in the old look), and signed ad hoc. The data is the built-in mock world.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="build/renders"
APPEARANCES="light,dark"
PR=""
TITLE="Renders"
LIST=""
STATES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    --appearances) APPEARANCES="$(echo "$2" | tr ' ' ',')"; shift 2 ;;
    --pr) PR="$2"; shift 2 ;;
    --title) TITLE="$2"; shift 2 ;;
    --list) LIST=1; shift ;;
    --*) echo "unknown option $1" >&2; exit 2 ;;
    *) STATES+=("$1"); shift ;;
  esac
done

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
swift build --product github-pr-explorer >/dev/null
SOURCE="$(swift build --show-bin-path)/github-pr-explorer"
BIN="build/render/github-pr-explorer"
mkdir -p build/render "$OUT"
cp "$SOURCE" "$BIN"
# The copy finds the core library's resources (the built-in layouts) beside it, as the debug
# binary does.
ln -sfn "$(dirname "$SOURCE")/github-pr-explorer_GitHubPRExplorerCore.bundle" build/render/github-pr-explorer_GitHubPRExplorerCore.bundle
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
xcrun vtool -set-build-version macos 27.0 "$SDK_VERSION" -replace -output "$BIN" "$BIN" 2>/dev/null
codesign --force --sign - "$BIN" 2>/dev/null

if [[ -n "$LIST" ]]; then
  "$BIN" --render-previews "$OUT" --list
  exit 0
fi

# A render quits on its own. The timeout only guards against a state that never draws.
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT
timeout 300 "$BIN" --render-previews "$OUT" --appearances "$APPEARANCES" ${STATES[@]+"${STATES[@]}"} | tee "$LOG"
FILES=()
while read -r _ file _; do FILES+=("$file"); done < <(grep '^rendered ' "$LOG")

if [[ -n "$PR" ]]; then
  BODY="$(mktemp)"
  ATTACH=()
  {
    echo "$TITLE, drawn offscreen with \`scripts/render-previews.sh\` from the mock world."
    echo
    for file in "${FILES[@]}"; do
      label="$(basename "$file" .png)"
      echo "![${label}](./$(basename "$file"))"
      ATTACH+=(--attach "./$(basename "$file")#${label}")
    done
  } >"$BODY"
  (cd "$OUT" && gh pr comment "$PR" --body-file "$BODY" "${ATTACH[@]}")
  rm -f "$BODY"
fi
