# Changelog

Supervertaler Sidekick – the free system-wide toolbox. Distributed as the
AutoHotkey script itself rather than as versioned builds, so the headings here
are dates.

This file starts on 2026-09-16. Anything before the entries below is in the git
history rather than here, because reconstructing it after the fact would be
guesswork.

## 2026-10-17

### Added

- **Text size buttons on the QuickTrans tab.** A small **−** and **+** at the right
  end of the Source line, for the mouse: the same steps as `Ctrl+-` and `Ctrl+=`,
  remembered the same way, and they grow the note on the Scratchpad tab too. After
  a click the focus goes back to the selected translation, so `1`–`9` and Enter
  still insert.

### Changed

- **Searches open in your default browser.** Every web search in the starter menu,
  Google this! (`Ctrl+/`) and Microsoft Terminology Search used to open Microsoft
  Edge whatever browser you use.

- **A tidier starter menu for new installs.** The menu a first run copies into
  `data\` loses what only made sense on the machine it came from: the voice-command
  notes, the AutoCorrect entry, a regex placeholder, the Dutch–English translation
  prompts (QuickTrans does translation), Localize, the GitHub-issue summary, the
  dtSearch and LogiTerm searches, the Oxford Premium search, "Edit Sidekick.ahk",
  and the hints naming text expansions a new install does not have. The HTML link
  snippet is now a plain template. A menu you already have is never changed.

- **Model lists come in two tiers, as in Supervertaler for Trados.** Each
  engine's dropdown in **AI providers & keys** now opens on the few models worth
  recommending, the same short list the Trados plugin shows, and picking one
  shows its verdict and price on the status line. **Show all models** adds
  everything the provider lists for your key; **Models** beside an engine does
  the same for that one engine. A provider's own list runs to dozens of dated
  snapshots and previews, which was all the dropdown used to show. Show all
  models replaces the **Fetch all models** button, which it does the work of.
  The short list is a copy of Trados's, so it changes when that one does.

## 2026-09-19

### Added

- **Scratchpad.** A third tab beside Clipboard and QuickTrans, and `Ctrl+Alt+N` to
  land in it with the caret already at the end of the note. Plain text in
  `data\scratchpad.txt`; it saves itself a beat after typing stops, when the window
  closes, and when the script exits or reloads. A hand edit made while Sidekick is
  running is picked up on the way into the tab, so typing cannot silently overwrite
  it, and a note that cannot be read is never saved over.

- **Text size, on the keys a browser uses.** `Ctrl+=` and `Ctrl+-` in the main
  window, `Ctrl+0` back to 9pt, remembered in `settings.ini`. It is not a zoom of
  the window: what grows is the text you sit and read and write – the note, the
  QuickTrans source box and the translations – while the clipboard list, the menu
  tree, the labels and the buttons stay the size they are. The QuickTrans tab
  measures its boxes in lines of that text, so a translation still gets as many
  lines as it needs at any size.

- **The tab the window opens on is a choice.** Clipboard, QuickTrans, Scratchpad
  or "last used", from an **Opens on:** box that sits in the spare space on the tab
  strip rather than in a settings dialog. It applies to the plain shortcut only –
  the QuickTrans and Scratchpad keys name the tab they want and always get it – and
  the box hides itself rather than sitting on top of the tabs when the window is
  too narrow for both.

### Fixed

- **The Scratchpad box hung past the bottom of its tab.** It was built from the
  QuickTrans tab's first row, which starts lower than the tab body does. It now
  takes the same rectangle as the clipboard list, read from it rather than written
  down a second time.

- **Keys typed in a text box arrive in order.** The window caught digits, arrows,
  Home/End and Enter and sent them on again, which put them back a beat late –
  typing "7 copies" into the QuickTrans source box could produce "  copies7". They
  are now registered under a condition instead, so while the caret is in the note or
  the source box they are not hooked at all. Home, End and → no longer jump into the
  menu tree from the source box either, and `Ctrl+Enter` only translates on the tab
  that has something to translate.

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
