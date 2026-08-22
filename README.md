# YouTube Suggester — Omarchy Quattro Plugin

A native Omarchy Quattro bar plugin that scans your YouTube subscriptions from the **last 24h** (plus 20 personalized **Recommended** on `Shift+R`), classifies every video against your tags, and shows **all** matches per tag + an `Others` list — all sorted by popularity (trending velocity). Any video can be summarized on demand via your default coding agent and inspected in a popup that keeps the original description.

## How it works

1. **Watched filter** — builds the set of already-watched IDs from local browser history (Firefox, Chrome, Chromium, Brave, Edge), YouTube account history (`:ythistory`), and `seen.json` (videos you opened via the plugin).
2. **Feed — last 24h** — fetches `https://www.youtube.com/feed/subscriptions` with `yt-dlp` using your browser's cookies (decrypts Chromium `v11` cookies via `secretstorage` + `pycryptodomex`, fallback `--cookies-from-browser`). `Shift+R` also fetches `https://www.youtube.com/feed/recommended` (limit 20) and adds it on top of subs.
3. **Metadata scoring** — each unwatched candidate's title, creator tags and description are scored (`title 3×`, `tags 4×`, `description 1×`; single incidental hits are ignored). Every candidate gets `age_label` and `views/hour`.
4. **Ranking** — strict `24h` window for subs (Recommended is unfiltered when included), then per-tag **all** matches sorted by `recency tier → views/hour → views`; `Others` = everything unmatched, same sort.
5. **On-demand summary** — `T` downloads captions (auto + manual, `vtt` → `parse_vtt`) → whisper fallback (`whisper --model base.en`, now `max_whisper_minutes: 180` and `timeout 600/1800` for long podcasts) → prompt `opencode run` (`_agent_reply` via `omarchy-default-agent`, default `opencode`) for 4–6 bullets (prompt truncated to `12000` chars, `timeout 180s`), falls back to extractive `describe()` if agent fails. Result stored as `summary` and shown with the original description at the bottom.

Nothing runs automatically — `R` / `Shift+R` starts the pipeline; `T`/`Shift+T` start summaries. Opening a video keeps it visible until the next refresh (it’s added to `seen.json` so the next `R` hides it).

## Features

- Bar widget (middle-click refreshes) and panel with `last 24h` header, progress `done/total`.
- **Tags editor `E`** — up to 5 keywords, `config set --interests a,b` → state sync → auto-`R`.
- **Tabs per tag + `Others` last** — `←/→` or `1-5` to switch, counts shown.
- **Refresh:** `R` = subs 24h; `Shift+R` = subs 24h + 20 Recommended.
- **Open:** `o`/`Enter` → `omarchy-launch-webapp https://www.youtube.com/watch?v=ID` (same as `Super+Shift+Y` → `uwsm-app -- <browser> --app=URL`), keeps video visible until next refresh, adds to `recent.json`.
- **Summarize:** `T` = this video; `Shift+T` = all in current tag (not `Others`), queued via `summarizeQueue` (`Service.qml:46`) with dedupe (`currentSummarizeId`) → `○ queued #n` / `◌ summarizing…` badges, header shows `· X queued`.
- **Summary popup `S`** — shows AI summary on top + original description at bottom for that video, or plain description if not yet summarized; `j/k` scrolls `Flickable`, `S`/`Esc`/`Enter` closes. Also opened automatically when `T` finds an existing summary.
- Queue: hit `T` on multiple videos → they queue sequentially.
- Fully keyboard-driven: `R`, `Shift+R`, `E`, `T`, `Shift+T`, `S`, `o/Enter`, `j/k`, `←/→`/`1-5`, `Esc`.

## Requirements

> **Installing the plugin does NOT install system dependencies.** Install them manually first.

- Omarchy Quattro with shell plugin system
- `yt-dlp` on `PATH` (`pacman -S yt-dlp`)
- Browser logged into YouTube matching `browser` setting (`chromium` default)
- Chromium-family: `python-secretstorage` + `python-pycryptodomex` (`pip install --user secretstorage pycryptodomex` or `pacman -S python-secretstorage python-pycryptodomex`)
- Optional but recommended: `whisper` CLI for podcasts without captions (`pipx install openai-whisper`, `whisper_model: base.en` default, `max_whisper_minutes: 180`)
- For `T` summaries: a configured default Omarchy agent (`omarchy default agent opencode` etc.; `opencode run` is used). Without it, `T` falls back to extractive summary.

