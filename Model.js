// Helpers for parsing and presenting YouTube Suggestor state.
.pragma library

function stageLabel(stage) {
  switch (stage) {
    case "idle": return "Idle"
    case "history": return "Reading browser history…"
    case "feed": return "Fetching subscriptions feed…"
    case "transcribing": return "Transcribing videos…"
    case "ranking": return "Ranking against your interests…"
    case "done": return "Recommendations ready"
    case "error": return "Error"
    default: return stage
  }
}

function isBusy(stage) {
  return stage === "history" || stage === "feed" || stage === "transcribing" || stage === "ranking"
}

function parseState(text) {
  try {
    var data = JSON.parse(text)
    if (data && data.stage) return data
  } catch (err) {
    // fall through
  }
  return null
}

function recommendations(state) {
  return state && Array.isArray(state.recommendations) ? state.recommendations : []
}

function interests(state) {
  return state && Array.isArray(state.interests) ? state.interests : []
}

function progressText(state) {
  if (!state || !state.progress) return ""
  var p = state.progress
  if (!p.total) return ""
  return p.done + " / " + p.total
}

function progressFraction(state) {
  if (!state || !state.progress || !state.progress.total) return 0
  return Math.max(0, Math.min(1, state.progress.done / state.progress.total))
}

function scoreBadge(item) {
  if (!item) return ""
  if (item.score > 0 && item.matched && item.matched.length > 0) {
    return "★ " + item.score + " · " + item.matched.slice(0, 3).join(", ")
  }
  return "no keyword match"
}

function matchedItem(item) {
  return item && item.score > 0
}

function sourceLabel(item) {
  switch (item ? item.transcript_source : "") {
    case "captions": return "captions"
    case "whisper": return "whisper"
    default: return "no transcript"
  }
}
