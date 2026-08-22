# YouTube Suggester — Omarchy Quattro Plugin

A native Omarchy bar plugin that scans your YouTube subscriptions from the **last 24h** (plus 20 Recommended on `Shift+R`), classifies every video against your tags, and shows **all** matches per tag + an `Others` list — all sorted by popularity. Any video can be summarized on demand via your default coding agent (`opencode` etc.) and inspected in a popup that keeps the original description.

On first install `AI` and `Software` are pre-configured as tags — change them with `E` in the panel.

![YouTube Suggester preview](preview.png)

## Manual installation

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
