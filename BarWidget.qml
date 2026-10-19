import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.alexllama.system-metrics"

  // Tuning, overridable per-widget from shell.json.
  readonly property int warnTemp: clampInt(setting("warnTemp", 70), 70, 40, 100)
  readonly property int critTemp: clampInt(setting("critTemp", 85), 85, 40, 110)
  readonly property int interval: clampInt(setting("interval", 2), 2, 1, 30)
  readonly property string diskPath: String(setting("diskPath", "/"))

  // Latest sample, mirrored from the sampler's JSON.
  property var metrics: ({})

  property bool popupOpen: false
  readonly property bool opened: popupOpen

  readonly property var cpu: metrics.cpu || ({})
  readonly property var temp: metrics.temp || ({})
  readonly property var mem: metrics.mem || ({})
  readonly property var disk: metrics.disk || ({})

  readonly property int cpuOverall: num(cpu.overall, 0)
  readonly property var perCoreCpu: Array.isArray(cpu.perCore) ? cpu.perCore : []
  readonly property var coreTemps: Array.isArray(temp.cores) ? temp.cores : []
  readonly property int maxTemp: num(temp.max, 0)
  readonly property bool tempKnown: maxTemp > 0
  readonly property int memPct: num(mem.usedPct, 0)
  readonly property int diskPct: num(disk.usedPct, -1)
  readonly property int fanRpm: num(metrics.fan, -1)
  readonly property int coreCount: Math.max(perCoreCpu.length, coreTemps.length)

  // Colour band for the hottest reading, and for any temperature value.
  readonly property color tempColor: tempBandColor(maxTemp)
  readonly property color fgColor: bar ? bar.foreground : Color.bar.text
  readonly property color dimColor: Qt.darker(fgColor, 1.35)
  readonly property color okColor: "#3fb950"
  readonly property color warnColor: "#d29922"
  readonly property color critColor: "#f85149"

  readonly property string label: tempKnown
    ? "CPU " + cpuOverall + "%  " + maxTemp + "\u00b0  MEM " + memPct + "%"
      + (diskPct >= 0 ? "  DISK " + diskPct + "%" : "")
    : "CPU " + cpuOverall + "%  MEM " + memPct + "%"
      + (diskPct >= 0 ? "  DISK " + diskPct + "%" : "")

  function num(value, fallback) {
    var n = Number(value)
    return isFinite(n) ? Math.round(n) : fallback
  }

  function clampInt(value, fallback, min, max) {
    var n = Number(value)
    if (!isFinite(n)) n = fallback
    return Math.max(min, Math.min(max, Math.round(n)))
  }

  function tempBandColor(value) {
    var t = num(value, 0)
    if (t <= 0) return fgColor
    if (t >= critTemp) return critColor
    if (t >= warnTemp) return warnColor
    return okColor
  }

  function usageBar(pct) {
    var p = Math.max(0, Math.min(100, num(pct, 0)))
    var filled = Math.round(p / 10)
    var out = ""
    for (var i = 0; i < 10; i++) out += (i < filled ? "\u2588" : "\u2591")
    return out
  }

  function refresh() {
    if (!sampleProc.running) sampleProc.running = true
  }

  function persist(key, value) {
    var entry = { id: root.moduleName }
    for (var k in root.settings) {
      if (k !== "id") entry[k] = root.settings[k]
    }
    entry[key] = value
    root.settings = entry
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function openBtop() {
    if (bar && typeof bar.run === "function") bar.run("omarchy-launch-floating-terminal-with-presentation btop")
  }

  // Hand the current readings to the user's default coding agent so it can
  // diagnose a hot machine. The prompt is built here so the agent starts with
  // real numbers rather than an empty session.
  function troubleshootWithAi() {
    if (!bar || typeof bar.run !== "function") return
    var lines = []
    lines.push("My laptop is running hot. Current readings from the Omarchy metrics widget:")
    lines.push("- CPU overall: " + cpuOverall + "%")
    if (tempKnown) lines.push("- Hottest core: " + maxTemp + "\u00b0C (warn at " + warnTemp + "\u00b0C, critical at " + critTemp + "\u00b0C)")
    if (num(temp.package, 0) > 0) lines.push("- Package: " + num(temp.package, 0) + "\u00b0C")
    if (perCoreCpu.length > 0) lines.push("- Per-thread CPU %: " + perCoreCpu.join(", "))
    if (coreTemps.length > 0) lines.push("- Per-core temps \u00b0C: " + coreTemps.join(", "))
    if (fanRpm >= 0) lines.push("- Fan: " + fanRpm + " RPM")
    lines.push("- Memory: " + memPct + "% used")
    if (diskPct >= 0) lines.push("- Disk " + diskPath + ": " + diskPct + "% used")
    lines.push("")
    lines.push("Find what is heating it up and what to do about it. Start by checking the top CPU consumers"
      + " (ps/btop), thermal throttling, fan control, and any runaway process. The host is Omarchy on Arch Linux.")
    var prompt = lines.join("\n")
    bar.run("omarchy agent prompt " + Util.shellQuote(prompt))
  }

  function open() { popupOpen = true }
  function close() { popupOpen = false }
  function toggle() { popupOpen = !popupOpen }
  function closeForPopoutSwitch() { popupOpen = false }

  Process {
    id: sampleProc
    command: ["bash", Quickshell.env("HOME") + "/.config/omarchy/plugins/io.github.alexllama.system-metrics/bin/metrics-sample", root.diskPath]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          if (parsed && typeof parsed === "object") root.metrics = parsed
        } catch (e) {
          // Leave the previous sample in place on a malformed read.
        }
      }
    }
  }

  Timer {
    interval: root.interval * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // --- Bar surface ---------------------------------------------------------
  // Numeric fields reserve space for the widest value they will ever hold
  // (100%, 100°). Measurement comes from hidden text so it matches the bar
  // font exactly; the reserved space is a trailing spacer so the label stays
  // tight to its number and the real gap falls between sections.
  Text {
    id: pctSizer
    visible: false
    text: "100%"
    font.family: bar ? bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.caption
  }
  Text {
    id: tempSizer
    visible: false
    text: "100\u00b0"
    font.family: bar ? bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.caption
  }
  readonly property real pctWidth: Math.ceil(pctSizer.implicitWidth)
  readonly property real tempWidth: Math.ceil(tempSizer.implicitWidth)

  // One measurer per live value, so a section's reserved space is exact (no
  // per-character estimate) and each binding reads its own Text.
  Text {
    id: cpuValSizer
    visible: false
    text: root.cpuOverall + "%"
    font.family: bar ? bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.caption
  }
  Text {
    id: tempValSizer
    visible: false
    text: root.maxTemp + "\u00b0"
    font.family: bar ? bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.caption
  }
  Text {
    id: memValSizer
    visible: false
    text: root.memPct + "%"
    font.family: bar ? bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.caption
  }
  Text {
    id: diskValSizer
    visible: false
    text: (root.diskPct >= 0 ? root.diskPct : 0) + "%"
    font.family: bar ? bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.caption
  }

  // Each section is a fixed-width Row: label, a small gap, then the value
  // left-aligned. Stability padding goes AFTER the value (a trailing spacer),
  // never before it, so the label sits tight against its own number and the
  // real breathing room falls between sections.
  readonly property real sectionGap: Style.space(3)

  implicitWidth: row.implicitWidth
  implicitHeight: barSize

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    spacing: root.sectionGap


    // CPU <pct>
    Row {
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(3)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "CPU"
        color: root.dimColor
        font.family: bar ? bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.cpuOverall + "%"
        color: root.fgColor
        font.family: bar ? bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
      }

      // Absorbs the width difference between "9%" and "100%".
      Item {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, root.pctWidth - cpuValSizer.implicitWidth)
        height: 1
      }
    }

    // <temp>
    Row {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.tempKnown
      spacing: 0

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.maxTemp + "\u00b0"
        color: root.tempColor
        font.family: bar ? bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: root.tempKnown && root.maxTemp >= root.warnTemp
      }

      Item {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, root.tempWidth - tempValSizer.implicitWidth)
        height: 1
      }
    }

    // MEM <pct>
    Row {
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(3)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "MEM"
        color: root.dimColor
        font.family: bar ? bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.memPct + "%"
        color: root.dimColor
        font.family: bar ? bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
      }

      Item {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, root.pctWidth - memValSizer.implicitWidth)
        height: 1
      }
    }

    // DISK <pct>
    Row {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.diskPct >= 0
      spacing: Style.space(3)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.diskPct >= 0
        text: "DISK"
        color: root.dimColor
        font.family: bar ? bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: (root.diskPct >= 0 ? root.diskPct : 0) + "%"
        color: root.dimColor
        font.family: bar ? bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
      }

      Item {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, root.pctWidth - diskValSizer.implicitWidth)
        height: 1
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) root.openBtop()
      else root.toggle()
    }
  }

  // --- Click popup: per-core detail and thresholds -------------------------
  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(300))
    contentHeight: popup.fittedContentHeight(Math.max(menuColumn.childrenRect.height, Style.space(200)))

    Column {
      id: menuColumn
      width: parent.width
      spacing: Style.space(10)

      Text {
        text: "System Metrics"
        color: root.fgColor
        font.family: bar ? bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      // Summary line, same as the bar but expanded.
      Text {
        width: parent.width
        text: root.tempKnown
          ? "CPU " + root.cpuOverall + "%   hottest core " + root.maxTemp + "\u00b0"
            + (num(root.temp.package, 0) > 0 ? "   package " + num(root.temp.package, 0) + "\u00b0" : "")
          : "CPU " + root.cpuOverall + "%"
        color: root.dimColor
        font.family: bar ? bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      // Per-core table.
      Row {
        width: parent.width
        spacing: Style.space(6)

        Text {
          text: "Core"
          color: root.dimColor
          font.family: bar ? bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          width: parent.width * 0.16
        }
        Text {
          text: "Usage"
          color: root.dimColor
          font.family: bar ? bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          width: parent.width * 0.44
        }
        Text {
          text: "Temp"
          color: root.dimColor
          font.family: bar ? bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }

      Repeater {
        model: root.coreCount

        Row {
          required property int index
          width: menuColumn.width
          spacing: Style.space(6)

          Text {
            text: "C" + index
            color: root.dimColor
            font.family: bar ? bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
            width: parent.width * 0.16
          }
          Text {
            text: root.usageBar(root.perCoreCpu[index] !== undefined ? root.perCoreCpu[index] : 0)
              + "  " + (root.perCoreCpu[index] !== undefined ? root.perCoreCpu[index] : 0) + "%"
            color: root.fgColor
            font.family: bar ? bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
            width: parent.width * 0.44
          }
          Text {
            text: root.coreTemps[index] !== undefined ? root.coreTemps[index] + "\u00b0" : "--"
            color: root.tempBandColor(root.coreTemps[index])
            font.family: bar ? bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Qt.rgba(root.fgColor.r, root.fgColor.g, root.fgColor.b, 0.15)
      }

      Text {
        width: parent.width
        text: "Mem " + root.memPct + "%"
          + (num(root.mem.total, 0) > 0
              ? "  (" + fmtGb(num(root.mem.total, 0) - num(root.mem.avail, 0)) + " / " + fmtGb(num(root.mem.total, 0)) + " GiB)"
              : "")
        color: root.fgColor
        font.family: bar ? bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        visible: root.diskPct >= 0
        width: parent.width
        text: "Disk " + root.diskPath + "  " + (root.diskPct >= 0 ? root.diskPct : 0) + "%"
          + (num(root.disk.availKb, 0) > 0 ? "  (" + fmtGb(num(root.disk.availKb, 0) / 1024 / 1024) + " GiB free)" : "")
        color: root.fgColor
        font.family: bar ? bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        visible: root.fanRpm >= 0
        width: parent.width
        text: "Fan " + (root.fanRpm >= 0 ? root.fanRpm : 0) + " RPM"
        color: root.fgColor
        font.family: bar ? bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Qt.rgba(root.fgColor.r, root.fgColor.g, root.fgColor.b, 0.15)
      }

      // --- Thresholds, compact: label + value share one line, slider under --
      Text {
        text: "Thresholds"
        color: root.dimColor
        font.family: bar ? bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      Column {
        width: parent.width
        spacing: Style.space(2)

        Row {
          width: parent.width
          Text {
            width: parent.width * 0.7
            text: "Warn"
            color: root.fgColor
            font.family: bar ? bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            width: parent.width * 0.3
            horizontalAlignment: Text.AlignRight
            text: root.warnTemp + "\u00b0C"
            color: root.warnColor
            font.family: bar ? bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }

        PanelSlider {
          width: parent.width
          bar: root.bar
          minimum: 40
          maximum: 100
          step: 1
          integer: true
          value: root.warnTemp
          onMoved: function(v) { root.persist("warnTemp", v) }
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(2)

        Row {
          width: parent.width
          Text {
            width: parent.width * 0.7
            text: "Critical"
            color: root.fgColor
            font.family: bar ? bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            width: parent.width * 0.3
            horizontalAlignment: Text.AlignRight
            text: root.critTemp + "\u00b0C"
            color: root.critColor
            font.family: bar ? bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }

        PanelSlider {
          width: parent.width
          bar: root.bar
          minimum: 40
          maximum: 110
          step: 1
          integer: true
          value: root.critTemp
          onMoved: function(v) { root.persist("critTemp", v) }
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(2)

        Row {
          width: parent.width
          Text {
            width: parent.width * 0.7
            text: "Refresh"
            color: root.fgColor
            font.family: bar ? bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            width: parent.width * 0.3
            horizontalAlignment: Text.AlignRight
            text: root.interval + "s"
            color: root.dimColor
            font.family: bar ? bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }

        PanelSlider {
          width: parent.width
          bar: root.bar
          minimum: 1
          maximum: 30
          step: 1
          integer: true
          value: root.interval
          onMoved: function(v) { root.persist("interval", v) }
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Qt.rgba(root.fgColor.r, root.fgColor.g, root.fgColor.b, 0.15)
      }

      Button {
        width: parent.width
        text: "Troubleshoot with AI"
        bordered: true
        foreground: root.fgColor
        accent: Color.accent
        fontFamily: bar ? bar.fontFamily : Style.font.family
        onClicked: { root.close(); root.troubleshootWithAi() }
      }

      Button {
        width: parent.width
        text: "Open btop"
        bordered: true
        foreground: root.fgColor
        accent: Color.accent
        fontFamily: bar ? bar.fontFamily : Style.font.family
        onClicked: { root.close(); root.openBtop() }
      }
    }
  }

  function fmtGb(kb) {
    return (kb / 1024 / 1024).toFixed(1)
  }
}
