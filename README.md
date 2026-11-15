# Tim's Astonishing Meme Laboratory

Meme Lab is a Mac command-line tool for making captioned meme GIFs. An agent such as Claude Code, Codex or Cursor drives it. The agent reads a request like "a meme that combines these two vibes", searches a small local library, renders several captioned options and shows them in a picker page in the browser. The pick goes to the clipboard, or to a Discord thread through Riv.

The command does no reasoning of its own. It searches, renders, shows and delivers. Choosing templates and writing captions is left to whichever agent runs it, through the skill in `skill/meme/`.

## What it does

- **Library.** Meme Lab starts with about 280 templates: memegen's set and Imgflip's 100 most popular. It also holds clips Tim adds: his own recordings, saved GIFs and Wikimedia Commons files. Each item carries a one-line feeling, so a search for "waiting" or "smug calm" finds the right template.
- **Staying current.** `meme sync` pulls memegen's template list and Imgflip's popular list. Templates new to either list appear under "New and rising" for two weeks.
- **Rendering.** Captions come in four styles: classic, caption bar, subtitle, and the template's own text boxes. Items combine in four layouts: single, side by side, stacked and in sequence. Text is drawn with Core Text; ffmpeg composes the frames and gifski encodes the GIF. A GIF is shrunk until it fits under 8 MB, and an MP4 is written beside it.
- **Picker page.** `meme pick`, `meme propose` and `meme browse` serve a page on 127.0.0.1 with an animated grid. The page hands Tim's choice back to the waiting command.
- **Delivery.** `meme send` puts the file itself on the clipboard, so pasting into Discord uploads it. `--riv` hands the file to Riv on the M1, which posts it to its "Meme Lab" thread.
- **KLIPY, links only.** With a `KLIPY_API_KEY` (an environment variable, or the `secrets` Keychain helper), `meme klipy <words>` shows KLIPY's results in their own grid, in KLIPY's order, and returns the chosen link. Without a key the command says KLIPY is off.

## Media and terms

The repository holds no meme images. Template images are fetched at runtime from memegen's repository and Imgflip into a local cache, for personal use. Saved GIFs stay in the local library.

GIPHY, KLIPY and Tenor media are link-only under their terms, which forbid downloading, captioning or re-hosting. `meme add` refuses their URLs.

## Requirements

- macOS 15 or later, Swift 6.
- `ffmpeg`, `ffprobe` and `gifski` on the `PATH` (`brew install ffmpeg gifski`).
- For `--riv`: `ssh m1` access, and Riv's `riv-drop` on the M1.

## Build and run

```
swift build -c release
.build/release/meme sync
.build/release/meme search waiting
.build/release/meme make drake -c "writing the code" -c "making a meme tool instead"
```

Every command documents itself with `--help`. Reads print JSON; errors are one plain sentence on stderr.

## Files

| Path | Holds |
| --- | --- |
| `~/Library/Application Support/Meme Lab/config.json` | Settings. Missing keys fall back to defaults. A file that does not parse is never overwritten. |
| `~/Library/Application Support/Meme Lab/status.json` | Picks, a pending proposal, whether a command is waiting, the last made meme. |
| `~/Library/Application Support/Meme Lab/index.json` | The library index. |
| `~/Pictures/Meme Lab/` | `Saved/` and `Made/`. `meme set libraryDir` moves it. |
| `~/Library/Caches/Meme Lab/` | Template images, strips and render scratch space. |

`MEME_LAB_HOME=<folder>` puts all of these under one folder.

## Development

```
swift test
```

The pipeline tests render generated clips through ffmpeg and gifski and drive the picker over HTTP. They use no network. `seed/vibes.json` holds the bundled template descriptions; `scripts/gen-seed.sh` regenerates `Sources/MemeCore/SeedVibesData.swift` from it.
