#!/usr/bin/env bash
# Builds github-pr-explorer.app into ./build and signs it. It never installs or launches it.
#
# Modeled on mac-os-agent's scripts/bundle.sh. Sparkle updates, scripts/release.sh, and the app
# icon are left out for now: ticket MAC-47 adds them. Until then the bundle has no icon, no
# updater, and no release path.
#
# Environment, all optional:
#   GITHUB_PR_EXPLORER_VERSION           The version to show, such as 1.2.0. Defaults to the
#                                        latest v* tag, or 0.1 without one.
#   GITHUB_PR_EXPLORER_SIGNING_IDENTITY  The signing identity. See "Sign" below for the default.
set -euo pipefail
cd "$(dirname "$0")/.."

# Use full Xcode for SwiftUI without changing the global xcode-select setting.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

swift build -c release --arch arm64 --product github-pr-explorer
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

APP="build/github-pr-explorer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/github-pr-explorer" "$APP/Contents/MacOS/github-pr-explorer"

# The core library's resources: the built-in layout files. SwiftPM puts them in a bundle next
# to the binary. Inside an app, its generated accessor looks in Contents/Resources first.
RESOURCES_BUNDLE="github-pr-explorer_GitHubPRExplorerCore.bundle"
if [[ ! -d "$BIN_DIR/$RESOURCES_BUNDLE" ]]; then
  echo "error: $BIN_DIR/$RESOURCES_BUNDLE is missing, so the app would have no built-in layouts" >&2
  exit 1
fi
ditto "$BIN_DIR/$RESOURCES_BUNDLE" "$APP/Contents/Resources/$RESOURCES_BUNDLE"

# SwiftPM writes the deployment target into the binary's SDK field. macOS reads that field
# to decide whether to run the app in a compatibility mode for older apps, so stamp the
# SDK the app was really built with.
MIN_OS=27.0
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
xcrun vtool -set-build-version macos "$MIN_OS" "$SDK_VERSION" -replace \
  -output "$APP/Contents/MacOS/github-pr-explorer" "$APP/Contents/MacOS/github-pr-explorer"
STAMPED="$(xcrun vtool -show-build "$APP/Contents/MacOS/github-pr-explorer" | awk '$1 == "sdk" { print $2 }')"
if [[ "$STAMPED" != "$SDK_VERSION" ]]; then
  echo "error: the binary is stamped with SDK '$STAMPED', expected '$SDK_VERSION'" >&2
  exit 1
fi

GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  GIT_COMMIT="$GIT_COMMIT-dirty"
fi
# The version comes from the latest release tag. The build number is the number of commits,
# which only grows on main.
LATEST_TAG="$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"
VERSION="${GITHUB_PR_EXPLORER_VERSION:-${LATEST_TAG#v}}"
VERSION="${VERSION:-0.1}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

# A window-first app: no LSUIElement, so it has a Dock icon and a menu bar.
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>github-pr-explorer</string>
  <key>CFBundleDisplayName</key><string>GitHub PR Explorer</string>
  <key>CFBundleIdentifier</key><string>dev.lubelski.github-pr-explorer</string>
  <key>CFBundleExecutable</key><string>github-pr-explorer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>GitHubPRExplorerGitCommit</key><string>$GIT_COMMIT</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_OS</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Sign. The identity is the first of these that exists:
#   1. GITHUB_PR_EXPLORER_SIGNING_IDENTITY, when it is set.
#   2. A Developer ID Application certificate in the keychain.
#   3. This Mac's self-signed "github-pr-explorer development" certificate, if the owner made one.
#   4. Ad hoc.
DEVELOPER_ID="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/ { print $2; exit }')"
if [[ -n "${GITHUB_PR_EXPLORER_SIGNING_IDENTITY:-}" ]]; then
  IDENTITY="$GITHUB_PR_EXPLORER_SIGNING_IDENTITY"
elif [[ -n "$DEVELOPER_ID" ]]; then
  IDENTITY="$DEVELOPER_ID"
elif security find-certificate -c "github-pr-explorer development" >/dev/null 2>&1; then
  IDENTITY="github-pr-explorer development"
else
  IDENTITY="-"
fi
SIGN=(codesign --force --sign "$IDENTITY")
if [[ "$IDENTITY" == *"Developer ID Application"* ]]; then
  # Notarization needs the hardened runtime and a secure timestamp.
  SIGN+=(--options runtime --timestamp)
fi
"${SIGN[@]}" "$APP"
codesign --verify --deep --strict "$APP"
if [[ "$IDENTITY" == "-" ]]; then
  echo "Signed ad hoc."
else
  echo "Signed with \"$IDENTITY\""
fi
echo "Built $APP, version $VERSION ($BUILD_NUMBER), commit $GIT_COMMIT"
