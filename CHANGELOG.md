# Changelog

All notable changes to Copera Currency. Each `## <version>` section is used as the
GitHub Release notes and the in-app (Sparkle) update notes.

## 1.0.1

- **Real-time fiat rates**: fiat currencies now use Coinbase's live exchange rates instead of a once-a-day snapshot, so USD/BRL and friends match what your bank and Google show. The daily source remains as a fallback.
- **Faster refresh**: new 15- and 30-second intervals (30 seconds is the new default), and opening the popover catches up immediately.
- **Charts end live**: fiat charts now finish at the current rate instead of this morning's snapshot.

## 1.0.0

- **Native Liquid Glass design** for macOS 26: a rebuilt popover and Settings window, Light/Dark/System appearance and six accent colors.
- **Live rates in the menu bar**: one item per pair, shown as pair, symbol, flag or value only, with an optional up/down arrow.
- **Real 24h change**: crypto uses Coinbase's 24-hour move, fiat compares today's rates with yesterday's.
- **Charts**: a sparkline on every pair, and a detailed chart with 24H, 7D, 30D and 90D ranges when you expand it.
- **170+ currencies**: 150+ fiat currencies and popular crypto assets, with flags, names and a searchable picker.
- **Converter**: type an amount (simple math like `250*4` works), swap directions, and copy the result with ⌘C.
- **Pairs your way**: favorite, reorder by dragging, choose which pairs appear in the menu bar, and add pairs from the popover or Settings.
- **Reliable refresh**: rates update every 1 to 60 minutes and right after waking from sleep or reconnecting; cached rates stay visible offline.
- **Keyboard friendly**: an optional global shortcut opens the converter, and arrow keys move through pairs and currencies.
- Open at login and automatic updates.