## Installation

```bash
omarchy plugin add https://github.com/Kristijan-K/omarchy-youtube-suggester.git --enable
```

### Manual installation

```bash
PLUGIN_ID="io.github.kkosu.youtube-suggester"
mkdir -p "$HOME/.config/omarchy/plugins/$PLUGIN_ID/bin"
cp manifest.json Service.qml BarWidget.qml Model.js README.md LICENSE \
  "$HOME/.config/omarchy/plugins/$PLUGIN_ID/"
cp bin/omarchy-youtube-suggester "$HOME/.config/omarchy/plugins/$PLUGIN_ID/bin/"
chmod +x "$HOME/.config/omarchy/plugins/$PLUGIN_ID/bin/omarchy-youtube-suggester"

omarchy plugin validate "$HOME/.config/omarchy/plugins/$PLUGIN_ID"
omarchy-shell shell rescanPlugins
omarchy plugin enable "$PLUGIN_ID"
omarchy bar put "$PLUGIN_ID" --section right
```

## First run

1. Click the bar icon → `E` → type `AI, Software, Music` → `Enter` (auto-refreshes).
2. Press `R` (subs 24h) or `Shift+R` (subs + 20 Recommended) → watch `history → feed → metadata` → tabs appear.
3. `T` on a video → header shows `Summarizing: Title · X queued` → notification when ready → `S` to read summary + original description. `Shift+T` queues the whole tag.

Browser profile mismatch: `~/.config/omarchy/plugins/io.github.kkosu.youtube-suggester/bin/omarchy-youtube-suggester config set --browser brave`

### Tuning knobs (`~/.config/youtube-suggester/config.json`)

| Key | Default | Meaning |
| --- | --- | --- |
| `interests` | `[]` | 1–5 keywords |
| `browser` | `chromium` | `chromium`/`chrome`/`brave`/`edge`/`firefox` |
| `feed_limit` | `120` | Subs feed entries per scan |
| `max_candidates` | `60` | Newest unwatched to score (plus 20 rec on `Shift+R`) |
| `metadata_workers` | `4` | Parallel `yt-dlp --dump-json` |
| `transcribe_whisper` | `true` | Allow whisper fallback |
| `max_whisper_minutes` | `180` | Whisper even for long podcasts (3h) |
| `whisper_model` | `base.en` | Whisper model |
| `subs_langs` | `en…` | Caption langs |

## CLI

```bash
CLI="$HOME/.config/omarchy/plugins/io.github.kkosu.youtube-suggester/bin/omarchy-youtube-suggester"

"$CLI" config get
"$CLI" config set --interests "linux,nix,salesforce"
"$CLI" run --limit 10                      # subs 24h
"$CLI" run --with-recommended             # subs 24h + 20 Recommended
"$CLI" status
"$CLI" summarize <video_id>
"$CLI" feed --limit 5
"$CLI" history
"$CLI" open <video_id>
```

State in `~/.cache/omarchy/youtube-suggestor/state.json` (`interests`, `recommendations[]` with `tag/source/summary`, `pool`, `recent`), `seen.json`, `recent.json`.

## Troubleshooting

```bash
omarchy plugin list --json | jq '.[] | select(.id=="io.github.kkosu.youtube-suggester")'
omarchy-shell shell rescanPlugins
qs log -p "$OMARCHY_PATH/shell" --tail 100
```

- **Feed empty / `cookies no longer valid`** — re-open YouTube in the configured browser, then `omarchy plugin validate` and `R` again; test `$CLI feed --limit 2`.
- **Scoring stuck `metadata 3/…`** — fixed in `Service.qml:122` + `bin/omarchy-youtube-suggestor:1011` per-item `try`; if it still happens `cat state.json | jq .stage` should now be `error` not `metadata`.
- **`S` shows no summary** — press `T` first; fallback is description if agent missing.

## License

[MIT](LICENSE). Depends on Omarchy Quattro, `yt-dlp`, and optionally `openai-whisper` + your `opencode`/`claude`/etc. agent — none bundled.

## Publishing

Public repo + `manifest.json` at root, `README`/`LICENSE`, no `omarchy.*` id, no symlinks, `bin/omarchy-youtube-suggestor` executable, `omarchy plugin validate` and `qmllint -I $OMARCHY_PATH/shell BarWidget.qml Service.qml` must pass. Then submit at https://github.com/HANCORE-linux/omarchy-plugin-marketplace/issues/new?template=submit-plugin.yml .
