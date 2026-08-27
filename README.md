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
| 🤖 **AI actions** | Run any prompt over the selection: translate, proofread, rephrase, summarise, expand, localise. Your prompts, your models. |
| 📋 **Snippet library** | Boilerplate, standard replies, special characters, regex patterns, dictionary citations — inserted at the cursor. |
| 🔤 **Text conversions** | Upper / lower / title / sentence case, curly quotes, brackets, HTML bold, soft-hyphen removal, straight-to-curly quote conversion. |
| 🔖 **Bookmarks** | Online and local. Forums, docs, reference sites, folders you keep reopening. |
| 📎 **Clipboard manager** | *Not yet implemented — see the roadmap.* |

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

---

## Layout

```
Beijer.bot.ahk        hotkeys, AI functions, text conversions
lib/
  menu_builder.ahk    builds the menu from data
  editor.ahk          the Library Editor
  data.ahk            reads and writes the JSON
  jxon.ahk            JSON parser (third-party)
data/                 your content — gitignored
data.example/         generic starter set, shipped
```

---

## Roadmap

- **Clipboard manager** — persistent text and image history, searchable, with
  the privacy controls the job needs: capture toggle, auto-expiry, and an
  exclusion list for password managers.
- **Provider-agnostic AI** — swap between Claude, OpenAI and others from a
  config file instead of being wired to one vendor's endpoint. Non-blocking, so
  a slow request no longer freezes the script.
- **Prompt library** — prompts as editable data alongside snippets, so a custom
  prompt is as easy to add as a snippet.

---

## Credits

The AI request handling began life in
[ChatGPT-AutoHotkey-Utility](https://github.com/kdalanon/ChatGPT-AutoHotkey-Utility)
by kdalanon, and has been substantially rewritten since.

JSON parsing uses [cJson/Jxon](https://github.com/cocobelgica/AutoHotkey-JSON).

---

By [Michael Beijer](https://michaelbeijer.co.uk/), Dutch→English patent and
technical translator. Related work:
[Supervertaler](https://github.com/michaelbeijer/Supervertaler) ·
[SuperLookup](https://github.com/michaelbeijer/superlookup) ·
[WordCounter](https://github.com/michaelbeijer/WordCounter)
