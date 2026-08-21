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

  readonly property string pluginId: manifest && manifest.id ? manifest.id : "io.github.kkosu.youtube-suggestor"
  readonly property var liveService: service || (bar && bar.shell ? bar.shell.serviceFor(pluginId) : null)
  readonly property var recs: liveService ? liveService.recommendations : []
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
      if (!root.liveService) return "YouTube Suggestor"
      var count = root.recs.length
      var line = count > 0 ? (count + " recommendations ready") : "No recommendations yet"
      if (root.busy) line = Model.stageLabel(root.stage)
      return "YouTube Suggestor\n" + line + "\nClick to open"
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
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function moveSelection(delta) {
    if (root.recs.length === 0) return
    selectedIndex = Math.max(0, Math.min(root.recs.length - 1, selectedIndex + delta))
    Qt.callLater(function() {
      recList.positionViewAtIndex(selectedIndex, ListView.Contain)
    })
  }

  function openSelected() {
    if (!root.liveService || root.recs.length === 0) return
    if (selectedIndex < root.recs.length) {
      root.liveService.openVideo(root.recs[selectedIndex].id)
    }
  }

  function startEditingInterests() {
    interestsDraft = root.liveService ? root.liveService.interests.join(", ") : ""
    editingInterests = true
    Qt.callLater(function() {
      interestsInput.forceActiveFocus()
      interestsInput.cursorPosition = interestsInput.text.length
    })
  }

  function commitInterests() {
    if (!root.liveService) return
    var keywords = interestsDraft.split(",").map(function(k) { return k.trim() }).filter(function(k) { return k.length > 0 })
    root.liveService.saveInterests(keywords.slice(0, 5))
    editingInterests = false
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
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
              text: "YouTube Suggestor"
              textFormat: Text.PlainText
              color: Color.foreground
              font.family: Style.font.family
              font.bold: true
              font.pixelSize: Style.font.subtitle
            }

            Text {
              text: {
                if (!root.liveService) return "Service unavailable"
                if (root.lastError !== "") return root.lastError
                if (root.busy) {
                  var p = Model.progressText(root.liveService.state)
                  return Model.stageLabel(root.stage) + (p ? " (" + p + ")" : "")
                }
                var base = Model.stageLabel(root.stage)
                if (root.liveService.updatedAt !== "") base += " · " + root.liveService.updatedAt
                return base
              }
              textFormat: Text.PlainText
              color: root.liveService && root.liveService.lastError !== "" ? Color.urgent : Qt.darker(Color.foreground, 1.5)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              Layout.fillWidth: true
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
            Layout.fillWidth: true
            text: root.interestsDraft
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: TextInput.NoWrap
            onTextChanged: root.interestsDraft = text
            onAccepted: root.commitInterests()
            Keys.onEscapePressed: function(event) {
              root.editingInterests = false
              event.accepted = true
              keyCatcher.forceActiveFocus()
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

        // Recommendations list
        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true

          ListView {
            id: recList
            anchors.fill: parent
            clip: true
            spacing: Style.space(10)
            model: root.recs
            visible: root.recs.length > 0
            currentIndex: root.selectedIndex

            delegate: Rectangle {
              id: recCard
              required property var modelData
              required property int index
              width: recList.width
              height: Math.max(thumb.height, recText.implicitHeight) + Style.space(16)
              radius: Style.rounding.small
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
                  radius: Style.rounding.small
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
                    text: (recCard.index + 1) + ". " + recCard.modelData.title
                    textFormat: Text.PlainText
                    color: Color.foreground
                    font.family: Style.font.family
                    font.bold: true
                    font.pixelSize: Style.font.bodySmall
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                  }

                  Text {
                    text: recCard.modelData.channel + " · " + recCard.modelData.duration_formatted + " · " + Model.sourceLabel(recCard.modelData)
                    textFormat: Text.PlainText
                    color: Qt.darker(Color.foreground, 1.5)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                  }

                  Text {
                    text: recCard.modelData.description
                    textFormat: Text.PlainText
                    color: Qt.darker(Color.foreground, 1.4)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                  }

                  Text {
                    text: Model.scoreBadge(recCard.modelData)
                    textFormat: Text.PlainText
                    visible: text !== ""
                    color: Model.matchedItem(recCard.modelData) ? Color.accent : Qt.darker(Color.foreground, 1.8)
                    font.family: Style.font.family
                    font.bold: Model.matchedItem(recCard.modelData)
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
            visible: root.recs.length === 0
            spacing: Style.space(8)

            Text {
              text: root.busy ? Model.stageLabel(root.stage) : "No recommendations yet"
              textFormat: Text.PlainText
              color: Qt.darker(Color.foreground, 1.5)
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              Layout.alignment: Qt.AlignHCenter
            }

            Text {
              text: root.busy
                ? (root.liveService ? (root.liveService.detail || "") : "")
                : "Set your interests (E), then press R to scan your feed"
              textFormat: Text.PlainText
              color: Qt.darker(Color.foreground, 1.8)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              Layout.alignment: Qt.AlignHCenter
            }
          }
        }

        // Footer keybindings bar
        Text {
          Layout.fillWidth: true
          text: "j / k navigate    o / Enter open    R rescan feed    E edit interests    Esc close"
          textFormat: Text.PlainText
          color: Qt.darker(Color.foreground, 1.5)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }

    Item {
      id: keyCatcher
      anchors.fill: card
      focus: true
      Keys.onPressed: function(event) {
        if (root.editingInterests) {
          if (event.key === Qt.Key_Escape) {
            root.editingInterests = false
            event.accepted = true
          }
          return // let the TextInput handle everything else
        }

        if (event.key === Qt.Key_Escape) {
          root.close()
          event.accepted = true
        } else if (event.text === "r" || event.text === "R") {
          if (root.liveService && !root.liveService.busy) root.liveService.refresh()
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
        } else if (event.text === "o" || event.text === "O" || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.openSelected()
          event.accepted = true
        }
      }
    }
  }
}
