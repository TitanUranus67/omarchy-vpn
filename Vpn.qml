import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Ui
import qs.Commons

Column {
  id: root
  property var bar: null
  property string connectionName: "vpn"
  property string label: "VPN"
  property bool hasCursor: false
  property bool connected: false
  property bool known: false
  property string pending: ""
  property string error: ""
  readonly property bool busy: pending !== ""
  readonly property string status: busy ? (pending === "up" ? "Connecting…" : "Disconnecting…")
    : !known ? "Status unavailable" : connected ? "Connected" : "Disconnected"
  signal hovered()
  spacing: Style.space(4)

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function toggle() {
    if (busy || !known) return
    error = ""
    pending = connected ? "down" : "up"
    // Save the user's choice before changing the live connection. In
    // particular, disable autoconnect before disconnecting so it stays off.
    saveProc.command = ["nmcli", "--wait", "20", "connection", "modify", "id", root.connectionName,
      "connection.autoconnect", pending === "up" ? "yes" : "no"]
    if (pending === "up")
      saveProc.command = saveProc.command.concat(["connection.autoconnect-retries", "0"])
    saveProc.running = true
  }

  Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: statusProc
    command: ["nmcli", "--wait", "5", "-g", "GENERAL.STATE", "connection", "show", "id", root.connectionName]
    environment: ({ LC_ALL: "C" })
    stdout: StdioCollector { id: statusOutput; waitForEnd: true }
    onExited: function(code) {
      root.known = code === 0
      root.connected = code === 0 && statusOutput.text.trim() === "activated"
    }
  }

  Process {
    id: saveProc
    environment: ({ LC_ALL: "C" })
    stderr: StdioCollector { id: saveError; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) {
        root.error = "Could not remember the VPN choice: " + (saveError.text.trim() || "NetworkManager rejected the change.")
        root.pending = ""
        root.refresh()
        return
      }
      actionProc.command = ["nmcli", "--wait", "20", "connection", root.pending, "id", root.connectionName]
      actionProc.running = true
    }
  }

  Process {
    id: actionProc
    environment: ({ LC_ALL: "C" })
    stderr: StdioCollector { id: actionError; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) root.error = "VPN choice saved, but the connection action failed: " + (actionError.text.trim() || "Try again.")
      if (code === 0) root.connected = root.pending === "up"
      root.pending = ""
      root.refresh()
    }
  }

  RowLayout {
    width: parent.width
    spacing: Style.space(12)

    Text {
      text: "󰒃"
      color: root.connected ? Color.accent : root.bar.foreground
      opacity: root.connected ? 1 : 0.5
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.title
    }

    Column {
      Layout.fillWidth: true
      spacing: Style.space(2)
      Text {
        text: root.label
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }
      Text {
        text: root.status
        color: root.connected ? Color.accent : root.bar.foreground
        opacity: root.connected ? 1 : 0.65
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    ToggleSwitch {
      id: vpnSwitch
      checked: root.busy ? root.pending === "up" : root.connected
      busy: root.busy || !root.known
      hasCursor: root.hasCursor
      foreground: root.bar.foreground
      onHovered: function(on) { if (on) root.hovered() }
      onToggled: root.toggle()

      PanelToolTip {
        visible: vpnSwitch.containsMouse
        text: (root.connected ? "Disconnect " : "Connect ") + root.label + " (V)"
        fontFamily: root.bar.fontFamily
      }
    }
  }

  Text {
    width: parent.width
    visible: root.error !== ""
    text: root.error
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    color: root.bar.urgent
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.caption
  }
}
