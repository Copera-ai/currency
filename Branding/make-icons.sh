#!/usr/bin/env bash
# Regenerates every Copera Currency icon asset from Branding/mark.svg (two
# overlapping coins, the front one engraved with an exchange glyph).
#
#   CoperaCurrency/AppIcon.icon/Assets/{back,rim,face}.svg  app icon layers (icon.json is hand-edited)
#   Branding/preview/AppIcon.svg, AppIcon-1024.png          flat preview for review (rsvg-convert)
#   Branding/menubar/CurrencyMark.{svg,pdf}                 18 pt menu bar template glyph
#   Branding/dmg-background.png, dmg-background@2x.png      DMG window background (resvg + SF Pro)
#   Branding/preview/AppIcon-rendered-1024.png              Liquid Glass render (actool + IconServices)
#   Branding/preview/AppIcon-rendered-dark-1024.png         dark appearance render (ictool)
#   Branding/VolumeIcon.icns                                DMG volume icon, the rendered app icon
#
# Usage: Branding/make-icons.sh [--flat]
#   --flat  skip the Xcode renders (rendered previews and VolumeIcon.icns).
# Requires `brew install librsvg resvg`; the renders need Xcode 26+ (actool, ictool).
set -euo pipefail

BRANDING="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$BRANDING")"
ICON="$ROOT/CoperaCurrency/AppIcon.icon"
MENUBAR="$BRANDING/menubar"
PREVIEW="$BRANDING/preview"
RENDER=1
[[ "${1:-}" == "--flat" ]] && RENDER=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for tool in rsvg-convert resvg; do
  command -v "$tool" >/dev/null || { echo "missing $tool: brew install librsvg resvg" >&2; exit 1; }
done

# layer <id>: the path data of one layer in mark.svg.
layer() {
  local d
  d="$(sed -n "s/.*id=\"$1\".* d=\"\([^\"]*\)\".*/\1/p" "$BRANDING/mark.svg")"
  [[ -n "$d" ]] || { echo "no path with id=\"$1\" in mark.svg" >&2; exit 1; }
  printf '%s' "$d"
}
BACK="$(layer back)"
RIM="$(layer rim)"
FACE="$(layer face)"

# App icon layers: one SVG per layer on the 1024 pt Icon Composer canvas. The
# layer colors, opacities, groups and glass settings come from icon.json.
mkdir -p "$ICON/Assets"
for name in back rim face; do
  case "$name" in
    back) d="$BACK" ;;
    rim) d="$RIM" ;;
    face) d="$FACE" ;;
  esac
  cat >"$ICON/Assets/$name.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <path fill="#fff" fill-rule="evenodd" d="$d"/>
</svg>
EOF
done

# Flat preview: the icon.json light gradient and layer opacities inside the
# macOS squircle (824 pt of the 1024 pt grid). No Liquid Glass; see the renders.
# Keep these colors in sync with icon.json.
mkdir -p "$PREVIEW"
cat >"$PREVIEW/AppIcon.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#22B07E"/>
      <stop offset="1" stop-color="#0A3F4A"/>
    </linearGradient>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="12" stdDeviation="16" flood-color="#021A17" flood-opacity="0.35"/>
    </filter>
  </defs>
  <rect x="100" y="100" width="824" height="824" rx="185" fill="url(#bg)"/>
  <g transform="translate(100 100) scale(0.8046875)" fill="#fff" fill-rule="evenodd" filter="url(#shadow)">
    <path fill-opacity="0.7" d="$BACK"/>
    <path d="$RIM"/>
    <path d="$FACE"/>
  </g>
</svg>
EOF
rsvg-convert -w 1024 -h 1024 -o "$PREVIEW/AppIcon-1024.png" "$PREVIEW/AppIcon.svg"

# Menu bar: an 18 x 18 pt template image (black on transparent) drawn for the
# menu bar rather than scaled down from the app icon: the back coin as a 1.5 pt
# outline (reads as a "C"), the front coin solid with the exchange glyph knocked
# out. The gap around the front coin is an even-odd clip path (masks don't
# survive the PDF round trip into template images).
mkdir -p "$MENUBAR"
cat >"$MENUBAR/CurrencyMark.svg" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="18pt" height="18pt" viewBox="0 0 18 18">
  <defs><clipPath id="gap"><path clip-rule="evenodd" d="M0 0h18v18H0z M3.85 11.05A7.2 7.2 0 1 0 18.25 11.05A7.2 7.2 0 1 0 3.85 11.05Z"/></clipPath></defs>
  <circle cx="5.85" cy="5.85" r="4.25" fill="none" stroke="#000" stroke-width="1.5" clip-path="url(#gap)"/>
  <path fill="#000" fill-rule="evenodd" d="M4.95 11.05A6.1 6.1 0 1 0 17.15 11.05A6.1 6.1 0 1 0 4.95 11.05Z
    M7.39 9.214Q7.39 8.61 7.994 8.61L12.236 8.61Q12.758 8.61 12.758 8.088L12.758 7.973Q12.758 7.451 13.138 7.808L14.438 9.026Q14.71 9.281 14.438 9.536L13.138 10.754Q12.758 11.111 12.758 10.589L12.758 10.474Q12.758 9.952 12.236 9.952L7.994 9.952Q7.39 9.952 7.39 9.348Z
    M14.71 12.886Q14.71 13.49 14.106 13.49L9.864 13.49Q9.342 13.49 9.342 14.012L9.342 14.127Q9.342 14.649 8.962 14.292L7.662 13.074Q7.39 12.819 7.662 12.564L8.962 11.346Q9.342 10.989 9.342 11.511L9.342 11.626Q9.342 12.148 9.864 12.148L14.106 12.148Q14.71 12.148 14.71 12.752Z"/>
</svg>
EOF
rsvg-convert -f pdf -o "$MENUBAR/CurrencyMark.pdf" "$MENUBAR/CurrencyMark.svg"

# DMG background (660 x 400 pt window); the release script merges both into a
# HiDPI TIFF. SF Pro is passed explicitly so the caption matches Finder.
FONT=(--use-font-file /System/Library/Fonts/SFNS.ttf)
resvg "${FONT[@]}" -w 660 "$BRANDING/dmg-background.svg" "$BRANDING/dmg-background.png"
resvg "${FONT[@]}" -w 1320 "$BRANDING/dmg-background.svg" "$BRANDING/dmg-background@2x.png"

if [[ "$RENDER" == 1 ]]; then
  # The real Liquid Glass rendering of AppIcon.icon, as macOS draws it.
  swift "$BRANDING/render-icon.swift" "$ICON" "$TMP/VolumeIcon.iconset"
  cp "$TMP/VolumeIcon.iconset/icon_512x512@2x.png" "$PREVIEW/AppIcon-rendered-1024.png"
  iconutil -c icns -o "$BRANDING/VolumeIcon.icns" "$TMP/VolumeIcon.iconset"

  # Dark appearance (IconServices only serves the light one to a CLI process),
  # via Icon Composer's ictool (not `xcrun ictool`, which is actool's). It
  # renders the squircle full bleed; pad it onto the same 1024 grid.
  ICTOOL="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
  "$ICTOOL" "$ICON" --export-preview macOS Dark 824 824 1 -45 "$TMP/dark.png" >/dev/null
  sips -p 1024 1024 "$TMP/dark.png" --out "$PREVIEW/AppIcon-rendered-dark-1024.png" >/dev/null
fi

echo "icons regenerated"
