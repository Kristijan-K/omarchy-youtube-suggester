# YouTube Suggester — Omarchy Quattro Plugin

A native Omarchy bar plugin that scans your YouTube subscriptions from the **last 24h** (plus 20 Recommended on `Shift+R`), classifies every video against your tags, and shows **all** matches per tag + an `Others` list — all sorted by popularity. Any video can be summarized on demand via your default coding agent (`opencode` etc.) and inspected in a popup that keeps the original description.

On first install `AI` and `Software` are pre-configured as tags — change them with `E` in the panel.

![YouTube Suggester preview](preview.png)

## Features

- **Last 24h subs + 20 Recommended** — `R` = subs strictly `<24h`, `Shift+R` = `R` + 20 personalized Recommended (any age) on top, de-duplicated and kept unfiltered so non-subs visibly appear.
- **Tag filter + `Others`** — every video scored (`title 3×` > `tags 4×` > `description 1×`, single incidental hits ignored). **All** matches per tag sorted by `age → views/hour → views`; `Others` = everything unmatched, same sort.
- **Title + description in list** — title, description snippet (`320` chars), thumbnail, `duration` · `age` · `views/hour`, channel. Full `meta_description` available in popup.
- **Summarize** — `T` downloads captions → Whisper fallback (`whisper --model base.en`, `max_whisper_minutes: 180` for long podcasts, `timeout 600/1800`) → `opencode run` 4–6 bullets (`12000` chars, `180s`), falls back to extractive. `Shift+T` queues **all** in current tag (not `Others`) via `summarizeQueue`/`currentSummarizeId` with `○ queued #n` / `◌ summarizing…` badges and header `· X queued`.
- **Popup `S`** — shows AI summary on top + original description at bottom (or plain description if not yet summarized); `j/k` scrolls `Flickable`, `S`/`Enter`/`Esc` closes, auto-updates when the queued job finishes (`popupLiveItem`).
- **Open** — `o`/`Enter` → `omarchy-launch-webapp https://www.youtube.com/watch?v=ID` (same as `Super+Shift+Y` → `uwsm-app -- <browser> --app=URL`), keeps video visible until next `R` (added to `seen.json`, hidden on next refresh via `watched = history|seen`).
- **Auto-refresh on tag edit** — `E` → `Enter` → `config set` → `loadStatus` → `refresh()` if idle.
- **No per-tab limit, no `no-tag` fallback** — empty tab stays empty (check `Others`).

## Flow

1. `E` edit tags → auto `R`.
2. `R` (or `Shift+R` for +Recommended) → `history → feed → metadata` (`done/total` + `candidates_seen`).
3. Browse tabs `←/→` / `1-5`, navigate `j/k`, open `o`.
4. `T` for one, `Shift+T` for whole tag → header shows summarizing + queued → `S` to read.

## Keybinds

| Key | Action |
|---|---|
| `R` | Refresh last 24h subs |
| `Shift+R` | Refresh subs 24h + 20 Recommended |
| `E` | Edit tags (up to 5, `Enter` saves) |
| `T` | Summarize this video |
| `Shift+T` | Summarize all in current tag (not Others) |
| `S` | Toggle description / summary popup (`j/k` scroll) |
| `o` / `Enter` | Open via webapp |
| `j` / `k` , `←` / `→` , `1-5` | Navigate list / tabs |
| `Esc` | Close popup → close panel |
| Middle-click bar icon | Refresh |

## Manual installation

> **Manual install is required** — `omarchy plugin add` only clones the repo and does **not** install system dependencies. Install them first:

**Required:**
- `yt-dlp` — `pacman -S yt-dlp` (or `pipx install yt-dlp`)
- Chromium cookie decrypt (for `browser: chromium`): `pacman -S python-secretstorage python-pycryptodomex` or `pip install --user secretstorage pycryptodomex` (`--break-system-packages` on Arch if needed)

**Optional (for long podcasts without captions):**
- `whisper` — `pipx install openai-whisper` (uses `whisper --model base.en`, `max_whisper_minutes: 180`, `timeout 600/1800`)

**For `T` AI summaries:**
- Default Omarchy agent — `omarchy default agent opencode` (or `claude`/`codex`/`grok`/`gemini`/`copilot`/`crush` via `mise`). Without it `T` falls back to extractive summary. To disable AI summaries entirely: `omarchy-youtube-suggester config set --enable-ai-summary false` (uses local extractive summary only).

Browser must be logged into YouTube matching `browser` setting (`chromium` default).

## Security

**Plugin privilege:** This plugin runs unsandboxed with your user privileges (same as the Omarchy shell process). Review [`bin/omarchy-youtube-suggester`](bin/omarchy-youtube-suggester) before enabling.

**YouTube content is untrusted:** Video titles and captions may contain prompt-injection payloads (e.g. `Ignore previous instructions…`). This plugin hardens the summarizer path:
- `bin/omarchy-youtube-suggester:1260+` wraps every title/transcript in explicit `BEGIN/END UNTRUSTED …` markers and prepends highest-priority `SECURITY RULES` that force the model to treat everything inside as **data only**, to ignore embedded instructions, and to never invoke tools or browse. Delimiter strings inside the content are filtered to prevent breakout.
- Agent invocations use least-privilege flags where supported: `codex --sandbox read-only`, `claude --tools "" --permission-mode dontAsk`, `gemini --approval-mode plan`, `copilot --available-tools ""`. Even a successful injection cannot escalate to local tool execution.
- Disable AI summaries if you prefer zero LLM exposure: `enable_ai_summary: false` (pure extractive summarization via `describe()`).
- QML rendering: `BarWidget.qml` sets `textFormat: Text.PlainText` (and `TextEdit.PlainText` for the summary popup) on **every** `Text`/`TextEdit` element, including the flagged `775-785` popup title, so remote HTML like `<img src=…>` is never interpreted and no remote resources are fetched via `AutoText`.

See `tests/test_prompt_isolation.py` and `tests/test_qml_safety.py` for regression coverage of both fixes.

## Development & Tests

```bash
# Validate manifest + QML (same checks as the marketplace)
omarchy plugin validate .
qmllint -I /usr/share/omarchy/shell BarWidget.qml Service.qml

# Python tests (prompt isolation, QML safety, config flag)
pytest -v
# or
python -m pytest tests -v
```

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
