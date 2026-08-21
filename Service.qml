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
  property int transcribed: state.transcribed || 0
  property int watchedCount: state.watched_count || 0
  property string lastError: state.error || ""
  property string updatedAt: state.updated_at || ""
  property bool busy: Model.isBusy(stage)

  readonly property string engineScript: {
    var raw = Qt.resolvedUrl("bin/omarchy-youtube-suggestor").toString()
    return raw.indexOf("file://") === 0 ? raw.substring(7) : raw
  }

  signal runFinished(bool success, string message)

  function refresh() {
    if (runProcess.running) return
    lastError = ""
    runProcess.command = [engineScript, "run"]
    runProcess.running = true
  }

  function openVideo(videoId) {
    if (!videoId || openProcess.running) return
    openProcess.command = [engineScript, "open", videoId]
    openProcess.running = true
  }

  function transcribe(videoId) {
    if (!videoId || transcribeProcess.running) return
    transcribeProcess.command = [engineScript, "transcribe", videoId]
    transcribeProcess.running = true
  }

  readonly property bool transcribing: transcribeProcess.running
  readonly property var transcribingItem: state.transcribing || null

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
      if (exitCode !== 0 && !root.busy) {
        root.lastError = String(runError.text || "Pipeline failed").trim()
        root.runFinished(false, root.lastError)
      } else {
        root.loadStatus() // reconcile final state from disk
      }
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
  }

  Process {
    id: transcribeProcess
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      root.loadStatus() // pick up the finished transcript summary
    }
  }

  // While a background transcription runs, keep the panel state fresh.
  Timer {
    interval: 1500
    repeat: true
    running: transcribeProcess.running
    onTriggered: root.loadStatus()
  }

  Process {
    id: configProcess
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.loadStatus()
    }
  }

  Component.onCompleted: root.loadStatus()
}
