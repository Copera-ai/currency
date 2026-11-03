# Copera Currency branding

Every icon comes from `mark.svg`: two overlapping coins, the front one
engraved with an exchange glyph (⇄). It is drawn on the 1024 pt Icon Composer
canvas as three even-odd paths (`back`, `rim`, `face`), and each path becomes
one Liquid Glass layer. Regenerate everything with:

```sh
brew install librsvg resvg   # once
Branding/make-icons.sh       # add --flat to skip the Xcode renders
```

## Files

| Output | Source | Notes |
| --- | --- | --- |
| `CoperaCurrency/AppIcon.icon` | `icon.json` (hand-edited) + generated `Assets/{back,rim,face}.svg` | Icon Composer package; open it in Icon Composer to tweak. Two groups: the front coin (`face` + `rim`, opaque white glass) above the back coin (`back`, 70% white, translucent glass). Light and dark gradients come from `fill-specializations`; the system derives tinted and clear. Picked up by `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`. actool also emits an `AppIcon.icns` fallback for macOS 14/15. |
| `preview/AppIcon.svg`, `preview/AppIcon-1024.png` | `mark.svg` | Flat preview without Liquid Glass (rsvg-convert). Its colors are copied from `icon.json`, so keep the two in sync. |
| `preview/AppIcon-rendered-1024.png` | `AppIcon.icon` via `render-icon.swift` | The real macOS render: actool compiles the icon into a throwaway bundle, then IconServices draws it. |
| `preview/AppIcon-rendered-dark-1024.png` | `AppIcon.icon` via Icon Composer's `ictool` | Dark appearance render, padded to the same 1024 grid. |
| `VolumeIcon.icns` | `AppIcon.icon` via `render-icon.swift` | DMG volume icon: the app icon as macOS renders it. |
| `menubar/CurrencyMark.svg`, `.pdf` | drawn in `make-icons.sh` | 18 × 18 pt template glyph (black on transparent). It is drawn for the menu bar, not scaled down from the app icon: the back coin is a 1.5 pt outline, the front coin is solid with the ⇄ knocked out. For an asset catalog, use the PDF with *Preserve Vector Data* and *Render As: Template Image*. |
| `dmg-background.png`, `dmg-background@2x.png` | `dmg-background.svg` | 660 × 400 pt DMG window background, rendered with resvg and SF Pro. The release script merges both into a multi-resolution TIFF, which Finder needs for Retina. |

## Brand colors

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| Accent ("Copera Emerald") | `#0B8A5F` | `#2CC98F` | App UI tint: buttons, selection, links, positive changes. Light has 4.4:1 contrast with white; dark has 7.8:1 against `#1E1E1E`. |
| Icon gradient, top | `#22B07E` | `#17735A` | `icon.json` background |
| Icon gradient, bottom | `#0A3F4A` | `#03201C` | `icon.json` background (deep petrol) |
| Glyph | `#FFFFFF` | `#FFFFFF` | Icon layers (the system tints these for the tinted and clear styles) |

## DMG layout

The background has no icons of its own; Finder draws them at these positions.

- Window content size: **660 × 400 pt** (icon view, with the toolbar, sidebar and status bar hidden).
- Icon size **128 pt**, text size **13 pt**.
- `Copera Currency.app` centered at **(160, 190)**; the `Applications` link centered at **(500, 190)**.
  Finder icon positions are the icon's center, with the origin at the top left of the window content.
- The background draws a faint 160 × 190 pt slot behind each icon and its label (x 80 and 420, y 100), with an emerald arrow from x 266 to x 393 at y 190 and a caption centered at y 350.
- Volume icon: `VolumeIcon.icns`, copied to `.VolumeIcon.icns` at the volume root and marked with the custom-icon Finder flag (`SetFile -a C`).
