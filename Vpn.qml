import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Ui
import qs.Commons

Column {
  id: root
  property var bar: null
  property string connectionName: "vpn"
  property string savedUuid: ""
  property string label: "VPN"
  property bool hasCursor: false
  property int controlIndex: 0
  property var profiles: []
  property string selectedUuid: ""
  property bool known: false
  property string pending: ""
  property string actionUuid: ""
  property int revision: 0
  property int listRevision: 0
  property string error: ""
  property string notice: ""
  property string configFile: ""
  property bool importOpen: false
  readonly property bool busy: pending !== "" || fileProc.running
  readonly property bool editing: importOpen || picker.popupOpen
  readonly property var selected: profiles.find(function(p) { return p.uuid === root.selectedUuid }) || null
  readonly property bool connected: known && !!selected && selected.active
  readonly property var activeProfiles: known ? profiles.filter(function(p) { return p.active }) : []
  readonly property bool anyConnected: activeProfiles.length > 0
  readonly property bool otherConnected: activeProfiles.some(function(p) { return p.uuid !== root.selectedUuid })
  readonly property string status: pending === "import" ? "Adding VPN…"
    : pending !== "" ? (pending === "up" ? "Connecting…" : "Disconnecting…")
    : !known ? "Checking VPNs…" : !selected ? "No VPNs saved"
    : connected ? "Connected" : "Disconnected"
  readonly property string summary: anyConnected
    ? "VPN: " + activeProfiles.map(function(p) { return p.name }).join(", ")
    : label + ": " + status
  readonly property string helper: decodeURIComponent(Qt.resolvedUrl("vpn.py").toString().replace(/^file:\/\//, ""))
  signal hovered()
  signal selectionChanged(string uuid)
  signal fileDialogOpening()
  signal fileDialogClosed()
  signal editorClosed()
  spacing: Style.space(8)

  function refresh() {
    if (!listProc.running && !busy) {
      listRevision = revision
      listProc.running = true
    }
  }

  function choose(uuid) {
    if (busy || !profiles.some(function(p) { return p.uuid === uuid })) return
    revision++
    selectedUuid = uuid
    error = ""
    notice = ""
    selectionChanged(uuid)
  }

  function moveControl(delta) {
    controlIndex = Math.max(0, Math.min(2, controlIndex + delta))
  }

  function activateControl() {
    if (busy) return
    if (controlIndex === 0) toggle()
    else if (controlIndex === 1 && profiles.length > 0) picker.open()
    else chooseFile()
  }

  function focusControl(index) {
    controlIndex = index
    hovered()
  }

  function toggle() {
    if (busy || !known || !selected) return
    if (!connected && otherConnected) {
      error = "Disconnect the active VPN before connecting another."
      return
    }
    error = ""
    notice = ""
    revision++
    actionUuid = selectedUuid
    pending = connected ? "down" : "up"
    saveProc.command = ["nmcli", "--wait", "20", "connection", "modify", "uuid", actionUuid,
      "connection.autoconnect", pending === "up" ? "yes" : "no"]
    if (pending === "up")
      saveProc.command = saveProc.command.concat(["connection.autoconnect-retries", "0"])
    saveProc.running = true
  }

  function chooseFile() {
    if (busy) return
    error = ""
    notice = ""
    fileDialogOpening()
    fileProc.running = true
  }

  function cancelImport() {
    if (busy) return
    importOpen = false
    configFile = ""
    editorClosed()
  }

  function addVpn() {
    if (busy || !configFile || !nameField.text.trim()) return
    error = ""
    revision++
    pending = "import"
    importProc.command = ["python3", helper, "import", configFile, nameField.text.trim()]
    importProc.running = true
  }

  function readResult(text) {
    try { return JSON.parse(text) }
    catch (e) { return {error: "Could not read VPN information. Check that python-gobject and libnm are installed."} }
  }

  onSavedUuidChanged: { if (savedUuid !== "") selectedUuid = savedUuid }

  Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: listProc
    command: ["python3", root.helper, "list"]
    stdout: StdioCollector { id: listOutput; waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      if (root.listRevision !== root.revision) { root.refresh(); return }
      var result = root.readResult(listOutput.text)
      root.known = code === 0 && !result.error
      if (!root.known) {
        root.error = result.error || "Could not list VPN connections."
        return
      }
      root.profiles = result.profiles || []
      if (!root.profiles.some(function(p) { return p.uuid === root.selectedUuid })) {
        var next = root.profiles.find(function(p) { return p.uuid === root.savedUuid })
          || root.profiles.find(function(p) { return p.name === root.connectionName })
          || root.profiles.find(function(p) { return p.active }) || root.profiles[0]
        root.selectedUuid = next ? next.uuid : ""
      }
    }
  }

  Process {
    id: fileProc
    command: ["zenity", "--file-selection", "--title=Import WireGuard config", "--file-filter=WireGuard configs | *.conf"]
    stdout: StdioCollector { id: fileOutput; waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      if (code === 0) {
        root.configFile = fileOutput.text.replace(/\r?\n$/, "")
        nameField.text = root.configFile.split("/").pop().replace(/\.conf$/i, "")
        root.importOpen = true
        nameFocus.restart()
      } else if (code !== 1) {
        root.error = "Could not open the file picker. Check that zenity is installed."
      }
      root.fileDialogClosed()
    }
  }

  Timer {
    id: nameFocus
    interval: 150
    onTriggered: nameField.forceActiveFocus()
  }

  Process {
    id: importProc
    stdout: StdioCollector { id: importOutput; waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      var result = root.readResult(importOutput.text)
      root.pending = ""
      if (code !== 0 || result.error) {
        root.error = result.error || "Could not add this VPN."
        return
      }
      // Keep a pending list refresh from overriding the newly saved selection.
      root.profiles = root.profiles.concat([{uuid: result.uuid, name: result.name, active: false}])
      root.choose(result.uuid)
      root.notice = "Added “" + result.name + "”"
      root.importOpen = false
      root.configFile = ""
      root.editorClosed()
      root.refresh()
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
      actionProc.command = ["nmcli", "--wait", "20", "connection", root.pending, "uuid", root.actionUuid]
      actionProc.running = true
    }
  }

  Process {
    id: actionProc
    environment: ({ LC_ALL: "C" })
    stderr: StdioCollector { id: actionError; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) root.error = "VPN choice saved, but the connection action failed: " + (actionError.text.trim() || "Try again.")
      root.pending = ""
      root.refresh()
    }
  }

  RowLayout {
    width: parent.width
    spacing: Style.space(12)
    Text {
      text: "󰒃"
      color: root.anyConnected ? Color.accent : root.bar.foreground
      opacity: root.anyConnected ? 1 : 0.5
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
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
    ToggleSwitch {
      id: vpnSwitch
      checked: root.pending === "up" || (root.pending !== "down" && root.connected)
      busy: root.busy || !root.known || !root.selected
      hasCursor: root.hasCursor && root.controlIndex === 0
      foreground: root.bar.foreground
      onHovered: function(on) { if (on) root.focusControl(0) }
      onToggled: root.toggle()
    }
  }

  Dropdown {
    id: picker
    width: parent.width
    visible: root.profiles.length > 0
    enabled: !root.busy
    showLabel: false
    value: root.selectedUuid
    options: root.profiles.map(function(p) {
      var duplicate = root.profiles.filter(function(other) { return other.name === p.name }).length > 1
      return {value: p.uuid, label: p.name + (duplicate ? " (" + p.uuid.slice(0, 8) + ")" : "") + (p.active ? " · Connected" : "")}
    })
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    hasCursor: root.hasCursor && root.controlIndex === 1
    onChanged: function(value) {
      root.choose(value)
      picker.value = Qt.binding(function() { return root.selectedUuid })
    }
    onHovered: function(on) { if (on) root.focusControl(1) }
    onPopupOpenChanged: if (!popupOpen) root.editorClosed()
  }

  Text {
    width: parent.width
    visible: root.otherConnected
    text: "Active: " + root.activeProfiles.map(function(p) { return p.name }).join(", ") + ". Disconnect it before connecting another VPN."
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.caption
  }

  Button {
    text: "Add VPN…"
    visible: !root.importOpen
    enabled: !root.busy
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    focusable: true
    hasCursor: root.hasCursor && root.controlIndex === 2
    onHovered: function(on) { if (on) root.focusControl(2) }
    onClicked: root.chooseFile()
  }

  Column {
    visible: root.importOpen
    width: parent.width
    spacing: Style.space(6)
    Text {
      width: parent.width
      text: "Import: " + root.configFile.split("/").pop()
      textFormat: Text.PlainText
      elide: Text.ElideMiddle
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.caption
    }
    TextField {
      id: nameField
      width: parent.width
      placeholderText: "VPN name"
      foreground: root.bar.foreground
      enabled: !root.busy
      maximumLength: 128
      onAccepted: root.addVpn()
      Keys.onEscapePressed: root.cancelImport()
    }
    Row {
      spacing: Style.space(8)
      Button {
        text: root.pending === "import" ? "Adding…" : "Add"
        enabled: !root.busy && nameField.text.trim() !== ""
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        focusable: true
        onClicked: root.addVpn()
      }
      Button {
        text: "Cancel"
        enabled: !root.busy
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        focusable: true
        onClicked: root.cancelImport()
      }
    }
  }

  RowLayout {
    width: parent.width
    visible: root.notice !== ""
    Text {
      Layout.fillWidth: true
      text: root.notice
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      color: Color.accent
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.caption
    }
    Button {
      text: "Connect"
      enabled: !root.busy && !root.connected && !root.otherConnected
      foreground: root.bar.foreground
      fontFamily: root.bar.fontFamily
      focusable: true
      onClicked: root.toggle()
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
