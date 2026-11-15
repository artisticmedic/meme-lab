---
name: meme
description: Makes captioned meme GIFs with Meme Lab, the `meme` command. Use when Tim asks for a meme or reaction GIF, "a meme that combines these two vibes", a caption on a clip, or something for Discord.
---

# Meme Lab

`meme` is a local command. It searches a small library, renders captions in about a second, shows options in a browser page and delivers the result. It never thinks: reading the vibes, writing the captions and judging the options is your job.

Every read prints JSON. Errors are one plain sentence on stderr. `meme <command> --help` documents each command.

## Before anything

- `meme status`: if `lastSync` is missing or older than seven days, run `meme sync` (about five seconds).
- `meme picks`: if Tim says "these", "my picks" or "the ones I picked", they are here.

## Make a meme

1. **Read the ask.** Name each vibe in plain words ("calm while everything burns", "build failing"). Draft three to five captions. Keep a line under about eight words.
2. **Search each vibe** two or three ways: literal, visual and emotional. Results carry `vibe`, `howUsed`, `boxes` and `rights`.
   ```
   meme search waiting forever
   meme search smug calm --kind template
   meme search --kind clip --limit 20
   ```
3. **Look before choosing.** `meme info <id>` prints `strip`, a PNG of the start, middle and end. Open it with your image-reading tool for two to four candidates. Templates download on first use.
4. **Render four to six options.** Each `meme make` prints an `id` and a `file`.
   ```
   meme make drake -c "writing the code" -c "making a meme tool instead"
   meme make s-1a2b3c4d -c "me watching CI spin" --style bar
   meme make fine s-1a2b3c4d --layout side --label "the plan" --label "the reality" --style classic -c "" -c "shipping friday"
   meme make s-1a2b3c4d fine --layout sequence --style subtitle -c "deploy at 4:59pm"
   ```
   - Styles: `template` uses the template's own boxes, one `-c` per box in order, following `howUsed`; it is the default for memegen templates. `classic` is Impact, top then bottom. `bar` is the white bar above a moving clip, the default for clips. `subtitle` sits at the bottom.
   - Layouts: `single`, `side`, `stack` and `sequence` (setup, then punchline). Up to four items.
   - `--trim 0.5-2.5` keeps part of a moving item; repeat it per item.
   - Output stays under 8 MB by lowering frame rate and size. `overLimit: true` means it could not; try `--trim` or fewer items.
5. **Show Tim the options.**
   ```
   meme propose m-abcde m-fghij m-klmno m-pqrst --from Codex
   ```
   - The command opens the picker page and waits, up to 15 minutes by default. Tell Tim the page is open, then run it.
   - It prints `{"chosen": ["m-fghij"], "note": ""}`.
   - If `chosen` is empty and `note` says what to change ("2, shorter caption"), re-render only that option and propose again.
   - Exit 124 means nobody chose. Ask Tim in chat instead.
   - If Tim is on his phone (he asked through Claude Duet or Riv), add `--riv`. The options are posted to Riv's "Meme Lab" Discord thread. Tim answers through the channel he asked from, not in Discord.
6. **Deliver.**
   - `meme send <id>`: puts the file on the clipboard. Tim pastes it into Discord.
   - `meme send <id> --riv`: posts it to Riv's Discord thread, for Tim on his phone. Add `--caption "..."` for a one-line caption.
   - `meme send <id> --save ~/Desktop`: copies it into a folder.
   - `--mp4` sends the MP4 instead: smaller, and it plays inline in Discord.

## KLIPY reaction GIFs (links only)

`meme status` shows `"klipy": true` when a `KLIPY_API_KEY` secret exists. Without one, skip KLIPY and say so in a few words.

```
meme klipy cat typing --copy
```

- It opens KLIPY's results in their own grid, in KLIPY's order, for Tim to choose one. It prints `{"chosen": [slug], "link": "..."}`, and `--copy` puts the link on the clipboard.
- KLIPY's terms require every result, unfiltered and in its order. Never pick among KLIPY results yourself, and never pass a KLIPY link to `meme add` or `meme make`.

## Rules

- **GIPHY, KLIPY and Tenor are links only.** Their terms forbid downloading, captioning or re-hosting their media, and `meme add` refuses their URLs. To use one, share its link as it is.
- **Templates and saved GIFs are for personal chat.** `rights` says "Personal chat" for them and "Post freely" for Tim's recordings and free-licence files. Mention it if Tim wants to use a meme in an ad or on a product.
- **Do not mock recognisable people in stock or Wikimedia clips.** Their licences rule that out.
- **Riv's side belongs to Riv.** Post only through `meme send --riv` or `meme propose --riv`. Exit 75 means rate limited or still in flight: do not resend.

## Library work

- **Add:**
  - `meme add <file or link>`: Wikimedia Commons links keep their licence and credit.
  - `meme add <file> --recording`: Tim's own recordings.
  - `meme import <folder>`: adds a whole folder, such as GIF Machine's save folder (`--recording`).
- **Tag:** `meme untagged` lists items with no feeling written yet. For each, run `meme info <id>`, look at the strip, then:
  ```
  meme tag <id> --vibe "smug calm while everything burns" --add chaos --add irony --how-used "Calm person in front of a disaster."
  ```
- **Collections:** `meme collect <id> work`, and `meme search --collection work`.
- **Remove:** `meme remove <id>`. Saved and made files go to the Trash; templates are hidden.
- **Browse:** when Tim wants to look around himself, start `meme browse` in the background. His picks land in `meme picks`, and "Copy prompt" on the page hands them to any agent.
- **Settings:** `meme get` and `meme set <key> <value>`: `maxMB`, `width`, `fps`, `maxSeconds`, `libraryDir`.

## Files

- `~/Library/Application Support/Meme Lab/`: `config.json`, `status.json` (picks, a pending proposal, the last made meme) and `index.json`.
- `~/Pictures/Meme Lab/`: `Saved/` and `Made/`.
- `~/Library/Caches/Meme Lab/`: template images and strips.
- `MEME_LAB_HOME=<folder>` moves all three, for tests.
