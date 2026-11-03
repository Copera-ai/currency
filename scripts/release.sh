#!/usr/bin/env bash
# Build, sign (Developer ID), notarize and package Copera Currency.
#
# Usage: scripts/release.sh <version> [--build N] [--skip-notarize]
#        (or: make release VERSION=x.y.z [BUILD=N] [SKIP_NOTARIZE=1])
#
# Env:   TEAM_ID         Apple Developer team (default: YN6WU24Q3K)
#        NOTARY_PROFILE  notarytool keychain profile (default: apple-notary)
#        BRANDING_DIR    DMG branding folder (default: Branding/): optional
#                        dmg-background.png (+ @2x) and VolumeIcon.icns
#        DMG_APP_POS / DMG_APPLICATIONS_POS
#                        "x y" icon centers in the styled DMG window
#                        (default: derived from the background size)
#
# Output (build/release/dist): Copera-Currency-<v>.dmg, Copera-Currency-<v>.zip
# (ditto of the stapled app) and checksums.txt. The build number is the git
# commit count by default, so it only ever grows (ready for a Sparkle feed).
set -euo pipefail

usage() {
  echo "usage: scripts/release.sh <version> [--build N] [--skip-notarize]" >&2
  exit 64
}
step() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

VERSION=""
BUILD=""
SKIP_NOTARIZE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --build)
      [[ $# -ge 2 ]] || usage
      BUILD="$2"
      shift 2
      ;;
    --build=*) BUILD="${1#--build=}"; shift ;;
    --skip-notarize) SKIP_NOTARIZE=1; shift ;;
    -h|--help) usage ;;
    -*) echo "unknown option: $1" >&2; usage ;;
    *)
      [[ -z "$VERSION" ]] || usage
      VERSION="$1"
      shift
      ;;
  esac
