// Helpers for parsing and presenting YouTube Suggester state.
.pragma library

function stageLabel(stage) {
  switch (stage) {
    case "idle": return "Idle"
    case "history": return "Reading watch history…"
    case "feed": return "Fetching subscriptions feed…"
    case "metadata": return "Scoring video tags…"
    case "enriching": return "Building descriptions…"
    case "ranking": return "Ranking against your interests…"
    case "done": return "Recommendations ready"
    case "error": return "Error"
    default: return stage
  }
}

function isBusy(stage) {
  return (
    stage === "history" || stage === "feed" || stage === "metadata"
    || stage === "enriching" || stage === "ranking"
  )
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

function recent(state) {
  return state && Array.isArray(state.recent) ? state.recent : []
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

function formatViewsPerHour(vph) {
  if (!vph) return ""
  if (vph >= 1000) return (vph / 1000).toFixed(1) + "k/hr"
  return vph + "/hr"
}

// "5h old · 18.0k/hr views" — freshness plus trending velocity.
function trendingBadge(item) {
  if (!item) return ""
  var parts = []
  if (item.age_label) parts.push(item.age_label + " old")
  var vph = item.views_per_hour || 0
  if (vph >= 100) parts.push(formatViewsPerHour(vph) + " views")
  return parts.join(" · ")
}

function transcriptBadge(item) {
  switch (item ? item.transcript_status : "") {
    case "working": return "◌ summarizing…"
    case "ready": return "✓ summary ready"
    case "unavailable": return "no usable transcript"
    default: return ""
  }
}

// Badge for a tab slot — empty when there is no real keyword match
// (fallback is now disabled, so mismatches simply don't appear).
function matchBadge(item) {
  if (!item) return ""
  var sb = scoreBadge(item)
  return sb === "no keyword match" ? "" : sb
}
