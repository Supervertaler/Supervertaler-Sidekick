# Supervertaler Sidekick

**The system-wide toolbox for translators.**

Part of the Supervertaler family, alongside [Supervertaler for Trados](https://github.com/Supervertaler/Supervertaler-for-Trados) and Supervertaler for memoQ. Those work inside your CAT tool; Sidekick works everywhere else.

Select text anywhere in Windows — in a CAT tool, a browser, a PDF, an email —
press `` ` ``, and act on it: look it up across a dozen terminology sources,
run an AI prompt over it, convert its case, wrap it in quotes, or paste a
snippet in its place.

Built in [AutoHotkey v2](https://www.autohotkey.com/docs/v2/). No dependencies,
no runtime, no install step.

<img width="1280" height="1211" alt="image" src="https://github.com/user-attachments/assets/3d8eef53-3c1c-487e-a4b3-9b12e33cedb2" />

<img width="2560" height="1440" alt="image" src="https://github.com/user-attachments/assets/fb5cce8d-7f13-47e1-b238-3cb4f03e53ba" />


---

## What it does

| | |
|---|---|
| 🪟 **One window** | `` ` `` opens the clipboard and the menu side by side. Arrows cross between them, folders open and close, `Alt+1`–`9` jumps straight to a section, `Ctrl+↑`/`↓` steps between them, and typing filters both panes at once. |
| ⌘ **The palette** | `Ctrl+Alt+Space`. One search box over *everything* — clipboard history, snippets, searches, AI prompts, bookmarks and conversions at once. Type a few letters, press Enter. The menu is still there for browsing. |
| 🌐 **QuickTrans** | `Ctrl+Alt+T`. A tab in the same window: translate the selection with several engines at once. Machine translation from MyMemory, Google, Microsoft, ModernMT and DeepL; LLMs from Claude, OpenAI, Gemini, Mistral, DeepSeek, OpenRouter, a local Ollama, or any OpenAI-compatible endpoint you point it at. Press `1`–`9` to insert one. The menu stays beside it, so you can translate, insert, then run a menu action without leaving. MyMemory needs no API key, so it works before anything is configured; keys and models for the rest are set in **Settings → AI providers & keys**, which asks each provider which models your key can actually use. |
| 📝 **Scratchpad** | `Ctrl+Alt+N`. A third tab in the same window, and a key that lands in it with the caret already at the end of the note, so a thought can be typed the moment it arrives. Plain text, no fields to fill in first, and it saves itself a moment after you stop typing – and again when the window closes. It lives in `data\scratchpad.txt`, so Notepad, grep and your backups can all read it. |
| 🎚️ **Opens where you want it** | The plain `` ` `` shortcut opens on whichever tab suits you – Clipboard, QuickTrans, Scratchpad, or whichever one you were last on. The **Opens on:** box sits on the tab strip beside the tabs, not in a settings dialog. `Ctrl+Alt+T` and `Ctrl+Alt+N` still go straight to their own tab whatever it says. |
| 🔎 **Text size** | `Ctrl+=` and `Ctrl+-` inside the window, `Ctrl+0` back to normal. It grows the text you actually read and write – the note, the QuickTrans source box, the translations – and leaves the clipboard list, the menu tree and the labels the size they are. Remembered between sessions, so the laptop screen and the big monitor each get what suits them. |
| 🔍 **Web searches** | Select a term, pick a source. IATE, Juremy, JurLex, Van Dale, Linguee, ProZ, Reverso, BabelNet, Wikipedia, Wiktionary, Google Patents and more. Every source follows the language pair you set, so one IATE entry serves every direction. MultiSearch fires a whole batch at once, each in its own tab of a fresh browser window. A **language pack** is everything for one pair in one click – Dutch ⇄ English ships – and only the pack for the pair you are in is shown. |
| 🤖 **AI actions** | Run any prompt over the selection: translate, proofread, rephrase, summarise, expand, localise. Provider-agnostic — Claude by default, OpenAI if you prefer — and non-blocking, so the rest of Sidekick keeps working while a request is in flight. |
| 📋 **Snippet library** | Boilerplate, standard replies, special characters, regex patterns, dictionary citations — inserted at the cursor. |
| 🔤 **Text conversions** | Upper / lower / title / sentence case, curly quotes, brackets, HTML bold, soft-hyphen removal, straight-to-curly quote conversion. |
| 🔖 **Bookmarks** | Online and local. Forums, docs, reference sites, folders you keep reopening. |
| 📎 **Clipboard manager** | Searchable history that survives restarts, pasted straight back into the window you came from. Entries you've already used are ticked and greyed, so you can work down a list of terms without losing your place. `Ctrl+Alt+C` |
| ⌨️ **Keyboard shortcuts** | Every built-in key can be changed, given a second key, or limited to one program, and you can attach a key to anything the menu does. A key can also be a quick double tap of Ctrl, Shift or Alt – tap Ctrl twice in memoQ or Trados to confirm a segment, say. All from **Keyboard shortcuts…**, no editing of ini files. |

Everything is reachable in two keystrokes: `` ` `` then an accelerator letter.

---

## Installing

1. Install [AutoHotkey v2](https://www.autohotkey.com/) (v2.0 or later — **not** v1).
2. Clone this repository.
3. Run `Sidekick.ahk`.

On first run, Sidekick copies the starter menu from `data.example/` into
`data/` and opens with a working set of searches and conversions. From there
you make it yours.

> Sidekick requests administrator rights on launch. This is deliberate: without
> them, its hotkeys are ignored by any window that is itself elevated.

### Setting up AI

Copy `settings.example.ini` to `settings.ini` and add a key:

```ini
[AI]
Provider=anthropic     ; or: openai
Model=                 ; blank = the provider's default
Effort=medium          ; low | medium | high | xhigh | max  (Anthropic only)

[Keys]
anthropic=sk-ant-...
```

`settings.ini` is gitignored. Switching vendor is one line — the request and
response shapes for each live in `lib/ai.ahk`, so adding a third provider means
one entry in `AI_Providers()`, not a rewrite.

---

## Making it yours

**Nothing personal lives in the script.** The menu is built at run time from
`data/menu.json`. That file is gitignored, so your snippets, bookmarks,
credentials and client boilerplate stay on your machine — you can fork, share
or publish the code without scrubbing anything first.

To change what's on the menu, open **Edit library…** (the second item). Add,
edit, delete and reorder entries; hit **Save & rebuild** and the menu updates
without restarting.

### Entry types

Each menu entry has a *type* that decides what it does with your selection:

| Type | What it does |
|---|---|
| `text` | Types out literal text |
| `keys` | Sends a key combination, e.g. `^+*` |
| `url` | Opens a web address |
| `run` | Launches a file or folder |
| `search` | Copies the selection and opens a URL, with `{q}` replaced by it and `{sl}`/`{tl}` by the language pair |
| `multisearch` | The same for several URLs, one per line, all opened at once in a new browser window |
| `ai` | Runs an AI prompt over the selection |
| `action` | Calls a built-in function |
| `submenu` | Holds other entries |
| `heading` / `separator` | Structure only |

Adding a new terminology source is one `search` entry:

```json
{
  "kind": "search",
  "label": "IATE",
  "url": "https://iate.europa.eu/search/byUrl?term={q}&sl={sl}&tl={tl}"
}
```

The selection is UTF-8 percent-encoded before substitution, so terms containing
`&`, `?`, `+` or accented characters work correctly. `{sl}` and `{tl}` are the
language pair — set in the QuickTrans tab, in Settings → Language pair…, or
with Swap languages — as two-letter codes; `{sl_full}` gives the name
(`dutch`), `{sl3}` the ISO 639-2/T code (`nld`), `{sl3b}` the bibliographic one
(`dut`), `{sl_upper}` the capitals. A site with no code in its URL, such as
Van Dale's dictionary ids, takes a `by_pair` map of `"nl-en": url` instead.

An AI action is just as short — and every prompt is editable in the same place
as your snippets:

```json
{
  "kind": "ai",
  "label": "Translate (Dutch to English)",
  "prompt": "Give ten possible translations, technical to general.",
  "effort": "high"
}
```

Optional per-entry overrides: `system`, `model`, `provider`, `effort`,
`maxtokens`.

---

## Layout

```
Sidekick.ahk        hotkeys, text conversions, local searches
lib/
  mainwindow.ahk      the backtick window (clipboard + menu)
  quicktrans.ahk      multi-engine translation of the selection
  palette.ahk         the search-everything window
  menu_builder.ahk    builds the menu from data
  ai.ahk              provider-agnostic AI requests
  clipboard.ahk       clipboard history
  editor.ahk          the Library Editor
  data.ahk            reads and writes the JSON
  jxon.ahk            JSON parser (third-party)
data/                 your content — gitignored
data.example/         generic starter set, shipped
settings.ini          API keys — gitignored
```

---

## Roadmap

- **Image clips** — the clipboard history is text-only. AutoHotkey has no
  practical way to thumbnail and persist bitmaps; the on-disk format leaves
  room for them.
- **Streaming AI replies** — show the answer as it arrives rather than after
  the full response lands.

---

## Credits

The AI request handling began life in
[ChatGPT-AutoHotkey-Utility](https://github.com/kdalanon/ChatGPT-AutoHotkey-Utility)
by kdalanon, and has since been rewritten as the provider-agnostic layer in
`lib/ai.ahk`.

JSON parsing uses [cJson/Jxon](https://github.com/cocobelgica/AutoHotkey-JSON).

---

By [Michael Beijer](https://michaelbeijer.co.uk/), Dutch→English patent and
technical translator. Related work:
[Supervertaler](https://github.com/michaelbeijer/Supervertaler) ·
[SuperLookup](https://github.com/michaelbeijer/superlookup) ·
[WordCounter](https://github.com/michaelbeijer/WordCounter)
