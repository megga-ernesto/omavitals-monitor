import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Quickshell.Io
import qs.Commons as Commons
import qs.Ui as Ui
import "ProcessModel.js" as Model

ColumnLayout {
  id: panel

  required property bool running
  required property var translate
  required property var formatNumber
  required property var formatSpeed
  readonly property color ink: Commons.Color.popups.text
  readonly property color muted: Qt.rgba(ink.r, ink.g, ink.b, 0.73)
  readonly property color surface: Qt.rgba(ink.r, ink.g, ink.b, 0.065)
  readonly property int pageSize: 10
  property var sampleData: null
  property bool failed: false
  property string sort: "cpu"
  property string filter: "all"
  property string grouping: "single"
  property var expanded: ({})
  property int page: 0
  readonly property var results: Model.build(sampleData ? sampleData.rows : [], search.text, filter, sort, grouping, expanded)
  readonly property int pages: Math.max(1, Math.ceil(results.rows.length / pageSize))
  readonly property int currentPage: Math.min(page, pages - 1)

  spacing: Commons.Style.space(8)

  component Label: Text {
    textFormat: Text.PlainText
    color: panel.ink
    font.family: Commons.Style.font.family
    font.pixelSize: Commons.Style.font.bodySmall
  }

  function options(keys) {
    return keys.map(key => ({value: key, label: translate("process." + key)}))
  }

  function duration(seconds) {
    const minutes = Math.floor(seconds / 60)
    if (minutes === 0)
      return translate("process.seconds").arg(formatNumber(Math.floor(seconds), 0))
    if (minutes < 60)
      return translate("process.minutes").arg(formatNumber(minutes, 0))
    const hours = Math.floor(minutes / 60)
    if (hours < 24)
      return translate("process.hours").arg(formatNumber(hours, 0)).arg(formatNumber(minutes % 60, 0))
    return translate("process.days").arg(formatNumber(Math.floor(hours / 24), 0)).arg(formatNumber(hours % 24, 0))
  }

  function sample() {
    if (running && !collector.running)
      collector.running = true
  }

  function toggleGroup(key) {
    const next = Object.assign({}, expanded)
    if (next[key]) delete next[key]
    else next[key] = true
    expanded = next
  }

  Process {
    id: collector
    command: ["python3", "-B", decodeURIComponent(Qt.resolvedUrl("processes.py").toString().replace(/^file:\/\//, ""))]
    stdout: StdioCollector { id: output }
    onExited: function(code, status) {
      if (!panel.running) return
      if (code === 0 && status === 0) {
        try {
          panel.sampleData = Model.update(JSON.parse(output.text), panel.sampleData)
          panel.failed = false
          return
        } catch (error) {
          console.warn("OmaVitals: invalid process snapshot", error)
        }
      }
      panel.sampleData = null
      panel.failed = true
    }
  }

  Timer {
    interval: 2500
    repeat: true
    triggeredOnStart: true
    running: panel.running
    onTriggered: panel.sample()
  }

  Label {
    text: panel.translate("process.title")
    font.bold: true
    font.pixelSize: Commons.Style.space(17)
    Layout.topMargin: Commons.Style.space(10)
  }

  Ui.TextField {
    id: search
    Layout.fillWidth: true
    placeholderText: panel.translate("process.search")
    background: Ui.BorderSurface {
      radius: Commons.Style.space(8)
      color: Commons.Style.controlFill(search.activeFocus, search.hovered,
        Commons.Color.popups.text, Commons.Color.accent)
      borderSpec: Commons.Border.controlSpec(search.activeFocus ? "focus"
        : (search.hovered ? "hover-cursor" : "normal"), Commons.Color.popups.text, Commons.Color.accent)
    }
    onTextChanged: panel.page = 0
  }

  GridLayout {
    Layout.fillWidth: true
    columns: width >= Commons.Style.space(385) ? 3 : 1
    columnSpacing: Commons.Style.space(7)
    rowSpacing: Commons.Style.space(5)
    RoundedSelect {
      Layout.fillWidth: true
      label: panel.translate("process.filter")
      value: panel.filter
      options: panel.options(["all", "cpuActive", "memoryActive", "diskActive", "running"])
      onChanged: value => { panel.filter = value; panel.page = 0 }
    }
    RoundedSelect {
      Layout.fillWidth: true
      label: panel.translate("process.sort")
      value: panel.sort
      options: panel.options(["cpu", "ram", "io", "age", "name"])
      onChanged: value => { panel.sort = value; panel.page = 0 }
    }
    RoundedSelect {
      Layout.fillWidth: true
      label: panel.translate("process.group")
      value: panel.grouping
      options: panel.options(["single", "program", "family"])
      onChanged: value => {
        panel.grouping = value
        panel.expanded = ({})
        panel.page = 0
      }
    }
  }

  Label {
    Layout.fillWidth: true
    wrapMode: Text.WordWrap
    color: panel.muted
    text: panel.failed ? panel.translate("unavailable")
        : !panel.sampleData ? panel.translate("waiting")
        : panel.sampleData.truncated ? panel.translate("process.limited")
        : panel.results.count === 0 ? panel.translate("process.noMatches")
        : panel.translate("process.matches").arg(panel.formatNumber(panel.results.count, 0))
  }

  Repeater {
    model: Math.min(panel.pageSize, panel.results.rows.length - panel.currentPage * panel.pageSize)
    delegate: Rectangle {
      id: entry
      required property int index
      readonly property var row: panel.results.rows[panel.currentPage * panel.pageSize + index] || {}
      readonly property bool group: !!row.group
      readonly property bool isExpanded: !!panel.expanded[row.key]
      implicitHeight: line.implicitHeight + Commons.Style.space(16)
      Layout.fillWidth: true
      Layout.minimumWidth: 0
      Layout.leftMargin: row.child ? Commons.Style.space(15) : 0
      radius: Commons.Style.space(10)
      color: panel.surface

      ColumnLayout {
        id: line
        anchors.fill: parent
        anchors.margins: Commons.Style.space(8)
        spacing: Commons.Style.space(3)

        RowLayout {
          Layout.fillWidth: true
          Label {
            text: entry.row.name || panel.translate("process.parent").arg(entry.row.parentPid)
            font.bold: true
            Layout.fillWidth: true
            elide: Text.ElideRight
          }
          RoundedButton {
            visible: entry.group
            text: (entry.isExpanded ? "▾ " : "▸ ") + panel.formatNumber(entry.row.items ? entry.row.items.length : 0, 0)
            hint: panel.translate(entry.isExpanded ? "process.collapse" : "process.expand")
            focusable: true
            bordered: true
            verticalPadding: Commons.Style.space(2)
            onClicked: panel.toggleGroup(entry.row.key)
          }
        }

        Label {
          Layout.fillWidth: true
          elide: Text.ElideRight
          color: panel.muted
          text: entry.group
            ? (entry.row.parentPid !== null ? panel.translate("process.parent").arg(entry.row.parentPid) + " · " : "")
              + panel.translate("process.oldest").arg(panel.duration(entry.row.age))
            : panel.translate("process.identity").arg(entry.row.pid).arg(entry.row.parent)
              .arg(panel.translate("process.state." + (["R", "S", "D", "T", "t", "Z", "I"].includes(entry.row.state) ? entry.row.state : "other")))
              .arg(panel.duration(entry.row.age))
        }

        Label {
          visible: !!entry.row.executable
          Layout.fillWidth: true
          color: panel.muted
          elide: Text.ElideMiddle
          text: entry.row.executable || ""
        }

        Label {
          Layout.fillWidth: true
          wrapMode: Text.WordWrap
          text: panel.translate("process.usage")
            .arg(entry.row.cpu === null ? "—" : panel.formatNumber(entry.row.cpu, 1) + "%")
            .arg(panel.formatNumber(entry.row.ram / 1048576, 1) + " MiB")
            .arg(entry.row.io === null ? "—" : panel.formatSpeed(entry.row.io))
        }
      }
    }
  }

  RowLayout {
    visible: panel.pages > 1
    Layout.fillWidth: true
    RoundedButton {
      text: panel.translate("process.previous")
      enabled: panel.currentPage > 0
      focusable: true
      bordered: true
      onClicked: panel.page = panel.currentPage - 1
    }
    Label {
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignHCenter
      text: panel.translate("process.page").arg(panel.formatNumber(panel.currentPage + 1, 0)).arg(panel.formatNumber(panel.pages, 0))
    }
    RoundedButton {
      text: panel.translate("process.next")
      enabled: panel.currentPage + 1 < panel.pages
      focusable: true
      bordered: true
      onClicked: panel.page = panel.currentPage + 1
    }
  }

  Label {
    Layout.fillWidth: true
    wrapMode: Text.WordWrap
    color: panel.muted
    text: panel.translate("process.units")
  }
}
