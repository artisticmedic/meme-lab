# Tim's Astonishing Meme Laboratory

Meme Lab for short. A Mac menu bar app for making captioned meme GIFs with an AI agent such as Claude Code, Codex or Cursor.

You ask your agent for "a meme that combines these two vibes". The agent searches Meme Lab's library, writes the captions, renders four to six options and shows them in the menu bar panel. You click one, and it lands on your clipboard, ready to paste into Discord.

The app does no reasoning of its own. It searches, renders, shows and delivers. Choosing templates and writing captions is left to the agent, through the skill in [`skill/meme/`](skill/meme/SKILL.md).

## Install

Meme Lab needs macOS 15 or later, on Apple silicon or Intel, and [Homebrew](https://brew.sh).

1. Install the two tools it renders with:

   ```sh
   brew install ffmpeg gifski
   ```

2. Download `Meme-Lab-1.0.0.zip` from the [latest release](https://github.com/artisticmedic/meme-lab/releases/latest). Unzip it and move **Tim's Astonishing Meme Laboratory** to Applications. The app is signed with a Developer ID and notarized by Apple.
3. Open it. A flask appears in the menu bar and the library window opens. In **Settings**, click **Refresh Now** to load about 270 templates. It takes a few seconds.
4. Let agents run it. In **Settings › Command line**, click **Install**. That points `~/.local/bin/meme` at the app; choose another folder there if you like. The card says whether the folder is on your shell's `PATH`, and **Copy Command** gives you the same step for a terminal. By hand:

   ```sh
   ln -s "/Applications/Tim's Astonishing Meme Laboratory.app/Contents/MacOS/MemeLab" ~/.local/bin/meme
   ```

5. Give your agent the skill. Clone this repository and link its skill folder into each agent's skills folder:

   ```sh
   git clone https://github.com/artisticmedic/meme-lab.git ~/meme-lab
   ln -s ~/meme-lab/skill/meme ~/.claude/skills/meme    # Claude Code
   ln -s ~/meme-lab/skill/meme ~/.codex/skills/meme     # Codex
   ln -s ~/meme-lab/skill/meme ~/.cursor/skills/meme    # Cursor
   ```

Then ask your agent for a meme.

## What it does

- **The panel.** Click the flask. Search by name or feeling ("waiting", "smug calm"), switch between templates, clips and made memes, and hover over a tile to see it move. Click tiles to pick up to four. **Copy prompt** puts a ready prompt for your agent on the clipboard, and **Ask agent** runs a command you set. Drag a tile into Discord or Finder to drop the file itself.
- **When an agent is waiting.** `meme propose` opens the panel with the agent's numbered options, and the flask shows a dot until you answer. Click one and press Return, or write what to change ("2, shorter caption") and click **Send back**. `meme pick` works the same way when the agent wants you to choose the base memes.
- **The library window.** All templates, clips and made memes. Click to select; **Details** (Command-I) shows the selection's details beside the grid, with a large moving preview, until you close them. Command-click or Shift-click to select several. Edit an item's feeling, how it's used, its tags and its collections. Remove items one at a time or all at once: files go to the Trash and templates are hidden. Drop GIFs, images or videos on the window or on the flask to add them. Every action is also in the menus, with keyboard shortcuts.
- **Picks.** Click the circle on a tile to pick it for your agent, up to four. The picks bar at the bottom shows them, with **Make GIF**, **Copy Prompt** and **Clear**, and the Picked shelf lists them.
- **Make GIF.** Click **Make GIF** on any item, or select up to four and make one from them. Type the captions and the preview follows as you type. Still templates become GIFs with a motion: **Reveal** shows the captions one at a time, **Zoom** pushes in slowly and **Shake** shakes. The result lands in Made, ready to copy or drag into a chat.
- **The library.** About 270 templates from [memegen](https://github.com/jacebrowning/memegen) and Imgflip's 100 most popular, plus your own clips and saved GIFs, and Wikimedia Commons files. Each item carries a one-line feeling, so searching for a mood finds the right template. The Popular shelf ranks Imgflip's top 100 and marks the ones new since the last refresh. Templates refresh by themselves once a week.
- **Rendering.** Captions come in four styles: classic, caption bar, subtitle, and the template's own text boxes. Items combine single, side by side, stacked or one after another, and still pictures can reveal, zoom or shake. Text is drawn with Core Text; ffmpeg composes the frames and gifski encodes the GIF. Each GIF shrinks until it fits under 8 MB, and an MP4 is written beside it.
- **One binary.** The app's binary is also the `meme` command. Reads print JSON, errors are one plain sentence, and every command documents itself with `--help`. Anything you can do in the app, an agent can do with the command.

Without the app running, `meme propose`, `meme pick` and `meme browse` fall back to a page in your browser. `--page` asks for the page on purpose.

## Media and terms

The repository holds no meme images. Template images are fetched at runtime from memegen's repository and Imgflip into a local cache, for personal use. Saved GIFs stay in your local library.

Each item shows how it may be used: "Post freely" for your own recordings and free-licence files, "Personal chat" for templates and saved GIFs.

GIPHY, KLIPY and Tenor media are link-only under their terms, which forbid downloading, captioning or re-hosting. `meme add` refuses their URLs. `meme klipy` shows KLIPY results in their own grid and returns a link, and needs a `KLIPY_API_KEY`.

`--riv` hands a file to Riv, Tim's own agent on another Mac, which posts it to a Discord thread. It needs `ssh` access to that Mac and is of no use outside Tim's setup.

## Files

| Path | Holds |
| --- | --- |
| `~/Library/Application Support/Meme Lab/config.json` | Settings. The app and `meme set` both write it. Missing keys fall back to defaults. A file that does not parse is never overwritten. |
| `~/Library/Application Support/Meme Lab/status.json` | Picks, a waiting agent's request, the running app, the last made meme. |
| `~/Library/Application Support/Meme Lab/index.json` | The library index. |
| `~/Pictures/Meme Lab/` | `Saved/` and `Made/`. **Settings › Library folder** moves them; `meme set libraryDir` only points Meme Lab at another folder. |
| `~/Library/Caches/Meme Lab/` | Template images, strips and render scratch space. |

`MEME_LAB_HOME=<folder>` puts all of these under one folder.

Settings in `config.json`: `maxMB`, `width`, `fps`, `maxSeconds`, `libraryDir`, `agentCommand` (what **Ask agent** runs; the prompt is in `$MEME_PROMPT`) and `animateAlways`.

## Build from source

Needs Xcode or the Swift 6 toolchain.

```sh
swift build
.build/debug/MemeLab sync            # run as the command: any verb works
.build/debug/MemeLab --render out/   # PNGs of each surface, light and dark
./scripts/build-app.sh               # build/Tim's Astonishing Meme Laboratory.app
./scripts/release.sh                 # notarized build/Meme-Lab-<version>.zip; needs a Developer ID
swift test
```

The pipeline tests render generated clips through ffmpeg and gifski and drive the picker over HTTP. They use no network. `seed/vibes.json` holds the bundled template descriptions; `scripts/gen-seed.sh` regenerates `Sources/MemeCore/SeedVibesData.swift` from it.

## License

MIT. See [LICENSE](LICENSE). The license covers the code only: template images and saved GIFs are not part of the repository.
