# YouTube Suggestor — Omarchy Quattro Plugin

A native Omarchy Quattro bar plugin that scans your logged-in YouTube
subscriptions feed, filters out videos you have already watched, and
recommends the **top 3** matches for your interest keywords — scored against
real video metadata (title, creator tags, description) in seconds, with
on-demand transcript summaries one keypress away.

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
3. **Metadata scoring** — each unwatched candidate's title, creator tags, and
   description are scored against your keywords (tags weigh most, then
   title, then description). Nothing is downloaded or transcribed; a full
   scan takes ~30 seconds.
4. **On-demand transcripts** — press `T` on any recommendation to transcribe
   it in the background (captions first, whisper fallback). The panel can be
   closed; when the summary is ready a desktop notification fires and the
   card shows "✓ summary ready" next time you open it.

Nothing runs automatically — the pipeline only starts when you press `F` or
click **Find me a video**.

## Features

- Bar widget (middle-click rescans); nothing runs until you ask.
- Panel opens showing your recently opened videos, ready for a fresh scan.
- **Find me a video** button / `F` key runs the whole pipeline live.
- Top 3 recommendations with thumbnails, channel, duration, keyword badges,
  and descriptions from the video's own metadata.
- `T` transcribes the selected video in the background with a spinner badge
  and a "summary ready" desktop notification.
- Inline tags editor (`E`) — up to 5 comma-separated keywords, persisted in
  `~/.config/youtube-suggestor/config.json`.
- Opens videos in your default browser (`o` / `Enter`) and remembers them as
  watched so they never appear again.
- Fully keyboard-driven: `F` find, `T` transcribe, `E` edit tags,
  `o/Enter` open, `j/k` navigate, `Esc` close.

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
2. Press `F` (or click **Find me a video**). Watch the live progress:
   watch history → feed → metadata scoring. Done in ~30 seconds.
3. Browse the top 3, press `o` to watch one — it is marked watched
   automatically. Want a deeper summary of one? Press `T` and carry on;
   a notification tells you when its transcript summary is ready.

If your YouTube login lives in a different browser, set it once:

```bash
~/.config/omarchy/plugins/io.github.kkosu.youtube-suggestor/bin/omarchy-youtube-suggestor \
  config set --browser brave
```

### Tuning knobs (`~/.config/youtube-suggestor/config.json`)

| Key | Default | Meaning |
| --- | --- | --- |
| `interests` | `[]` | 1–5 keywords scored against titles, tags, descriptions |
| `browser` | `chromium` | Cookie source: `chromium`, `chrome`, `brave`, `edge`, `firefox` |
| `feed_limit` | `120` | How many subscription-feed entries to pull per scan |
| `max_candidates` | `15` | Newest unwatched videos to score per scan |
| `metadata_workers` | `4` | Parallel metadata fetches (scan speed) |
| `recommend_count` | `3` | Recommendations shown |
| `use_account_history` | `true` | Also fetch account watch history (other-device views) |
| `account_history_limit` | `200` | Account history entries to consider |
| `transcribe_whisper` | `true` | Allow whisper fallback for on-demand `T` transcriptions |
| `max_whisper_minutes` | `20` | Only whisper-transcribe videos shorter than this |
| `whisper_model` | `base.en` | Whisper model used for the fallback |
| `subs_langs` | `en…` | Caption languages to accept |

## CLI

```bash
CLI="$HOME/.config/omarchy/plugins/io.github.kkosu.youtube-suggestor/bin/omarchy-youtube-suggestor"

"$CLI" config get                 # show configuration
"$CLI" config set --interests "linux,nix,salesforce"
"$CLI" run                        # full pipeline, streams progress JSON lines
"$CLI" status                     # current state JSON
"$CLI" transcribe <video_id>      # background transcript summary + notification
"$CLI" feed                       # debug: show fetched feed candidates
"$CLI" history                    # debug: count watched IDs found in browsers
"$CLI" open <video_id>            # mark watched + open in browser
```

State lives in `~/.cache/omarchy/youtube-suggestor/state.json`; seen-video
marks in `seen.json` and the panel's "Recently opened" list in `recent.json`
next to it.

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
