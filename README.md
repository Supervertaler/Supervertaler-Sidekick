# Beijer.bot

**A keyboard-driven command palette for translators.**

Select text anywhere in Windows — in a CAT tool, a browser, a PDF, an email —
press `` ` ``, and act on it: look it up across a dozen terminology sources,
run an AI prompt over it, convert its case, wrap it in quotes, or paste a
snippet in its place.

Built in [AutoHotkey v2](https://www.autohotkey.com/docs/v2/). No dependencies,
no runtime, no install step.

![Beijer.bot menu](https://github.com/user-attachments/assets/773898d6-33b5-4aae-88f0-d89e7144db00)

---

## What it does

| | |
|---|---|
| 🔍 **Web searches** | Select a term, pick a source. IATE, Juremy, JurLex, Van Dale, Linguee, Proz, Reverso, BabelNet, Wikipedia, Wiktionary, Google Patents and more — 25 out of the box. Multi-search fires a whole batch at once. |
| 🤖 **AI actions** | Run any prompt over the selection: translate, proofread, rephrase, summarise, expand, localise. Provider-agnostic — Claude by default, OpenAI if you prefer — and non-blocking, so the rest of Beijer.bot keeps working while a request is in flight. |
| 📋 **Snippet library** | Boilerplate, standard replies, special characters, regex patterns, dictionary citations — inserted at the cursor. |
| 🔤 **Text conversions** | Upper / lower / title / sentence case, curly quotes, brackets, HTML bold, soft-hyphen removal, straight-to-curly quote conversion. |
| 🔖 **Bookmarks** | Online and local. Forums, docs, reference sites, folders you keep reopening. |
| 📎 **Clipboard manager** | Searchable history that survives restarts, pasted straight back into the window you came from. Entries you've already used are ticked and greyed, so you can work down a list of terms without losing your place. `Ctrl+Alt+C` |

Everything is reachable in two keystrokes: `` ` `` then an accelerator letter.

---

## Installing

1. Install [AutoHotkey v2](https://www.autohotkey.com/) (v2.0 or later — **not** v1).
2. Clone this repository.
3. Run `Beijer.bot.ahk`.

On first run, Beijer.bot copies the starter menu from `data.example/` into
`data/` and opens with a working set of searches and conversions. From there
you make it yours.

> Beijer.bot requests administrator rights on launch. This is deliberate: without
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
| `search` | Copies the selection and opens a URL, with `{q}` replaced by it |
| `ai` | Runs an AI prompt over the selection |
| `action` | Calls a built-in function |
| `submenu` | Holds other entries |
| `heading` / `separator` | Structure only |

Adding a new terminology source is one `search` entry:

```json
{
  "kind": "search",
  "label": "Wiktionary (English)",
  "url": "https://en.wiktionary.org/wiki/{q}"
}
```

The selection is UTF-8 percent-encoded before substitution, so terms containing
`&`, `?`, `+` or accented characters work correctly.

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
Beijer.bot.ahk        hotkeys, text conversions, local searches
lib/
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
