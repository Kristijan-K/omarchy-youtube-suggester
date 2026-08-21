# YouTube Suggestor — Omarchy Quattro Plugin

A native Omarchy Quattro bar plugin that scans your logged-in YouTube
subscriptions feed, filters out videos you have already watched, transcribes
the newest unwatched uploads, and recommends the **top 5** that best match
your interest keywords — each with a short "what it's about" description
generated from the actual transcript.

![YouTube Suggestor preview](preview.png)

## How it works

1. **Watched filter** — builds the set of already-watched video IDs from your
   local browser history (Firefox, Chrome, Chromium, Brave, Edge), your
   YouTube account watch history (`:ythistory`, catches other-device views),
   plus every video you open through the plugin.
2. **Feed** — fetches your subscriptions feed with `yt-dlp` using your
   browser's cookies, so you get the same logged-in view as the YouTube app
   without an API key. On Chromium-family browsers the plugin decrypts the
   cookie database itself (including the new v11 hash-prefix scheme that
   yt-dlp cannot read yet) into a temporary `cookies.txt`; it falls back to
   `--cookies-from-browser` elsewhere.
3. **Transcription** — for each unwatched candidate (newest 15 by default):
   existing captions are used when available (seconds per video); otherwise
   the audio is downloaded and transcribed locally with `whisper` (bounded by
   `max_whisper_per_run` so a scan never runs forever). Music/silence
   transcripts are detected and discarded.
4. **Ranking** — transcripts are scored against your 1–5 interest keywords
   (title matches weigh 3×, transcript matches 1×), and the top 5 videos are
   shown with keyword badges and an extractive summary of what was said.

## Features

- Bar widget showing pipeline status at a glance; middle-click rescans.
- Panel lists the top 5 recommendations with thumbnails, channel, duration,
  transcript source, relevance score, matched keywords, and description.
- Inline interest editor (`E`) — up to 5 comma-separated keywords, persisted
  in `~/.config/youtube-suggestor/config.json`.
- Live progress while scanning (history → feed → transcribing → ranking).
- Opens videos in your default browser (`o` / `Enter`) and remembers them as
  watched so they never appear again.
- Fully keyboard-driven: `j/k` navigate, `R` rescan, `E` edit interests,
  `Esc` close.

## Requirements

- Omarchy Quattro with the shell plugin system
- `yt-dlp` on `PATH`
- A browser logged into YouTube whose profile matches the configured
  `browser` setting (default `chromium`)
- Chromium-family browsers: `python3` with `secretstorage` and
  `pycryptodomex` for cookie decryption
  (`pip install --user secretstorage pycryptodomex`; on Arch add
  `--break-system-packages`, or install `python-secretstorage`
  system-wide)
- Optional: OpenAI `whisper` CLI for the no-captions fallback
  (`pip install openai-whisper`, model configurable, default `base.en`)

## Installation

```bash
omarchy plugin add https://github.com/Kristijan-K/omarchy-youtube-suggestor.git --enable
```

### Manual installation

```bash
PLUGIN_ID="io.github.kkosu.youtube-suggestor"
mkdir -p "$HOME/.config/omarchy/plugins/$PLUGIN_ID/bin"
cp manifest.json Service.qml BarWidget.qml Model.js README.md LICENSE \
  "$HOME/.config/omarchy/plugins/$PLUGIN_ID/"
cp bin/omarchy-youtube-suggestor "$HOME/.config/omarchy/plugins/$PLUGIN_ID/bin/"
chmod +x "$HOME/.config/omarchy/plugins/$PLUGIN_ID/bin/omarchy-youtube-suggestor"

omarchy plugin validate "$HOME/.config/omarchy/plugins/$PLUGIN_ID"
omarchy-shell shell rescanPlugins
omarchy plugin enable "$PLUGIN_ID"
omarchy bar put "$PLUGIN_ID" --section right
```

## First run

1. Click the bar icon and press `E`, type up to 5 keywords
   (e.g. `linux, hyprland, salesforce, keyboards`), press `Enter`.
2. Press `R`. The pipeline runs: browser history → subscriptions feed →
   transcription → ranking. Progress is streamed live in the panel.
3. Browse the top 5, press `o` to watch one — it is marked watched
   automatically.

If your YouTube login lives in a different browser, set it once:

```bash
~/.config/omarchy/plugins/io.github.kkosu.youtube-suggestor/bin/omarchy-youtube-suggestor \
  config set --browser brave
```

### Tuning knobs (`~/.config/youtube-suggestor/config.json`)

| Key | Default | Meaning |
| --- | --- | --- |
| `interests` | `[]` | 1–5 keywords scored against titles and transcripts |
| `browser` | `chromium` | Cookie source: `chromium`, `chrome`, `brave`, `edge`, `firefox` |
| `feed_limit` | `120` | How many subscription-feed entries to pull per scan |
| `max_candidates` | `15` | Newest unwatched videos to transcribe per scan |
| `recommend_count` | `5` | Recommendations shown |
| `use_account_history` | `true` | Also fetch account watch history (other-device views) |
| `account_history_limit` | `200` | Account history entries to consider |
| `max_whisper_minutes` | `20` | Only whisper-transcribe videos shorter than this |
| `max_whisper_per_run` | `3` | Cap local whisper jobs per scan |
| `whisper_model` | `base.en` | Whisper model used for the fallback |
| `subs_langs` | `en…` | Caption languages to accept |

## CLI

```bash
CLI="$HOME/.config/omarchy/plugins/io.github.kkosu.youtube-suggestor/bin/omarchy-youtube-suggestor"

"$CLI" config get                 # show configuration
"$CLI" config set --interests "linux,nix,salesforce"
"$CLI" run                        # full pipeline, streams progress JSON lines
"$CLI" status                     # current state JSON
"$CLI" feed                       # debug: show fetched feed candidates
"$CLI" history                    # debug: count watched IDs found in browsers
"$CLI" open <video_id>            # mark watched + open in browser
```

State lives in `~/.cache/omarchy/youtube-suggestor/state.json`; seen-video
marks in `seen.json` next to it.

## Troubleshooting

```bash
omarchy plugin list --json | jq '.[] | select(.id == "io.github.kkosu.youtube-suggestor")'
omarchy-shell shell rescanPlugins
qs log -p "$OMARCHY_PATH/shell" --tail 100
```

- **Feed returns nothing** — make sure the configured browser profile is
  actually logged into YouTube, then test `$CLI feed` directly.
- **All entries say "no transcript"** — captions were blocked and whisper is
  not installed or the video exceeds `max_whisper_minutes`; those videos are
  still ranked by title matches only.

## License

[MIT](LICENSE). This plugin depends on Omarchy Quattro, yt-dlp, and optionally
OpenAI Whisper; none of them are bundled or modified.
