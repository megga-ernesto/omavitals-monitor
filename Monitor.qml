import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import qs.Ui as Ui

Ui.BarWidget {
  id: root
  moduleName: "elmegga.omavitals-monitor"

  readonly property var metrics: [
    { key: "cpu", icon: "󰻠" },
    { key: "ram", icon: "󰍛" },
    { key: "zram", icon: "󰘋" },
    { key: "swap", icon: "󰓡" },
    { key: "gpu", icon: "󰢮" },
    { key: "disk", icon: "󰋊", shortKey: "diskShort" },
    { key: "network", icon: "󰛳", shortKey: "networkShort" },
    { key: "storage", icon: "󰆼", shortKey: "storageShort" },
    { key: "battery", icon: "󰁹", shortKey: "batteryShort" },
    { key: "temperature", icon: "󰔏", shortKey: "temperatureShort" }
  ]
  readonly property var modes: ["icons", "both", "text"]
  readonly property var columnOptions: [1, 2, 3, 4]
  readonly property int cardsPerRow: {
    const count = Number(setting("cardsPerRow", 2))
    return columnOptions.includes(count) ? count : 2
  }
  readonly property var activeKeys: {
    const configured = setting("metrics", ["cpu", "ram"])
    return metrics.filter(m => Array.isArray(configured) && configured.includes(m.key)).map(m => m.key)
  }
  readonly property var displayedMetrics: metrics.filter(m => activeKeys.includes(m.key))
  readonly property string mode: modes.includes(setting("mode", "both")) ? setting("mode", "both") : "both"
  readonly property int fontSize: sizeSetting("fontSize", 12)
  readonly property int iconSize: sizeSetting("iconSize", 15)
  readonly property int historySize: 30
  readonly property color panelInk: Commons.Color.popups.text
  readonly property color softInk: Qt.rgba(panelInk.r, panelInk.g, panelInk.b, 0.73)
  property var history: ({})
  property var hardware: ({})
  property bool showingSettings: false
  property var previous: null
  property var readings: ({})
  property bool saveFailed: false
  property bool sampled: false
  property bool opened: false
  property bool popoutSwitchClosing: false

  implicitWidth: vertical ? barSize : strip.implicitWidth + Commons.Style.space(12)
  implicitHeight: vertical ? strip.implicitHeight + Commons.Style.space(10) : barSize

  function sizeSetting(key, fallback) {
    const value = Number(setting(key, fallback))
    return Number.isFinite(value) ? Math.max(8, Math.min(24, Math.round(value))) : fallback
  }

  function open() {
    if (bar && !opened) {
      showingSettings = false
      opened = true
      if (!hardwareCollector.running) hardwareCollector.running = true
    }
  }
  function close() { opened = false }
  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(() => { root.popoutSwitchClosing = false })
  }

  function save(key, value) {
    const entry = Object.assign({}, settings, {id: moduleName})
    entry[key] = value
    saveFailed = !bar || !bar.shell || !bar.shell.updateEntryInline(moduleName, entry)
    if (!saveFailed)
      settings = entry
  }

  function toggleMetric(key, enabled) {
    save("metrics", enabled ? activeKeys.concat([key]) : activeKeys.filter(item => item !== key))
  }

  function sample() {
    if (activeKeys.length && !collector.running) {
      const path = decodeURIComponent(Qt.resolvedUrl("metrics.py").toString().replace(/^file:\/\//, ""))
      collector.command = ["python3", path].concat(activeKeys)
      collector.running = true
    }
  }

  function rates(now, before, elapsed) {
    if (!now || !before || elapsed <= 0)
      return null
    const names = Object.keys(now)
    if (!names.length)
      return [0, 0]
    const speeds = [0, 0]
    let matched = false
    for (const name of names) {
      if (!before[name] || now[name].some((value, i) => value < before[name][i]))
        continue
      matched = true
      for (let i = 0; i < speeds.length; ++i)
        speeds[i] += (now[name][i] - before[name][i]) / elapsed
    }
    return matched ? speeds : null
  }

  function accept(snapshot) {
    const next = snapshot.values
    if (previous) {
      const time = snapshot.time - previous.time
      const cpu = snapshot.counters.cpu
      const oldCpu = previous.counters.cpu
      if (cpu && oldCpu && cpu[0] > oldCpu[0]) {
        const idle = Math.max(0, cpu[1] - oldCpu[1])
        next.cpu = [Math.max(0, 1 - idle / (cpu[0] - oldCpu[0])) * 100, "%"]
      }
      next.disk = rates(snapshot.counters.disk, previous.counters.disk, time)
      next.network = rates(snapshot.counters.network, previous.counters.network, time)
    }
    previous = snapshot
    readings = next
    appendHistory(next)
    sampled = true
  }

  function level(key, value) {
    if (!value)
      return null
    if (key === "ram" || key === "swap" || key === "storage")
      return value[1] > 0 ? 100 * value[0] / value[1] : null
    if (value[1] === "%")
      return value[0]
    return null
  }

  function usageColor(key, value, fallback, background) {
    // zram has no utilization gauge. In savings mode, color its visible percentage.
    const percentage = key === "zram" && value && value[0] > 0
      && readingMode(key, readingModes(key)) === "savedPercent"
      ? 100 * (value[0] - value[1]) / value[0] : level(key, value)
    if (percentage === null || key === "battery")
      return fallback

    // Thresholds follow the same whole-percent reading shown in the panel.
    const usage = Math.round(percentage)
    const light = 0.2126 * background.r + 0.7152 * background.g + 0.0722 * background.b > 0.55
    if (usage >= 91) return light ? "#b81b32" : "#ff5363"
    if (usage >= 81) return light ? "#9a481b" : "#eda88a"
    if (usage >= 71) return light ? "#766014" : "#e2d3a1"
    return fallback
  }

  function trendValue(key, value) {
    if (!value)
      return null
    const percent = level(key, value)
    if (percent !== null)
      return percent
    if (key === "disk" || key === "network")
      return value[0] + value[1]
    if (key === "zram")
      return value[1]
    if (key === "swap" || key === "storage" || key === "ram")
      return null
    return value[0]
  }

  function appendHistory(values) {
    const next = {}
    for (const key of activeKeys) {
      const points = history[key] || []
      const priorGpu = key === "gpu" && values.gpu && previousTrendGpuUnit !== values.gpu[1]
      next[key] = (priorGpu ? [] : points.slice(1 - historySize)).concat([trendValue(key, values[key])])
    }
    if (values.gpu)
      previousTrendGpuUnit = values.gpu[1]
    history = next
  }

  property string previousTrendGpuUnit: ""

  onActiveKeysChanged: {
    const next = {}
    for (const key of activeKeys)
      if (history[key]) next[key] = history[key]
    history = next
    if (activeKeys.length) {
      Qt.callLater(root.sample)
    } else {
      previous = null
      readings = ({})
      sampled = false
    }
  }

  function number(value, decimals) {
    return Commons.I18n.formatNumber(value, decimals)
  }

  function speed(value) {
    if (value >= 1024 * 1024)
      return number(value / (1024 * 1024), 1) + " MiB/s"
    return number(value / 1024, 0) + " KiB/s"
  }

  function readingModes(key) {
    switch (key) {
    case "ram":
    case "swap":
    case "storage":
      return ["auto", "used", "remaining", "total", "usedPercent", "remainingPercent",
              "usedRemaining", "usedTotal"]
    case "cpu":
      return ["usedPercent", "idlePercent"]
    case "gpu":
      return readings.gpu && readings.gpu[1] === "%" ? ["usedPercent", "idlePercent"] : []
    case "battery":
      return ["remainingPercent", "usedPercent"]
    case "zram":
      return ["auto", "physicalMemory", "originalSize", "savedMemory", "savedPercent"]
    case "disk":
      return ["readWrite", "read", "write", "combinedRate"]
    case "network":
      return ["downloadUpload", "download", "upload", "combinedRate"]
    case "temperature":
      return ["celsius", "fahrenheit"]
    default:
      return []
    }
  }

  function readingMode(key, options) {
    const configured = setting("readingModes", {})[key]
    return options.includes(configured) ? configured : options[0]
  }

  function saveReadingMode(key, mode) {
    const formats = Object.assign({}, setting("readingModes", {}))
    formats[key] = mode
    save("readingModes", formats)
  }

  function percent(part, total) {
    return total > 0 ? number(100 * part / total, 0) + "%" : "—"
  }

  function capacityLabel(used, total, mode) {
    const remaining = Math.max(0, total - used)
    switch (mode) {
    case "usedPercent": return percent(used, total)
    case "remainingPercent": return percent(remaining, total)
    case "remaining": return number(remaining, 1) + " GiB"
    case "total": return number(total, 1) + " GiB"
    case "usedRemaining": return number(used, 1) + " / " + number(remaining, 1) + " GiB"
    case "usedTotal": return number(used, 1) + " / " + number(total, 1) + " GiB"
    default: return number(used, 1) + " GiB"
    }
  }

  function label(key, detailed) {
    const value = readings[key]
    if (!value)
      return detailed ? strings.t(sampled ? "unavailable" : "waiting") : "—"
    const mode = readingMode(key, readingModes(key))
    switch (key) {
    case "disk":
    case "network":
      if (mode === "read" || mode === "download")
        return "↓" + speed(value[0])
      if (mode === "write" || mode === "upload")
        return "↑" + speed(value[1])
      if (mode === "combinedRate")
        return speed(value[0] + value[1])
      return "↓" + speed(value[0]) + "  ↑" + speed(value[1])
    case "ram":
    case "swap":
    case "storage":
      return capacityLabel(value[0], value[1], mode === "auto" && detailed ? "usedTotal" : mode)
    case "zram":
      if (mode === "originalSize")
        return number(value[0], 0) + " MiB"
      if (mode === "savedMemory")
        return number(value[0] - value[1], 0) + " MiB"
      if (mode === "savedPercent")
        return percent(value[0] - value[1], value[0])
      if (mode === "auto" && detailed)
        return number(value[0], 0) + " → " + number(value[1], 0) + " MiB"
      return number(value[1], 0) + " MiB"
    case "temperature":
      return mode === "fahrenheit" ? number(value[0] * 9 / 5 + 32, 0) + " °F"
                                   : number(value[0], 0) + " °C"
    default:
      if (value[1] !== "%")
        return number(value[0], 0) + " " + value[1]
      return number(mode === "idlePercent" || (key === "battery" && mode === "usedPercent")
                    ? 100 - value[0] : value[0], 0) + "%"
    }
  }

  function detailLines(key) {
    const value = readings[key]
    const gib = bytes => number(bytes / 1073741824, 1) + " GiB"
    const models = (items, format) => (items || []).slice(0, 3).map(format)
    const capacity = () => value ? [
      strings.t("hardware.capacity").arg(number(value[1], 1) + " GiB"),
      strings.t("hardware.available").arg(number(Math.max(0, value[1] - value[0]), 1) + " GiB")
    ] : []
    switch (key) {
    case "cpu":
      return hardware.cpu ? [hardware.cpu[0], strings.t("hardware.threads").arg(number(hardware.cpu[1], 0))] : []
    case "temperature":
      return hardware.cpu ? [hardware.cpu[0]] : []
    case "ram":
      return capacity()
    case "swap":
      return capacity().concat((hardware.swap || []).slice(0, 4).join(", "))
    case "storage":
      return capacity().concat(hardware.storage ? "/ · " + hardware.storage : "")
    case "gpu":
      return models(hardware.gpu, row => [row[0], row[1],
        row[2] !== null ? strings.t("hardware.vram").arg(gib(row[2])) : ""].filter(Boolean).join(" · "))
    case "disk":
      return models(hardware.disk, row => [row[1] || row[0], row[2] ? gib(row[2]) : ""].filter(Boolean).join(" · "))
    case "network":
      return [(hardware.network || []).slice(0, 5).join(", "), strings.t("hardware.networkRate")]
    case "zram":
      return models(hardware.zram, row => [row[0], row[1],
        row[2] ? strings.t("hardware.capacity").arg(number(row[2], 0) + " MiB") : ""].filter(Boolean).join(" · "))
    case "battery":
      return models(hardware.battery, row => row[1] === null ? row[0]
        : row[0] + " · " + strings.t("hardware.health").arg(number(row[1], 0) + "%"))
    default:
      return []
    }
  }

  Process {
    id: hardwareCollector
    command: ["python3", "-B", decodeURIComponent(Qt.resolvedUrl("hardware.py").toString().replace(/^file:\/\//, ""))]
    stdout: StdioCollector { id: hardwareOutput }
    onExited: function(code, status) {
      if (code === 0 && status === 0) {
        try { root.hardware = JSON.parse(hardwareOutput.text) }
        catch (error) { console.warn("OmaVitals: invalid hardware snapshot", error) }
      }
    }
  }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  Process {
    id: collector
    stdout: StdioCollector { id: output }
    onExited: function(exitCode, exitStatus) {
      if (exitCode === 0 && exitStatus === 0) {
        try {
          if (root.activeKeys.length)
            root.accept(JSON.parse(output.text))
          return
        } catch (error) {
          console.warn("OmaVitals: invalid metrics snapshot", error)
        }
      }
      root.previous = null
      root.readings = ({})
      root.appendHistory({})
      root.sampled = true
    }
  }

  Timer {
    interval: 2000
    repeat: true
    running: root.activeKeys.length > 0
    triggeredOnStart: true
    onTriggered: root.sample()
  }

  Ui.WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    tooltipText: strings.t("title")
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton || mouseButton === Qt.RightButton)
        root.opened ? root.close() : root.open()
    }

    GridLayout {
      id: strip
      anchors.centerIn: parent
      columns: root.vertical ? 1 : Math.max(1, root.displayedMetrics.length)
      columnSpacing: Commons.Style.space(9)
      rowSpacing: Commons.Style.space(4)

      Text {
        visible: !root.displayedMetrics.length
        textFormat: Text.PlainText
        text: "󰄨"
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: root.iconSize
      }

      Repeater {
        model: root.displayedMetrics
        delegate: GridLayout {
          id: metricBadge
          required property var modelData
          readonly property color ink: root.usageColor(modelData.key, root.readings[modelData.key],
            button.foreground, root.bar ? root.bar.background : Commons.Color.background)
          columns: root.vertical ? 1 : 2
          columnSpacing: Commons.Style.space(4)
          rowSpacing: 0
          Layout.alignment: Qt.AlignCenter

          Text {
            visible: root.mode !== "text"
            textFormat: Text.PlainText
            text: modelData.icon
            color: metricBadge.ink
            font.family: button.fontFamily
            font.pixelSize: root.iconSize
            Layout.alignment: Qt.AlignCenter
          }
          Text {
            visible: root.mode !== "icons"
            textFormat: Text.PlainText
            text: {
              const reading = root.label(modelData.key, false)
              if (root.vertical)
                return reading.replace("  ↑", "\n↑")
              if (root.mode === "both")
                return reading
              return strings.t(modelData.shortKey || modelData.key) + " " + reading
            }
            color: metricBadge.ink
            font.family: button.fontFamily
            font.pixelSize: root.fontSize
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            Layout.maximumWidth: root.vertical ? root.barSize : implicitWidth
          }
        }
      }
    }
  }

  Ui.KeyboardPanel {
    id: panel
    bar: root.bar
    anchorItem: button
    owner: root
    open: root.opened
    focusTarget: loadedContent
    contentWidth: fittedContentWidth(Commons.Style.space(
      Math.max(530, Math.min(root.cardsPerRow, root.displayedMetrics.length) * 250 + 30)))
    contentHeight: fittedContentHeight(loadedContentHeight, Commons.Style.space(660))

    content: FocusScope {
      id: page
      // KeyboardPanel owns the outer chrome. Bind only its ancestor surface,
      // so this widget can round its popup using the current Omarchy theme.
      readonly property var outerSurface: {
        let ancestor = parent
        while (ancestor) {
          if (ancestor instanceof Ui.BorderSurface)
            return ancestor
          ancestor = ancestor.parent
        }
        return null
      }

      Binding {
        target: page.outerSurface
        property: "radius"
        value: Commons.Style.space(16)
        when: page.outerSurface !== null
      }

      anchors.fill: parent
      implicitHeight: panelLayout.implicitHeight
      Keys.onEscapePressed: {
        if (root.showingSettings) root.showingSettings = false
        else root.close()
      }

      component PanelText: Text {
        textFormat: Text.PlainText
        color: root.panelInk
        font.family: Commons.Style.font.family
        font.pixelSize: Commons.Style.font.body
      }

      component Card: Rectangle {
        radius: Commons.Style.space(12)
        color: Qt.rgba(root.panelInk.r, root.panelInk.g, root.panelInk.b, 0.065)
        border.color: Qt.rgba(root.panelInk.r, root.panelInk.g, root.panelInk.b, 0.15)
        border.width: 1
      }

      component QuickButton: RoundedButton {
        foreground: root.panelInk
        bordered: true
        focusable: true
        fontSize: Commons.Style.font.bodySmall
        iconSize: Commons.Style.space(14)
        horizontalPadding: Commons.Style.space(6)
        verticalPadding: Commons.Style.space(3)
        Accessible.name: hint || text
      }

      component SizeControl: RowLayout {
        id: sizeControl
        required property string label
        required property int size
        signal modified(int value)
        spacing: Commons.Style.space(4)

        PanelText {
          text: sizeControl.label
          font.pixelSize: Commons.Style.font.bodySmall
          color: root.softInk
        }
        QuickButton {
          text: "−"
          hint: strings.t("decreaseSize").arg(sizeControl.label)
          enabled: sizeControl.size > 8
          onClicked: sizeControl.modified(sizeControl.size - 1)
        }
        PanelText {
          text: root.number(sizeControl.size, 0)
          horizontalAlignment: Text.AlignHCenter
          Layout.preferredWidth: Commons.Style.space(18)
          font.pixelSize: Commons.Style.font.bodySmall
        }
        QuickButton {
          text: "+"
          hint: strings.t("increaseSize").arg(sizeControl.label)
          enabled: sizeControl.size < 24
          onClicked: sizeControl.modified(sizeControl.size + 1)
        }
      }

      ColumnLayout {
        id: panelLayout
        anchors.fill: parent
        spacing: Commons.Style.space(12)

        RowLayout {
          Layout.fillWidth: true
          spacing: Commons.Style.space(12)

          ColumnLayout {
            spacing: Commons.Style.space(3)
            Layout.fillWidth: true
            PanelText {
              text: strings.t("title")
              font.pixelSize: Commons.Style.space(19)
              font.bold: true
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
            PanelText {
              text: strings.t("historyWindow")
              font.pixelSize: Commons.Style.font.bodySmall
              color: root.softInk
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
          }

          RoundedButton {
            iconText: "󰓅"
            fontFamily: button.fontFamily
            selected: scroll.atProcesses
            hint: strings.t(scroll.atProcesses ? "backToCharts" : "process.title")
            foreground: root.panelInk
            bordered: true
            focusable: true
            Accessible.name: hint
            onClicked: {
              if (scroll.contentItem)
                scroll.contentItem.contentY = scroll.atProcesses ? scroll.contentItem.originY
                                                                 : scroll.processPosition
            }
          }

          RoundedButton {
            iconText: "󰒓"
            selected: root.showingSettings
            fontFamily: button.fontFamily
            hint: strings.t(root.showingSettings ? "hideSettings" : "settingsTitle")
            foreground: root.panelInk
            bordered: true
            focusable: true
            Accessible.name: hint
            onClicked: {
              root.showingSettings = !root.showingSettings
              if (root.showingSettings && scroll.contentItem)
                scroll.contentItem.contentY = 0
            }
          }
        }

        QQC.ScrollView {
          id: scroll
          readonly property real processOffset: view.item
            ? Math.max(0, Math.min(view.item.processY, contentHeight - availableHeight)) : 0
          readonly property real processPosition: (contentItem ? contentItem.originY : 0) + processOffset
          readonly property bool atProcesses: !!contentItem && processOffset > 1
            && contentItem.contentY >= processPosition - 1
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.preferredHeight: view.implicitHeight
          clip: true
          contentWidth: availableWidth
          contentHeight: view.implicitHeight
          QQC.ScrollBar.horizontal.policy: QQC.ScrollBar.AlwaysOff

          Loader {
            id: view
            width: scroll.availableWidth
            sourceComponent: dashboard
            onLoaded: {
              if (scroll.contentItem)
                scroll.contentItem.contentY = 0
            }
          }
        }
      }

      Component {
        id: dashboard

        ColumnLayout {
          readonly property real processY: processes.y
          spacing: Commons.Style.space(10)

          Item {
            id: reveal
            Layout.fillWidth: true
            property real revealedHeight: root.showingSettings ? controls.implicitHeight + Commons.Style.space(16) : 0
            Layout.preferredHeight: revealedHeight
            visible: height > 0 || root.showingSettings
            enabled: root.showingSettings
            clip: true
            Behavior on revealedHeight {
              NumberAnimation { duration: Commons.Style.duration(180); easing.type: Easing.OutCubic }
            }

            Card {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              height: controls.implicitHeight + Commons.Style.space(16)

              ColumnLayout {
                id: controls
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Commons.Style.space(8)
                spacing: Commons.Style.space(6)

                Flow {
                  Layout.fillWidth: true
                  spacing: Commons.Style.space(8)

                  RowLayout {
                    spacing: Commons.Style.space(3)
                    Repeater {
                      model: root.modes
                      QuickButton {
                        required property string modelData
                        iconText: modelData === "icons" ? "󰘔" : modelData === "text" ? "󰊄" : "󰌹"
                        fontFamily: button.fontFamily
                        hint: strings.t(modelData)
                        selected: root.mode === modelData
                        onClicked: root.save("mode", modelData)
                      }
                    }
                  }

                  RowLayout {
                    spacing: Commons.Style.space(3)
                    PanelText {
                      text: strings.t("columnsShort")
                      color: root.softInk
                      font.pixelSize: Commons.Style.font.bodySmall
                    }
                    Repeater {
                      model: root.columnOptions
                      QuickButton {
                        required property int modelData
                        text: root.number(modelData, 0)
                        hint: strings.t("cardsPerRow") + " · " + text
                        selected: root.cardsPerRow === modelData
                        onClicked: root.save("cardsPerRow", modelData)
                      }
                    }
                  }

                  SizeControl {
                    label: strings.t("fontShort")
                    size: root.fontSize
                    onModified: value => root.save("fontSize", value)
                  }

                  SizeControl {
                    label: strings.t("iconsShort")
                    size: root.iconSize
                    onModified: value => root.save("iconSize", value)
                  }
                }

                Rectangle {
                  Layout.fillWidth: true
                  implicitHeight: 1
                  color: Qt.rgba(root.panelInk.r, root.panelInk.g, root.panelInk.b, 0.15)
                }

                Flow {
                  Layout.fillWidth: true
                  spacing: Commons.Style.space(4)

                  Repeater {
                    model: root.metrics
                    QuickButton {
                      required property var modelData
                      text: strings.t(modelData.shortKey || modelData.key)
                      hint: strings.t(modelData.key)
                      selected: root.activeKeys.includes(modelData.key)
                      Accessible.role: Accessible.CheckBox
                      Accessible.checked: selected
                      onClicked: root.toggleMetric(modelData.key, !selected)
                    }
                  }
                }

                PanelText {
                  visible: root.saveFailed
                  text: strings.t("saveError")
                  color: Commons.Color.urgent
                }
              }
            }
          }

          GridLayout {
            id: cards
            Layout.fillWidth: true
            columns: Math.max(1, Math.min(root.cardsPerRow, root.displayedMetrics.length,
              Math.floor((width + columnSpacing) / (Commons.Style.space(190) + columnSpacing))))
            uniformCellWidths: true
            uniformCellHeights: true
            columnSpacing: Commons.Style.space(10)
            rowSpacing: Commons.Style.space(10)

            Repeater {
              model: root.displayedMetrics

              delegate: Card {
                id: card
                required property var modelData
                readonly property string metricKey: modelData.key
                readonly property var reading: root.readings[metricKey]
                readonly property var samples: root.history[metricKey] || []
                readonly property var level: root.level(metricKey, reading)
                readonly property color highlight: root.usageColor(metricKey, reading,
                  Commons.Color.accent, Commons.Color.popups.background)
                readonly property color readingInk: root.usageColor(metricKey, reading,
                  root.panelInk, Commons.Color.popups.background)

                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 1
                implicitHeight: cardBody.implicitHeight + Commons.Style.space(24)

                ColumnLayout {
                  id: cardBody
                  anchors.fill: parent
                  anchors.margins: Commons.Style.space(12)
                  spacing: Commons.Style.space(7)

                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Commons.Style.space(7)
                    PanelText {
                      text: card.modelData.icon
                      color: card.highlight
                      font.family: button.fontFamily
                      font.pixelSize: Commons.Style.space(17)
                    }
                    PanelText {
                      text: strings.t(card.modelData.shortKey || card.metricKey)
                      font.bold: true
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                    }
                    QuickButton {
                      readonly property var options: root.readingModes(card.metricKey)
                      readonly property string current: root.readingMode(card.metricKey, options) || ""
                      visible: root.showingSettings && options.length > 1
                      iconText: "󰑓"
                      fontFamily: button.fontFamily
                      hint: strings.t("cycleReading").arg(strings.t("reading." + current))
                      onClicked: {
                        const next = (options.indexOf(current) + 1) % options.length
                        root.saveReadingMode(card.metricKey, options[next])
                      }
                    }
                  }

                  PanelText {
                    text: root.label(card.metricKey, true)
                    color: card.readingInk
                    font.pixelSize: Commons.Style.space(15)
                    font.bold: true
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                    Layout.minimumHeight: Commons.Style.space(25)
                  }

                  PanelText {
                    readonly property var lines: root.detailLines(card.metricKey).filter(Boolean)
                    visible: lines.length > 0
                    Layout.fillWidth: true
                    text: lines.join("\n")
                    color: root.softInk
                    font.pixelSize: Commons.Style.font.bodySmall
                    wrapMode: Text.Wrap
                  }

                  Sparkline {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Commons.Style.space(35)
                    points: card.samples
                    tint: card.highlight
                    capacity: root.historySize
                    ceiling: card.level === null ? 0 : 100
                    Accessible.ignored: true
                  }

                  RowLayout {
                    visible: card.level !== null
                    Layout.fillWidth: true
                    Rectangle {
                      id: track
                      Layout.fillWidth: true
                      implicitHeight: Commons.Style.space(5)
                      radius: height / 2
                      color: Qt.rgba(card.highlight.r, card.highlight.g, card.highlight.b, 0.18)
                      Rectangle {
                        anchors.left: parent.left
                        height: parent.height
                        width: track.width * Math.max(0, Math.min(1, Number(card.level) / 100))
                        radius: height / 2
                        color: card.highlight
                        Behavior on width {
                          NumberAnimation { duration: Commons.Style.duration(160); easing.type: Easing.OutCubic }
                        }
                      }
                    }
                    PanelText {
                      color: root.softInk
                      font.pixelSize: Commons.Style.font.bodySmall
                      text: (card.metricKey === "battery" ? strings.t("reading.remainingPercent")
                                                          : strings.t("reading.usedPercent"))
                            + " · " + root.number(Number(card.level), 0) + "%"
                    }
                  }
                }
              }
            }
          }

          Card {
            visible: !root.displayedMetrics.length
            Layout.fillWidth: true
            implicitHeight: emptyMessage.implicitHeight + Commons.Style.space(44)

            PanelText {
              id: emptyMessage
              width: parent.width - Commons.Style.space(32)
              anchors.centerIn: parent
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              text: strings.t("noMetrics")
              color: root.softInk
            }
          }

          ProcessPanel {
            id: processes
            Layout.fillWidth: true
            running: root.opened
            translate: key => strings.t(key)
            formatNumber: (value, decimals) => root.number(value, decimals)
            formatSpeed: value => root.speed(value)
          }
        }
      }

    }
  }
}
