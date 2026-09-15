# Changelog

Supervertaler Sidekick – the free system-wide toolbox. Distributed as the
AutoHotkey script itself rather than as versioned builds, so the headings here
are dates.

This file starts on 2026-09-16. Anything before the entries below is in the git
history rather than here, because reconstructing it after the fact would be
guesswork.

## 2026-09-13

### Added

- **Language packs.** The search sources that belong to one language pair, as data
  rather than as code: `nl-en.json` replaces the separate `nl` and `en` sets in one
  click, and the pack appears as a single submenu inside Web searches, named by its
  pair. MultiSearch became data with them.
- **Double-tap keyboard shortcuts**, an **Add another key** button, and a resizable
  shortcut editor.

## 2026-09-09

### Changed

- **The mark is black.** The three products are told apart by the colour of the
  same mark – blue for Trados, vermillion for memoQ, black for Sidekick, which is
  also the mark on supervertaler.com. Recoloured by draining the saturation and
  remapping the value rather than by flood-filling, so the anti-aliased rim
  survives; all nine frames are mapped against one range taken from the largest, so
  the 16px and the 256px versions are the same black.
- **The tray icon follows the taskbar.** A black disc on a dark taskbar leaves the
  white "Sv" floating, so a dark taskbar gets the mark inverted. The state read is
  `SystemUsesLightTheme` – the taskbar – rather than `AppsUseLightTheme`, which is
  application windows and is commonly set the other way round. Windows broadcasts
  `WM_SETTINGCHANGE` when the theme is switched, so the icon follows without a
  timer polling the registry.

## 2026-09-06

### Changed

- **API keys are shared with the Supervertaler plugins.** The file the plugins
  keep is read first, and the providers window writes to it, so a key rotated in
  one place is rotated everywhere.
