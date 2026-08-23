import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root

  property var service: null
  property var shell: null
  property var manifest: null

  property int selectedIndex: 0
  property bool editingInterests: false
  property string interestsDraft: ""
  property string activeTag: ""
  property bool showSummaryPopup: false
  property string popupTitle: ""
  property string popupSummary: ""
  property var popupItem: null
  readonly property var popupLiveItem: {
    if (!popupItem) return null
    var pid = popupItem.id || ""
    for (var i = 0; i < root.recs.length; i++) {
      if (root.recs[i].id === pid) return root.recs[i]
    }
    // Fallback to snapshot if not found (e.g., video dismissed)
    return popupItem
  }

  readonly property string pluginId: manifest && manifest.id ? manifest.id : "io.github.kkosu.youtube-suggester"
  readonly property var liveService: service || (bar && bar.shell ? bar.shell.serviceFor(pluginId) : null)
  readonly property var recs: liveService ? liveService.recommendations : []
  readonly property var recentItems: liveService ? (liveService.recent || []) : []
  // One tab per tag + Others, all videos for that tag sorted by popularity
  readonly property var tabNames: {
    var names = []
    for (var i = 0; i < root.recs.length; i++) {
      var t = root.recs[i].tag || "Others"
      if (names.indexOf(t) === -1) names.push(t)
    }
    // Keep Others last for consistency
    var othersIdx = names.indexOf("Others")
    if (othersIdx !== -1) {
      names.splice(othersIdx, 1)
      names.push("Others")
    }
    return names
  }
  readonly property var visibleRecs: {
    if (!root.activeTag || root.tabNames.indexOf(root.activeTag) === -1) {
      return root.recs
    }
    return root.recs.filter(function(r) { return (r.tag || "Others") === root.activeTag })
  }
  readonly property var listModel: root.visibleRecs.length > 0 ? root.visibleRecs : root.recentItems
  readonly property bool showingRecent: root.visibleRecs.length === 0 && root.recentItems.length > 0
  readonly property bool busy: liveService ? liveService.busy : false
  readonly property string stage: liveService ? liveService.stage : "idle"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰗃"
    fontSize: Style.font.caption
    foreground: root.bar ? root.bar.barForeground : Color.foreground
    tooltipText: {
      if (!root.liveService) return "YouTube Suggester"
      var count = root.recs.length
      var line = count > 0 ? (count + " videos · last 24h") : "No videos in last 24h"
      if (root.busy) line = Model.stageLabel(root.stage)
      return "YouTube Suggester\n" + line + "\nClick to open"
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) {
        if (root.liveService && !root.liveService.busy) root.liveService.refresh()
        return
      }
      if (root.bar && root.bar.shell) root.toggle()
    }
  }

  onOpenedChanged: if (opened) {
    selectedIndex = 0
    editingInterests = false
    showSummaryPopup = false
    activeTag = root.tabNames.length > 0 ? root.tabNames[0] : ""
    if (liveService) liveService.loadStatus()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onTabNamesChanged: {
    if (root.tabNames.indexOf(root.activeTag) === -1) {
      activeTag = root.tabNames.length > 0 ? root.tabNames[0] : ""
      selectedIndex = 0
    }
  }

  function moveSelection(delta) {
    if (root.visibleRecs.length === 0) return
    selectedIndex = Math.max(0, Math.min(root.visibleRecs.length - 1, selectedIndex + delta))
    Qt.callLater(function() {
      recList.positionViewAtIndex(selectedIndex, ListView.Contain)
    })
  }

  function openSelected() {
    if (!root.liveService || root.visibleRecs.length === 0) return
    if (selectedIndex < root.visibleRecs.length) {
      root.liveService.openVideo(root.visibleRecs[selectedIndex].id)
    }
  }

  function summarizeSelected() {
    if (!root.liveService || root.visibleRecs.length === 0) return
    if (selectedIndex < root.visibleRecs.length) {
      var sel = root.visibleRecs[selectedIndex]
      if (sel.transcript_status === "working") return
      if (sel.transcript_status === "ready" && sel.summary) {
        // Already summarized — just show popup
        openSummaryPopup()
        return
      }
      root.liveService.summarize(sel.id)
    }
  }

  function summarizeAllInTag() {
    if (!root.liveService || root.visibleRecs.length === 0) return
    if (!root.activeTag || root.activeTag === "Others") return
    var ids = []
    for (var i = 0; i < root.visibleRecs.length; i++) {
      var it = root.visibleRecs[i]
      if (!it || it.transcript_status === "working") continue
      if (it.summary && it.summary.length > 0) continue
      if (it.transcript_status === "ready") continue
      ids.push(it.id)
    }
    if (ids.length === 0) return
    if (root.liveService.summarizeAll) {
      root.liveService.summarizeAll(ids)
    } else {
      // Fallback single
      for (var j = 0; j < ids.length; j++) root.liveService.summarize(ids[j])
    }
  }

  function openSummaryPopup() {
    if (root.visibleRecs.length === 0) return
    var sel = root.visibleRecs[selectedIndex]
    if (!sel) return
    popupItem = sel
    popupTitle = sel.title || ""
    if (sel.summary && sel.summary.length > 0) {
      // Keep original description at the bottom as requested
      var orig = sel.meta_description || sel.description || ""
      if (orig && orig.length > 0) {
        popupSummary = sel.summary + "\n\n— — —\nOriginal description:\n" + orig
      } else {
        popupSummary = sel.summary
      }
    } else if (sel.transcript_status === "working") {
      popupSummary = "Summarizing… please wait. The summary will appear here when ready."
    } else if (sel.description && sel.description.length > 0) {
      popupSummary = sel.description
      if (sel.meta_description && sel.meta_description.length > sel.description.length) {
        popupSummary = sel.meta_description
      }
    } else if (sel.meta_description) {
      popupSummary = sel.meta_description
    } else {
      popupSummary = "No description available. Press T to summarize via transcript."
    }
    showSummaryPopup = true
    // Reset scroll to top when opening
    Qt.callLater(function() {
      if (summaryFlick) summaryFlick.contentY = 0
    })
  }

  function closeSummaryPopup() {
    showSummaryPopup = false
  }

  function toggleSummaryPopup() {
    if (showSummaryPopup) {
      closeSummaryPopup()
    } else {
      openSummaryPopup()
    }
  }

  function selectTab(index) {
    if (root.tabNames.length === 0) return
    index = Math.max(0, Math.min(root.tabNames.length - 1, index))
    if (root.tabNames[index] === root.activeTag) return
    activeTag = root.tabNames[index]
    selectedIndex = 0
    showSummaryPopup = false
  }

  function cycleTab(delta) {
    if (root.tabNames.length === 0) return
    var current = root.tabNames.indexOf(root.activeTag)
    if (current === -1) current = 0
    selectTab((current + delta + root.tabNames.length) % root.tabNames.length)
  }

  function startEditingInterests() {
    interestsDraft = root.liveService ? root.liveService.interests.join(", ") : ""
    editingInterests = true
    Qt.callLater(function() {
      interestsInput.text = interestsDraft
      interestsInput.forceActiveFocus()
      interestsInput.cursorPosition = interestsInput.text.length
    })
  }

  function commitInterests() {
    if (!root.liveService) {
      editingInterests = false
      return
    }
    var keywords = interestsDraft.split(",").map(function(k) { return k.trim() }).filter(function(k) { return k.length > 0 }).slice(0, 5)
    root.liveService.saveInterests(keywords)
    editingInterests = false
    activeTag = ""
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: root.editingInterests ? interestsInput : keyCatcher
    contentWidth: Style.space(700)
    contentHeight: Style.space(640)

    Rectangle {
      id: card
      anchors.fill: parent
      color: "transparent"

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.space(16)
        spacing: Style.space(12)

        // Header
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(10)

          Text {
            text: "󰗃"
            textFormat: Text.PlainText
            font.family: Style.fontFamily
            font.pixelSize: Style.font.title
            color: "#ff4444"
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(2)

            Text {
              text: "YouTube Suggester · last 24h"
              textFormat: Text.PlainText
              color: Color.foreground
              font.family: Style.font.family
              font.bold: true
              font.pixelSize: Style.font.subtitle
            }

            Text {
              text: {
                if (root.liveService && root.liveService.summarizing) {
                  var t = root.liveService.summarizingItem
                    ? (root.liveService.summarizingItem.title || "") : ""
                  var q = root.liveService.summarizeQueue ? root.liveService.summarizeQueue.length : 0
                  var queued = q > 0 ? " · " + q + " queued" : ""
                  return "Summarizing" + (t ? ": " + t : "…") + queued + " — you can close this panel"
                }
                if (root.liveService && root.liveService.lastError !== "") return root.liveService.lastError
                if (root.busy) {
                  var s = root.liveService ? root.liveService.state : null
                  var p = s ? Model.progressText(s) : ""
                  return Model.stageLabel(root.stage) + (p ? " (" + p + ")" : "")
                }
                var base = Model.stageLabel(root.stage)
                if (root.liveService && root.liveService.updatedAt) base += " · " + root.liveService.updatedAt
                if (!root.liveService) base += " (service starting…)"
                return base
              }
              textFormat: Text.PlainText
              color: root.liveService && root.liveService.lastError !== "" ? Color.urgent : Qt.darker(Color.foreground, 1.5)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              Layout.fillWidth: true
              Layout.minimumWidth: 0
            }
          }
        }

        // Progress bar while the pipeline runs
        ProgressBar {
          Layout.fillWidth: true
          visible: root.busy
          from: 0
          to: 1
          value: root.liveService ? Model.progressFraction(root.liveService.state) : 0
        }

        // Refresh button — now R
        Rectangle {
          id: findButton
          Layout.fillWidth: true
          implicitHeight: findLabel.implicitHeight + Style.space(14)
          radius: Style.cornerRadius
          color: !root.liveService || root.busy
            ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.06)
            : findMouse.containsPress
              ? Color.accent
              : findMouse.containsMouse
                ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.28)
                : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.15)

          Text {
            id: findLabel
            anchors.centerIn: parent
            text: (root.busy)
              ? Model.stageLabel(root.stage) + "…"
              : "󰍉  Refresh last 24h   [R]"
            textFormat: Text.PlainText
            color: root.busy ? Qt.darker(Color.foreground, 1.6) : Color.accent
            font.family: Style.font.family
            font.bold: true
            font.pixelSize: Style.font.bodySmall
          }

          MouseArea {
            id: findMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: root.liveService && !root.busy
            onClicked: root.liveService.refresh()
          }
        }

        // Interests row / editor
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Text {
            text: "Interests:"
            textFormat: Text.PlainText
            color: Qt.darker(Color.foreground, 1.5)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          // Keyword chips
          Row {
            visible: !root.editingInterests
            spacing: Style.space(6)
            Layout.fillWidth: true

            Repeater {
              model: root.liveService ? root.liveService.interests : []

              Rectangle {
                required property var modelData
                radius: height / 2
                color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18)
                implicitHeight: chipLabel.implicitHeight + Style.space(6)
                implicitWidth: chipLabel.implicitWidth + Style.space(14)

                Text {
                  id: chipLabel
                  anchors.centerIn: parent
                  text: parent.modelData
                  textFormat: Text.PlainText
                  color: Color.accent
                  font.family: Style.font.family
                  font.bold: true
                  font.pixelSize: Style.font.caption
                }
              }
            }

            Text {
              visible: (root.liveService ? root.liveService.interests.length : 0) === 0
              text: "none set — press E to add up to 5 keywords"
              textFormat: Text.PlainText
              color: Qt.darker(Color.foreground, 1.8)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.italic: true
            }
          }

          TextInput {
            id: interestsInput
            visible: root.editingInterests
            focus: root.editingInterests
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            clip: true
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: TextInput.NoWrap
            selectByMouse: true
            onTextChanged: root.interestsDraft = text
            onAccepted: root.commitInterests()
            Keys.onReturnPressed: function(event) {
              root.commitInterests()
              event.accepted = true
            }
            Keys.onEnterPressed: function(event) {
              root.commitInterests()
              event.accepted = true
            }
            Keys.onEscapePressed: function(event) {
              root.editingInterests = false
              event.accepted = true
              Qt.callLater(function() { keyCatcher.forceActiveFocus() })
            }
          }

          Text {
            visible: !root.editingInterests
            text: "[E] edit"
            textFormat: Text.PlainText
            color: Qt.darker(Color.foreground, 1.8)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        // Tag tabs — one per interest tag + Others
        Row {
          visible: root.tabNames.length > 0 && !root.showingRecent
          spacing: Style.space(6)
          Layout.fillWidth: true

          Repeater {
            model: root.tabNames

            Rectangle {
              id: tabButton
              required property var modelData
              required property int index
              readonly property bool isActive: modelData === root.activeTag
              readonly property int count: {
                var n = 0
                for (var i = 0; i < root.recs.length; i++) if ((root.recs[i].tag || "Others") === modelData) n++
                return n
              }
              radius: Style.cornerRadius
              implicitHeight: tabLabel.implicitHeight + Style.space(10)
              implicitWidth: Math.min(
                tabLabel.implicitWidth + Style.space(18),
                Style.space(150)
              )
              color: isActive
                ? Color.accent
                : tabMouse.containsMouse
                  ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22)
                  : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.10)

              Text {
                id: tabLabel
                anchors.centerIn: parent
                text: (tabButton.index + 1) + " " + tabButton.modelData + " (" + tabButton.count + ")"
                textFormat: Text.PlainText
                elide: Text.ElideRight
                width: tabButton.width - Style.space(12)
                horizontalAlignment: Text.AlignHCenter
                color: tabButton.isActive ? "white" : Color.accent
                font.family: Style.font.family
                font.bold: tabButton.isActive
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                id: tabMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                  root.selectTab(tabButton.index)
                  keyCatcher.forceActiveFocus()
                }
              }
            }
          }
        }

        // Recommendations / recently-opened list
        ColumnLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: Style.space(6)

          Text {
            visible: root.listModel.length > 0
            text: root.showingRecent
              ? "Recently opened"
              : (root.activeTag || "All") + " · " + root.visibleRecs.length + " videos"
            textFormat: Text.PlainText
            color: Qt.darker(Color.foreground, 1.5)
            font.family: Style.font.family
            font.bold: true
            font.pixelSize: Style.font.caption
          }

          Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
              id: recList
              anchors.fill: parent
              clip: true
              spacing: Style.space(10)
              model: root.listModel
              visible: root.listModel.length > 0
              currentIndex: root.selectedIndex

            delegate: Rectangle {
              id: recCard
              required property var modelData
              required property int index
              width: recList.width
              height: Math.max(thumb.height, recText.implicitHeight) + Style.space(16)
              radius: Style.cornerRadius
              color: recCard.index === root.selectedIndex
                ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12)
                : "transparent"
              border.color: recCard.index === root.selectedIndex ? Color.accent : Color.popups.border
              border.width: recCard.index === root.selectedIndex ? 2 : 1

              RowLayout {
                anchors.fill: parent
                anchors.margins: Style.space(8)
                spacing: Style.space(10)

                // Thumbnail
                Rectangle {
                  id: thumb
                  width: Style.space(128)
                  height: Style.space(72)
                  radius: Style.cornerRadius
                  clip: true
                  color: Qt.darker(Color.foreground, 2.5)

                  Image {
                    anchors.fill: parent
                    source: recCard.modelData.thumbnail || ""
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    visible: status === Image.Ready
                  }

                  Text {
                    anchors.centerIn: parent
                    visible: !parent.visible
                    text: "▶"
                    textFormat: Text.PlainText
                    color: Qt.darker(Color.foreground, 1.8)
                    font.pixelSize: Style.font.subtitle
                  }
                }

                ColumnLayout {
                  id: recText
                  Layout.fillWidth: true
                  spacing: Style.space(3)

                  Text {
                    text: recCard.modelData.title || ""
                    textFormat: Text.PlainText
                    color: Color.foreground
                    font.family: Style.font.family
                    font.bold: true
                    font.pixelSize: Style.font.bodySmall
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                  }

                  Text {
                    text: {
                      if (root.showingRecent) {
                        return recCard.modelData.channel + " · opened " + (recCard.modelData.opened_at || "")
                      }
                      var parts = [
                        recCard.modelData.channel,
                        recCard.modelData.duration_formatted
                      ]
                      var trend = Model.trendingBadge(recCard.modelData)
                      if (trend !== "") parts.push(trend)
                      return parts.join(" · ")
                    }
                    textFormat: Text.PlainText
                    color: Qt.darker(Color.foreground, 1.5)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                  }

                  Text {
                    text: recCard.modelData.description || ""
                    textFormat: Text.PlainText
                    visible: text !== ""
                    color: Qt.darker(Color.foreground, 1.4)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                  }

                  Text {
                    text: {
                      if (root.showingRecent) return ""
                      var parts = []
                      var mb = Model.matchBadge(recCard.modelData)
                      if (mb !== "") parts.push(mb)
                      var isQueued = root.liveService && root.liveService.summarizeQueue && root.liveService.summarizeQueue.indexOf(recCard.modelData.id) !== -1
                      var isCurrent = root.liveService && root.liveService.currentSummarizeId === recCard.modelData.id
                      if (recCard.modelData.summary) {
                        parts.push("✓ summary ready [S]")
                      } else if (isQueued) {
                        var pos = root.liveService.summarizeQueue.indexOf(recCard.modelData.id) + 1
                        parts.push("○ queued #" + pos)
                      } else if (isCurrent || recCard.modelData.transcript_status === "working") {
                        parts.push("◌ summarizing…")
                      } else {
                        var tb = Model.transcriptBadge(recCard.modelData)
                        if (tb !== "") parts.push(tb)
                      }
                      return parts.join(" · ")
                    }
                    textFormat: Text.PlainText
                    visible: text !== ""
                    color: {
                      if (root.showingRecent) return Qt.darker(Color.foreground, 1.8)
                      var isQ = root.liveService && root.liveService.summarizeQueue && root.liveService.summarizeQueue.indexOf(recCard.modelData.id) !== -1
                      var isC = root.liveService && root.liveService.currentSummarizeId === recCard.modelData.id
                      if (recCard.modelData.summary || recCard.modelData.transcript_status === "ready" || isQ || isC || Model.matchedItem(recCard.modelData)) return Color.accent
                      return Qt.darker(Color.foreground, 1.8)
                    }
                    font.family: Style.font.family
                    font.bold: {
                      if (root.showingRecent) return false
                      var isQ2 = root.liveService && root.liveService.summarizeQueue && root.liveService.summarizeQueue.indexOf(recCard.modelData.id) !== -1
                      var isC2 = root.liveService && root.liveService.currentSummarizeId === recCard.modelData.id
                      return recCard.modelData.transcript_status === "ready" || !!recCard.modelData.summary || isQ2 || isC2 || Model.matchedItem(recCard.modelData)
                    }
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                  }
                }
              }

              MouseArea {
                anchors.fill: parent
                z: -1
                onClicked: {
                  root.selectedIndex = recCard.index
                  keyCatcher.forceActiveFocus()
                }
                onDoubleClicked: root.openSelected()
              }
            }

            ScrollBar.vertical: ScrollBar {}
          }

            // Empty state
            ColumnLayout {
              anchors.centerIn: parent
              visible: root.listModel.length === 0 && !root.busy
              spacing: Style.space(8)

              Text {
                text: "No videos in last 24h"
                textFormat: Text.PlainText
                color: Qt.darker(Color.foreground, 1.5)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                Layout.alignment: Qt.AlignHCenter
              }

              Text {
                text: root.liveService && root.liveService.interests.length === 0
                  ? "Set your tags with E, then press R"
                  : "No matches — check Others tab or press R"
                textFormat: Text.PlainText
                color: Qt.darker(Color.foreground, 1.8)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                Layout.alignment: Qt.AlignHCenter
              }
            }
          }
        }

        // Footer keybindings bar — wraps instead of overflowing the panel
        Text {
          Layout.fillWidth: true
          text: "R refresh  ·  Shift+R + recommended  ·  E edit tags  ·  T summarize  ·  Shift+T all in tag  ·  S description/summary  ·  o / Enter open  ·  j / k scroll or navigate  ·  ←/→ or 1-5 tabs  ·  Esc close"
          textFormat: Text.PlainText
          color: Qt.darker(Color.foreground, 1.5)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }
      }

      // Summary popup overlay
      Rectangle {
        id: summaryPopup
        anchors.fill: parent
        visible: root.showSummaryPopup
        color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.96)
        radius: Style.cornerRadius
        border.color: Color.accent
        border.width: 2

        // Dismiss on outside click
        MouseArea {
          anchors.fill: parent
          onClicked: root.closeSummaryPopup()
        }

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.space(16)
          spacing: Style.space(12)

          RowLayout {
            Layout.fillWidth: true
            Text {
              text: "Summary"
              textFormat: Text.PlainText
              color: Color.accent
              font.family: Style.font.family
              font.bold: true
              font.pixelSize: Style.font.subtitle
              Layout.fillWidth: true
            }
            Text {
              text: "[j/k] scroll  ·  [S] close  ·  [Esc] close"
              textFormat: Text.PlainText
              color: Qt.darker(Color.foreground, 1.8)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          Text {
            text: root.popupTitle
            textFormat: Text.PlainText
            color: Color.foreground
            font.family: Style.font.family
            font.bold: true
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            elide: Text.ElideRight
            maximumLineCount: 2
          }

          Flickable {
            id: summaryFlick
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentHeight: summaryText.implicitHeight
            contentWidth: width
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            TextEdit {
              id: summaryText
              width: parent.width
              textFormat: TextEdit.PlainText
              // Live binding so summary appears automatically when ready
              text: {
                var it = root.popupLiveItem
                if (!it) return root.popupSummary
                if (it.summary && it.summary.length > 0) {
                  var orig = it.meta_description || it.description || ""
                  return orig ? it.summary + "\n\n— — —\nOriginal description:\n" + orig : it.summary
                }
                if (it.transcript_status === "working") return "Summarizing… please wait. The summary will appear here when ready."
                // Fallback to description/meta for plain S popup
                if (root.popupSummary && root.popupSummary.length > 0) return root.popupSummary
                return it.meta_description || it.description || "No description available."
              }
              readOnly: true
              wrapMode: TextEdit.Wrap
              selectByMouse: true
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              // Transparent background handled by parent
            }
          }

          RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            Rectangle {
              implicitHeight: okLabel.implicitHeight + Style.space(8)
              implicitWidth: okLabel.implicitWidth + Style.space(20)
              radius: Style.cornerRadius
              color: Color.accent
              Text {
                id: okLabel
                anchors.centerIn: parent
                text: "Close [S / Esc]"
                textFormat: Text.PlainText
                color: "white"
                font.family: Style.font.family
                font.bold: true
                font.pixelSize: Style.font.caption
              }
              MouseArea {
                anchors.fill: parent
                onClicked: root.closeSummaryPopup()
                cursorShape: Qt.PointingHandCursor
              }
            }
          }
        }
      }
    }

    Item {
      id: keyCatcher
      anchors.fill: card
      focus: true
      Keys.onPressed: function(event) {
        // Popup has priority
        if (root.showSummaryPopup) {
          if (event.key === Qt.Key_Escape || event.text === "s" || event.text === "S") {
            root.closeSummaryPopup()
            event.accepted = true
            return
          }
          // Allow Enter to also close popup
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.closeSummaryPopup()
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Down || event.text === "j" || event.text === "J") {
            summaryFlick.contentY = Math.min(Math.max(0, summaryFlick.contentHeight - summaryFlick.height), summaryFlick.contentY + 60)
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Up || event.text === "k" || event.text === "K") {
            summaryFlick.contentY = Math.max(0, summaryFlick.contentY - 60)
            event.accepted = true
            return
          }
          return
        }

        if (root.editingInterests) {
          if (event.key === Qt.Key_Escape) {
            root.editingInterests = false
            event.accepted = true
            Qt.callLater(function() { keyCatcher.forceActiveFocus() })
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.commitInterests()
            event.accepted = true
          }
          return
        }

        if (event.key === Qt.Key_Escape) {
          root.close()
          event.accepted = true
        } else if (event.text === "R") {
          // Shift+R: subscriptions + YouTube Recommended (limit 20)
          if (root.liveService && !root.liveService.busy) {
            if (root.liveService.refreshWithRecommended) root.liveService.refreshWithRecommended()
            else root.liveService.refresh()
          }
          event.accepted = true
        } else if (event.text === "r") {
          if (root.liveService && !root.liveService.busy) root.liveService.refresh()
          event.accepted = true
        } else if (event.text === "T") {
          // Shift+T: summarize all videos in current tag (not Others)
          root.summarizeAllInTag()
          event.accepted = true
        } else if (event.text === "t") {
          root.summarizeSelected()
          event.accepted = true
        } else if (event.text === "s" || event.text === "S") {
          root.toggleSummaryPopup()
          event.accepted = true
        } else if (event.text === "e" || event.text === "E") {
          root.startEditingInterests()
          event.accepted = true
        } else if (event.key === Qt.Key_Down || event.text === "j" || event.text === "J") {
          root.moveSelection(1)
          event.accepted = true
        } else if (event.key === Qt.Key_Up || event.text === "k" || event.text === "K") {
          root.moveSelection(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Right || event.text === "l") {
          root.cycleTab(1)
          event.accepted = true
        } else if (event.key === Qt.Key_Left || event.text === "h") {
          root.cycleTab(-1)
          event.accepted = true
        } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
          var tabIdx = event.key - Qt.Key_1
          if (tabIdx < root.tabNames.length) {
            root.selectTab(tabIdx)
            event.accepted = true
          }
        } else if (event.text === "o" || event.text === "O" || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.openSelected()
          event.accepted = true
        }
      }
    }
  }
}
