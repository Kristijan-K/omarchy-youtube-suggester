import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  property var shell: null

  // Mirrored pipeline state (last JSON line emitted by the engine)
  property var state: ({ stage: "idle" })
  property string stage: state.stage || "idle"
  property string detail: state.detail || ""
  property var recommendations: Model.recommendations(state)
  property var interests: Model.interests(state)
  property var recent: Model.recent(state)
  property int candidatesSeen: state.candidates_seen || 0
  property int watchedCount: state.watched_count || 0
  property string lastError: state.error || ""
  property string updatedAt: state.updated_at || ""
  property bool busy: Model.isBusy(stage)

  readonly property string engineScript: {
    var raw = Qt.resolvedUrl("bin/omarchy-youtube-suggester").toString()
    return raw.indexOf("file://") === 0 ? raw.substring(7) : raw
  }

  signal runFinished(bool success, string message)

  function refresh() {
    if (runProcess.running) return
    lastError = ""
    runProcess.command = [engineScript, "run"]
    runProcess.running = true
  }

  function refreshWithRecommended() {
    if (runProcess.running) return
    lastError = ""
    runProcess.command = [engineScript, "run", "--with-recommended"]
    runProcess.running = true
  }

  function openVideo(videoId) {
    if (!videoId || openProcess.running) return
    openProcess.command = [engineScript, "open", videoId]
    openProcess.running = true
  }

  function saveInterests(keywords) {
    if (configProcess.running) return
    configProcess.command = [engineScript, "config", "set", "--interests", keywords.join(",")]
    configProcess.running = true
  }

  function loadStatus() {
    if (statusProcess.running) return
    statusProcess.command = [engineScript, "status"]
    statusProcess.running = true
  }

  function applyState(data) {
    if (!data) return
    root.state = data
    if (data.stage === "done") {
      root.runFinished(true, data.detail || "Recommendations ready")
    } else if (data.stage === "error") {
      root.runFinished(false, data.error || "Pipeline failed")
    }
  }

  // Streams live progress lines from the engine while the pipeline runs.
  Process {
    id: runProcess
    stdout: SplitParser {
      onRead: function(data) {
        root.applyState(Model.parseState(data))
      }
    }
    stderr: StdioCollector { id: runError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var msg = String(runError.text || "Pipeline failed (exit " + exitCode + ")").trim()
        if (!msg) msg = "Pipeline failed"
        root.lastError = msg
        root.runFinished(false, msg)
        // If we died while busy, the state file is stale (still at
        // metadata 3/35). Don't reload it and re-enter busy — surface
        // the error directly.
        if (root.busy) {
          root.state = {
            stage: "error",
            error: msg,
            detail: "",
            progress: {done: 0, total: 0},
            interests: root.interests,
            recommendations: root.recommendations,
            recent: root.recent,
            candidates_seen: root.candidatesSeen,
            watched_count: root.watchedCount,
            updated_at: new Date().toISOString().slice(0,19)
          }
          return
        }
      }
      Qt.callLater(function() { root.loadStatus() })
    }
  }

  Process {
    id: statusProcess
    stdout: StdioCollector { id: statusOutput; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0 && !root.busy) {
        root.applyState(Model.parseState(statusOutput.text))
      }
    }
  }

  Process {
    id: openProcess
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.loadStatus() // refresh recent; opened videos stay visible until next R
    }
  }

  Process {
    id: configProcess
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.loadStatus()
        // Auto-refresh so editing tags immediately shows new classification
        Qt.callLater(function() {
          if (!root.busy && !runProcess.running) root.refresh()
        })
      }
    }
  }

  Component.onCompleted: root.loadStatus()
}