done
[[ -n "$VERSION" ]] || usage
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must be x.y.z (got \"$VERSION\")"

cd "$(dirname "$0")/.."
ROOT="$PWD"
[[ -n "$BUILD" ]] || BUILD="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || true)"
[[ "$BUILD" =~ ^[0-9]+$ ]] || die "build number must be an integer (got \"$BUILD\"); pass --build N"

NOTARY_PROFILE="${NOTARY_PROFILE:-apple-notary}"
BUNDLE_ID="ai.copera.currency"
APP_NAME="Copera Currency"        # PRODUCT_NAME: "Copera Currency.app"
FILE_BASE="Copera-Currency-$VERSION"
DMG_VOLNAME="Copera Currency"
BRANDING="${BRANDING_DIR:-$ROOT/Branding}"

OUT="$ROOT/build/release"
ARCHIVE="$OUT/CoperaCurrency.xcarchive"
EXPORT="$OUT/export"
DIST="$OUT/dist"
STAGE="$OUT/dmg-stage"
APP="$EXPORT/$APP_NAME.app"
ZIP="$DIST/$FILE_BASE.zip"
DMG="$DIST/$FILE_BASE.dmg"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# Always unregister build products so LaunchServices doesn't list duplicate
# copies. Includes copies that were already deleted (stale registrations survive
# deletion) and xcodebuild's intermediates under DerivedData.
unregister() {
  {
    printf '%s\n' "$ARCHIVE/Products/Applications/$APP_NAME.app" "$APP" "$STAGE/$APP_NAME.app"
    "$LSREGISTER" -dump 2>/dev/null \
      | sed -n "s/^path: *\(.*\/$APP_NAME\.app\) (0x[0-9a-f]*)\$/\1/p" | grep -v '^/Applications/' || true
  } | sort -u | while IFS= read -r p; do
    "$LSREGISTER" -u "$p" >/dev/null 2>&1 || true
  done
}
trap unregister EXIT

# ---- DMG --------------------------------------------------------------------

plain_dmg() {
  hdiutil create -volname "$DMG_VOLNAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
}

# Branded DMG: background (1x + @2x merged into a HiDPI tiff), volume icon and
# icon positions saved by Finder into the volume's .DS_Store. The window matches
# the 1x background size.
styled_dmg() {
  local rw="$OUT/$FILE_BASE-rw.dmg" bg="$BRANDING/dmg-background.png" bg2x="$BRANDING/dmg-background@2x.png"
  local w h mnt app_pos apps_pos
  w="$(sips -g pixelWidth "$bg" | awk '/pixelWidth/ {print $2}')"
  h="$(sips -g pixelHeight "$bg" | awk '/pixelHeight/ {print $2}')"
  [[ "$w" =~ ^[0-9]+$ && "$h" =~ ^[0-9]+$ ]] || return 1
  # Defaults: icons on one row at 27% / 73% of the width (160/440 on a 600x400 background).
  app_pos="${DMG_APP_POS:-$((w * 27 / 100)) $((h * 475 / 1000))}"
  apps_pos="${DMG_APPLICATIONS_POS:-$((w * 73 / 100)) $((h * 475 / 1000))}"
  mkdir -p "$STAGE/.background"
  if [[ -f "$bg2x" ]]; then
    tiffutil -cathidpicheck "$bg" "$bg2x" -out "$STAGE/.background/background.tiff" >/dev/null 2>&1 || return 1
  else
    sips -s format tiff "$bg" --out "$STAGE/.background/background.tiff" >/dev/null || return 1
  fi
  rm -f "$rw"
  hdiutil create -volname "$DMG_VOLNAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$rw" >/dev/null || return 1
  # Default /Volumes mount point (Finder only lays out browsable volumes); use
  # the path hdiutil reports in case the name is taken.
  mnt="$(hdiutil attach "$rw" -readwrite -noverify -noautoopen | sed -n 's:.*\(/Volumes/.*\)$:\1:p' | tail -1)"
  [[ -d "$mnt" ]] || { rm -f "$rw"; return 1; }
  local ok=0
  # shellcheck disable=SC2086 # positions are "x y" pairs
  osascript - "$mnt" "$w" "$h" "$APP_NAME.app" $app_pos $apps_pos <<'OSA' >/dev/null || ok=1
on run argv
  set mnt to item 1 of argv
  set w to (item 2 of argv) as integer
  set h to (item 3 of argv) as integer
  set appItem to item 4 of argv
  set appPos to {(item 5 of argv) as integer, (item 6 of argv) as integer}
  set applicationsPos to {(item 7 of argv) as integer, (item 8 of argv) as integer}
  tell application "Finder"
    set d to (POSIX file mnt as alias)
    open d
    set win to container window of d
    set current view of win to icon view
    set toolbar visible of win to false
    set statusbar visible of win to false
    set bounds of win to {200, 120, 200 + w, 120 + h + 32} -- + title bar
    set opts to icon view options of win
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 13
    set background picture of opts to (POSIX file (mnt & "/.background/background.tiff") as alias)
    set position of item appItem of d to appPos
    set position of item "Applications" of d to applicationsPos
    update d without registering applications
    delay 2
    close win
  end tell
end run
OSA
  # Both hdiutil -srcfolder and Finder's layout pass drop .VolumeIcon.icns, so add
  # it last; FinderInfo with only kHasCustomIcon (0x0400 in fdFlags) enables it.
  if [[ "$ok" == 0 && -f "$BRANDING/VolumeIcon.icns" ]]; then
    cp "$BRANDING/VolumeIcon.icns" "$mnt/.VolumeIcon.icns"
    xattr -wx com.apple.FinderInfo "$(printf '%064d' 0 | sed 's/^\(.\{16\}\)00/\104/')" "$mnt"
  fi
  rm -rf "$mnt/.fseventsd"
  sync
  sleep 2
  hdiutil detach "$mnt" >/dev/null 2>&1 || { sleep 3; hdiutil detach -force "$mnt" >/dev/null; }
  [[ "$ok" == 0 ]] || { rm -f "$rw"; return 1; }
  rm -f "$DMG"
  hdiutil convert "$rw" -format UDZO -o "$DMG" >/dev/null || { rm -f "$rw"; return 1; }
  rm -f "$rw"
}

# ---- Preflight --------------------------------------------------------------

step "Preflight"
command -v xcodegen >/dev/null 2>&1 || die "xcodegen not found (brew install xcodegen)"
for tool in xcodebuild xcrun codesign ditto hdiutil lipo shasum; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool not found (install Xcode and select it with xcode-select)"
done
[[ -f "$ROOT/project.yml" ]] || die "project.yml not found in $ROOT"

TEAM_ID="${TEAM_ID:-YN6WU24Q3K}"
[[ "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || die "TEAM_ID must be a 10-character Apple team id"
echo "team id: set (not printed)"

if [[ "$SKIP_NOTARIZE" == 0 ]]; then
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 || die \
"notary profile '$NOTARY_PROFILE' not found or not usable. Run in your own Terminal:
  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <apple-id> --team-id $TEAM_ID
(use an app-specific password), then re-run. --skip-notarize skips notarization for local testing."
  echo "notary profile: $NOTARY_PROFILE"
fi

# ---- Build ------------------------------------------------------------------

step "Generating project"
xcodegen generate --spec project.yml

step "Archiving $APP_NAME $VERSION ($BUILD), arm64"
rm -rf "$ARCHIVE" "$EXPORT" "$STAGE" "$DIST"
mkdir -p "$OUT" "$DIST"
# project.yml sets DEVELOPMENT_TEAM = $(COPERA_TEAM_ID), so the team only lives
# on this command line. -quiet also keeps xcodebuild from echoing it.
xcodebuild archive -project CoperaCurrency.xcodeproj -scheme CoperaCurrency -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" \
  -derivedDataPath "$OUT/DerivedData" -allowProvisioningUpdates \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO COPERA_TEAM_ID="$TEAM_ID" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
  -quiet

step "Exporting (Developer ID)"
cat >"$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>developer-id</string>
<key>signingStyle</key><string>automatic</string>
<key>teamID</key><string>$TEAM_ID</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates -quiet

step "Verifying app"
[[ -d "$APP" ]] || die "export did not produce $APP"
codesign --verify --deep --strict --verbose=2 "$APP"
# Capture output first: `grep -q` in a pipe would SIGPIPE the writer under pipefail.
SIGINFO="$(codesign -dvv "$APP" 2>&1)"
[[ "$SIGINFO" == *"Authority=Developer ID Application"* ]] || die "app is not Developer ID signed"
[[ "$SIGINFO" == *"(runtime)"* ]] || die "app is missing the hardened runtime"
plist() { /usr/libexec/PlistBuddy -c "Print $1" "$APP/Contents/Info.plist"; }
[[ "$(plist CFBundleIdentifier)" == "$BUNDLE_ID" ]] || die "bundle id is not $BUNDLE_ID"
[[ "$(plist CFBundleShortVersionString)" == "$VERSION" ]] || die "built version does not match $VERSION"
[[ "$(plist CFBundleVersion)" == "$BUILD" ]] || die "built build number does not match $BUILD"
ARCHS_BUILT="$(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"
[[ "$ARCHS_BUILT" == "arm64" ]] || die "expected an arm64-only binary (got: $ARCHS_BUILT)"

step "Creating $(basename "$DMG")"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
if [[ -f "$BRANDING/dmg-background.png" ]]; then
  if styled_dmg; then
    echo "styled DMG (background from $BRANDING)"
  else
    echo "(styled DMG failed: falling back to a plain one)"
    rm -rf "$STAGE/.background"
    plain_dmg
  fi
else
  echo "(no $BRANDING/dmg-background.png: plain DMG)"
  plain_dmg
fi
rm -rf "$STAGE"

# DMG signing needs a local identity; the cloud-managed Developer ID cert has none.
# An unsigned DMG still notarizes and staples (Gatekeeper trusts the ticket).
IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -n 1)"
if [[ -n "$IDENTITY" ]]; then
  step "Signing DMG"
  codesign --force --sign "$IDENTITY" --timestamp "$DMG"
else
  echo "(no local Developer ID identity: DMG left unsigned; the app inside is signed)"
fi

if [[ "$SKIP_NOTARIZE" == 1 ]]; then
  echo "--skip-notarize: skipping notarization, stapling and Gatekeeper checks"
else
  # One submission covers the DMG and the app inside it, so both can be stapled.
  step "Notarizing"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  step "Stapling"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  step "Gatekeeper"
  spctl -a -t exec -vv "$APP"
  if [[ -n "$IDENTITY" ]]; then
    spctl -a -t open --context context:primary-signature -vv "$DMG"
  fi
fi

step "Checking DMG contents"
MNT="$(mktemp -d "${TMPDIR:-/tmp}/copera-currency-dmg.XXXXXX")"
hdiutil attach "$DMG" -nobrowse -readonly -noautoopen -mountpoint "$MNT" >/dev/null
dmg_ok=1
[[ -d "$MNT/$APP_NAME.app" ]] || dmg_ok=0
[[ -L "$MNT/Applications" && "$(readlink "$MNT/Applications")" == /Applications ]] || dmg_ok=0
if [[ "$dmg_ok" == 1 && "$SKIP_NOTARIZE" == 0 ]]; then
  spctl -a -t exec -vv "$MNT/$APP_NAME.app" || dmg_ok=0
fi
hdiutil detach "$MNT" >/dev/null 2>&1 || hdiutil detach -force "$MNT" >/dev/null
rmdir "$MNT" 2>/dev/null || true
[[ "$dmg_ok" == 1 ]] || die "DMG does not contain a valid $APP_NAME.app and an Applications link"
echo "DMG has $APP_NAME.app and Applications -> /Applications"

# Built from the stapled app, so it passes Gatekeeper offline on first launch
# (also the archive a future Sparkle feed would serve).
step "Creating $(basename "$ZIP")"
ditto -c -k --keepParent "$APP" "$ZIP"

step "Checksums"
(cd "$DIST" && shasum -a 256 "$(basename "$DMG")" "$(basename "$ZIP")" >checksums.txt)
cat "$DIST/checksums.txt"

step "Summary"
echo "Version:  $VERSION ($BUILD)"
echo "DMG:      $DMG"
echo "Zip:      $ZIP"
echo "Sums:     $DIST/checksums.txt"
[[ "$SKIP_NOTARIZE" == 0 ]] || echo "NOT notarized (--skip-notarize): local testing only"
