pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string moduleName: "hancore.bongocat"
  readonly property string home: Quickshell.env("HOME")
  readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME") !== ""
    ? Quickshell.env("XDG_CACHE_HOME") : home + "/.cache"
  readonly property string helperPath: cacheHome + "/omarchy/bongocat/bongo-input"
  readonly property string buildScript: localPath("helper/build-helper")
  readonly property string accessScript: localPath("helper/input-access")

  property var pluginSettings: ({})
  property bool catActive: true
  property bool positionLocked: true
  property int positionX: -1
  property int positionY: -1
  property int catWidth: 280
  readonly property int catHeight: Math.max(1, Math.round(catWidth * 360 / 864))
  property int keypressDuration: 105
  property string keyboardName: ""
  property string monitorName: ""
  property string colorMode: "default"
  property string customColor: "#f0abab"
  readonly property bool catColorized: colorMode !== "default"
  readonly property color catTint: colorMode === "theme"
    ? Color.accent : customColor

  property bool leftDown: false
  property bool rightDown: false
  property bool helperReady: false
  property string buildError: ""
  property string inputState: "building"
  property int inputCount: 0
  property var devices: []
  property bool deviceScanRunning: false
  property bool accessBusy: false
  property bool accessInstalled: false
  property string accessError: ""
  property bool inputStopRequested: false
  property int inputFailureCount: 0

  readonly property string frameFile: leftDown && rightDown
    ? "bongo-cat-both-down.png"
    : leftDown ? "bongo-cat-left-down.png"
    : rightDown ? "bongo-cat-right-down.png"
    : "bongo-cat-both-up.png"
  readonly property url frameSource: Qt.resolvedUrl("assets/" + frameFile)
  readonly property url idleSource: Qt.resolvedUrl("assets/bongo-cat-both-up.png")
  readonly property bool inputReady: inputState === "ready"
  readonly property bool needsInputAccess: inputState === "permission"

  visible: false
  width: 0
  height: 0

  function localPath(relativePath) {
    return Qt.resolvedUrl(relativePath).toString().replace(/^file:\/\//, "")
  }

  function defaults() {
    return {
      active: true,
      positionLocked: true,
      positionX: -1,
      positionY: -1,
      catWidth: 280,
      keypressDuration: 105,
      keyboardName: "",
      monitorName: "",
      colorMode: "default",
      customColor: "#f0abab"
    }
  }

  function boolValue(value, fallback) {
    if (value === true || value === false) return value
    if (value === undefined || value === null) return fallback
    var text = String(value).toLowerCase()
    return text === "true" || text === "1" || text === "yes" || text === "on"
  }

  function intValue(value, fallback, minimum, maximum) {
    var parsed = parseInt(String(value), 10)
    if (!isFinite(parsed)) parsed = fallback
    return Math.max(minimum, Math.min(maximum, parsed))
  }

  function mergedSettings(settings) {
    var merged = defaults()
    if (settings) {
      for (var key in settings) {
        if (key !== "id") merged[key] = settings[key]
      }
    }
    return merged
  }

  function applySettings(settings) {
    var next = mergedSettings(settings)
    var oldActive = catActive
    var oldKeyboard = keyboardName

    pluginSettings = next
    catActive = boolValue(next.active, true)
    positionLocked = boolValue(next.positionLocked, true)
    positionX = intValue(next.positionX, -1, -1, 16000)
    positionY = intValue(next.positionY, -1, -1, 16000)
    catWidth = intValue(next.catWidth, 280, 120, 640)
    keypressDuration = intValue(next.keypressDuration, 105, 40, 500)
    keyboardName = String(next.keyboardName || "")
    monitorName = String(next.monitorName || "")
    var nextMode = String(next.colorMode || "default")
    colorMode = nextMode === "theme" || nextMode === "hex" ? nextMode : "default"
    var nextColor = String(next.customColor || "#f0abab")
    customColor = /^#[0-9a-fA-F]{6}$/.test(nextColor) ? nextColor : "#f0abab"

    if (oldActive !== catActive || oldKeyboard !== keyboardName)
      updateInputProcess()
  }

  function settingsFromShell() {
    if (!shell) return null
    var config = shell.shellConfig
    if (!config || !config.bar || !config.bar.layout) return null
    var sections = ["left", "center", "right"]
    for (var s = 0; s < sections.length; ++s) {
      var entries = config.bar.layout[sections[s]]
      if (!Array.isArray(entries)) continue
      for (var i = 0; i < entries.length; ++i) {
        if (entries[i] && String(entries[i].id || "") === moduleName)
          return entries[i]
      }
    }
    if (Array.isArray(config.plugins)) {
      for (var p = 0; p < config.plugins.length; ++p) {
        if (config.plugins[p] && String(config.plugins[p].id || "") === moduleName)
          return config.plugins[p]
      }
    }
    return null
  }

  function syncFromShell() {
    var found = settingsFromShell()
    if (found) applySettings(found)
  }

  function patchSettings(patch) {
    var next = mergedSettings(pluginSettings)
    for (var key in patch) next[key] = patch[key]
    applySettings(next)
    if (shell && typeof shell.updateEntryInline === "function")
      shell.updateEntryInline(moduleName, next)
  }

  function setCatActive(value) { patchSettings({ active: !!value }) }
  function setPositionLocked(value) { patchSettings({ positionLocked: !!value }) }
  function previewCatWidth(value) {
    catWidth = intValue(value, catWidth, 120, 640)
  }
  function setCatWidth(value) {
    patchSettings({ catWidth: intValue(value, catWidth, 120, 640) })
  }
  function resizeCat(delta) { setCatWidth(catWidth + delta) }
  function setKeypressDuration(value) {
    patchSettings({ keypressDuration: intValue(value, 105, 40, 500) })
  }
  function setKeyboardName(value) { patchSettings({ keyboardName: String(value || "") }) }
  function setMonitorName(value) { patchSettings({ monitorName: String(value || "") }) }
  function setColorMode(value) {
    var mode = String(value || "default")
    patchSettings({ colorMode: mode === "theme" || mode === "hex" ? mode : "default" })
  }
  function setCustomColor(value) {
    var next = String(value || "")
    if (/^#[0-9a-fA-F]{6}$/.test(next))
      patchSettings({ customColor: next, colorMode: "hex" })
  }

  function targetScreen() {
    var screens = Quickshell.screens || []
    if (monitorName !== "") {
      for (var i = 0; i < screens.length; ++i)
        if (String(screens[i].name || "") === monitorName) return screens[i]
    }
    return screens.length > 0 ? screens[0] : null
  }

  function screenEnabled(screenObject) {
    var target = targetScreen()
    return target !== null && target === screenObject
  }

  function resolvedX(screenObject) {
    if (!screenObject) return 0
    var fallback = Math.max(0, screenObject.width - catWidth - 36)
    return Math.max(0, Math.min(screenObject.width - catWidth,
      positionX < 0 ? fallback : positionX))
  }

  function resolvedY(screenObject) {
    if (!screenObject) return 0
    var fallback = Math.max(0, screenObject.height - catHeight - 54)
    return Math.max(0, Math.min(screenObject.height - catHeight,
      positionY < 0 ? fallback : positionY))
  }

  function previewPosition(x, y, screenObject) {
    if (!screenObject || positionLocked) return
    positionX = Math.round(Math.max(0, Math.min(screenObject.width - catWidth, x)))
    positionY = Math.round(Math.max(0, Math.min(screenObject.height - catHeight, y)))
  }

  function commitPosition() {
    if (positionX < 0 || positionY < 0) return
    patchSettings({ positionX: positionX, positionY: positionY })
  }

  function setPosition(x, y) {
    var screenObject = targetScreen()
    if (!screenObject) return
    var nextX = Math.round(Math.max(0, Math.min(screenObject.width - catWidth, x)))
    var nextY = Math.round(Math.max(0, Math.min(screenObject.height - catHeight, y)))
    patchSettings({ positionX: nextX, positionY: nextY })
  }

  function nudgePosition(dx, dy) {
    var screenObject = targetScreen()
    if (!screenObject || positionLocked) return
    setPosition(resolvedX(screenObject) + dx, resolvedY(screenObject) + dy)
  }

  function resetPosition() {
    patchSettings({ positionX: -1, positionY: -1 })
  }

  function pressLeft() {
    leftDown = true
    leftRelease.interval = keypressDuration
    leftRelease.restart()
  }

  function pressRight() {
    rightDown = true
    rightRelease.interval = keypressDuration
    rightRelease.restart()
  }

  function testAnimation() {
    pressLeft()
    pressRight()
  }

  function handleInputLine(rawLine) {
    var line = String(rawLine || "").trim()
    if (line === "L") {
      pressLeft()
      return
    }
    if (line === "R") {
      pressRight()
      return
    }
    if (line.indexOf("STATUS\t") === 0) {
      var fields = line.split("\t")
      inputState = fields.length > 1 ? fields[1] : "error"
      inputCount = fields.length > 2 ? Math.max(0, parseInt(fields[2], 10) || 0) : 0
      inputFailureCount = 0
    }
  }

  function inputCommand() {
    var command = [helperPath, "--watch"]
    if (keyboardName !== "") command.push("--name", keyboardName)
    return command
  }

  function startInputProcess() {
    if (!helperReady || !catActive || inputProcess.running) return
    inputProcess.command = inputCommand()
    inputState = "scanning"
    inputProcess.running = true
  }

  function updateInputProcess() {
    inputRestart.stop()
    if (!catActive) {
      if (inputProcess.running) {
        inputStopRequested = true
        inputProcess.running = false
      }
      inputState = "disabled"
      inputCount = 0
      leftDown = false
      rightDown = false
      return
    }
    if (!helperReady) {
      inputState = buildProcess.running ? "building" : "error"
      return
    }
    if (inputProcess.running) {
      inputStopRequested = true
      inputProcess.running = false
      return
    }
    inputRestart.interval = 150
    inputRestart.restart()
  }

  function inputProcessExited() {
    if (!catActive || !helperReady) {
      inputStopRequested = false
      return
    }
    if (inputStopRequested) {
      inputStopRequested = false
      inputRestart.interval = 150
    } else {
      inputFailureCount = Math.min(8, inputFailureCount + 1)
      inputState = "error"
      inputRestart.interval = Math.min(30000,
        500 * Math.pow(2, inputFailureCount - 1))
    }
    inputRestart.restart()
  }

  function scanDevices() {
    if (!helperReady || deviceScan.running) return
    deviceScanRunning = true
    deviceScan.command = [helperPath, "--list"]
    deviceScan.running = true
  }

  function applyDeviceList(raw) {
    try {
      var parsed = JSON.parse(String(raw || "[]"))
      devices = Array.isArray(parsed) ? parsed : []
    } catch (error) {
      devices = []
    }
  }

  function keyboardOptions() {
    var options = [{ value: "", label: "Auto (all keyboards)" }]
    var seen = ({})
    for (var i = 0; i < devices.length; ++i) {
      var name = String(devices[i].name || "")
      if (name === "" || seen[name]) continue
      seen[name] = true
      options.push({
        value: name,
        label: name + (devices[i].readable ? "" : " · no access")
      })
    }
    if (keyboardName !== "" && !seen[keyboardName])
      options.push({ value: keyboardName, label: keyboardName + " · not found" })
    return options
  }

  function monitorOptions() {
    var screens = Quickshell.screens || []
    var options = [{ value: "", label: "Primary monitor" }]
    for (var i = 0; i < screens.length; ++i) {
      var name = String(screens[i].name || "")
      if (name !== "") options.push({ value: name, label: name })
    }
    return options
  }

  function inputStatusText() {
    if (!catActive) return "Disabled"
    if (inputState === "building") return "Building input helper…"
    if (inputState === "scanning") return "Scanning keyboards…"
    if (inputState === "ready")
      return inputCount + (inputCount === 1 ? " keyboard active" : " keyboards active")
    if (inputState === "permission") return "Input access required"
    if (inputState === "no-device") return "No keyboard found"
    return buildError !== "" ? buildError : "Input helper unavailable"
  }

  function checkInputAccess() {
    if (accessProbe.running) return
    accessProbe.command = [accessScript, "status"]
    accessProbe.running = true
  }

  function setInputAccess(allow) {
    if (accessBusy || accessProcess.running) return
    accessError = ""
    accessProcess.command = [accessScript, allow ? "install" : "remove"]
    accessProcess.running = true
  }

  onShellChanged: syncFromShell()

  Connections {
    target: root.shell
    function onShellConfigChanged() { root.syncFromShell() }
  }

  Component.onCompleted: {
    applySettings(defaults())
    buildProcess.command = [buildScript, helperPath]
    buildProcess.running = true
    checkInputAccess()
  }

  Timer {
    id: leftRelease
    repeat: false
    onTriggered: root.leftDown = false
  }

  Timer {
    id: rightRelease
    repeat: false
    onTriggered: root.rightDown = false
  }

  Timer {
    id: inputRestart
    interval: 150
    repeat: false
    onTriggered: root.startInputProcess()
  }

  Timer {
    id: accessRescan
    interval: 600
    repeat: false
    onTriggered: {
      root.checkInputAccess()
      root.scanDevices()
      root.updateInputProcess()
    }
  }

  Process {
    id: buildProcess
    onStarted: {
      root.buildError = ""
      root.inputState = "building"
    }
    onExited: function(exitCode) {
      root.helperReady = exitCode === 0
      if (root.helperReady) {
        root.scanDevices()
        root.updateInputProcess()
      } else {
        root.inputState = "error"
        if (root.buildError === "") root.buildError = "Could not build input helper"
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var message = String(text || "").trim()
        if (message !== "") root.buildError = message.split("\n")[0]
      }
    }
  }

  Process {
    id: inputProcess
    stdout: SplitParser {
      onRead: function(line) { root.handleInputLine(line) }
    }
    onExited: root.inputProcessExited()
  }

  Process {
    id: deviceScan
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyDeviceList(text)
    }
    onExited: root.deviceScanRunning = false
  }

  Process {
    id: accessProbe
    onExited: function(exitCode) { root.accessInstalled = exitCode === 0 }
  }

  Process {
    id: accessProcess
    onStarted: root.accessBusy = true
    onExited: function(exitCode) {
      root.accessBusy = false
      if (exitCode !== 0 && root.accessError === "")
        root.accessError = "Input access was not changed"
      accessRescan.restart()
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var message = String(text || "").trim()
        if (message !== "") root.accessError = message.split("\n")[0]
      }
    }
  }

  IpcHandler {
    target: root.moduleName

    function toggle(): void { root.setCatActive(!root.catActive) }
    function enable(): void { root.setCatActive(true) }
    function disable(): void { root.setCatActive(false) }
    function lock(): void { root.setPositionLocked(true) }
    function unlock(): void { root.setPositionLocked(false) }
    function resize(width: int): void { root.setCatWidth(width) }
    function test(): void { root.testAnimation() }
    function rescan(): void { root.scanDevices(); root.updateInputProcess() }
    function status(): string {
      return JSON.stringify({
        active: root.catActive,
        locked: root.positionLocked,
        input: root.inputState,
        keyboards: root.inputCount,
        x: root.positionX,
        y: root.positionY,
        width: root.catWidth
      })
    }
  }

  Variants {
    model: Quickshell.screens

    Scope {
      id: screenScope
      required property var modelData

      PanelWindow {
        id: displayWindow
        screen: screenScope.modelData
        visible: root.catActive && root.positionLocked
          && root.screenEnabled(screenScope.modelData)
        color: "transparent"
        implicitWidth: root.catWidth
        implicitHeight: root.catHeight
        exclusionMode: ExclusionMode.Ignore
        anchors {
          top: root.positionY >= 0
          bottom: root.positionY < 0
          left: root.positionX >= 0
          right: root.positionX < 0
        }
        margins {
          left: root.positionX >= 0 ? root.resolvedX(screenScope.modelData) : 0
          right: root.positionX < 0 ? 36 : 0
          top: root.positionY >= 0 ? root.resolvedY(screenScope.modelData) : 0
          bottom: root.positionY < 0 ? 54 : 0
        }
        mask: Region {}

        WlrLayershell.namespace: "hancore-bongocat"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        CatImage {
          anchors.fill: parent
          source: root.frameSource
          colorized: root.catColorized
          tint: root.catTint
        }
      }

      PanelWindow {
        id: editWindow
        screen: screenScope.modelData
        visible: root.catActive && !root.positionLocked
          && root.screenEnabled(screenScope.modelData)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        mask: Region { item: editorCat }

        WlrLayershell.namespace: "hancore-bongocat-position"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Item {
          id: editorCat
          x: root.resolvedX(screenScope.modelData)
          y: root.resolvedY(screenScope.modelData)
          width: root.catWidth
          height: root.catHeight

          CatImage {
            anchors.fill: parent
            source: root.frameSource
            colorized: root.catColorized
            tint: root.catTint
          }

          Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.width: 2
            border.color: "#f0abab"
            radius: 4
          }

          Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 5
            width: dragLabel.implicitWidth + 12
            height: dragLabel.implicitHeight + 6
            radius: 3
            color: "#cc111111"

            Text {
              id: dragLabel
              anchors.centerIn: parent
              text: "Drag · Scroll to resize · Right-click to lock"
              color: "white"
              font.pixelSize: 11
            }
          }

          MouseArea {
            id: dragArea
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
            cursorShape: pressedButtons & Qt.LeftButton
              ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            property real pressOffsetX: 0
            property real pressOffsetY: 0

            onPressed: function(mouse) {
              if (mouse.button !== Qt.LeftButton) return
              pressOffsetX = mouse.x
              pressOffsetY = mouse.y
            }
            onPositionChanged: function(mouse) {
              if (!(pressedButtons & Qt.LeftButton)) return
              var point = editorCat.mapToItem(editWindow.contentItem, mouse.x, mouse.y)
              root.previewPosition(point.x - pressOffsetX, point.y - pressOffsetY,
                screenScope.modelData)
            }
            onReleased: function(mouse) {
              if (mouse.button === Qt.LeftButton) root.commitPosition()
            }
            onClicked: function(mouse) {
              if (mouse.button === Qt.RightButton) root.setPositionLocked(true)
            }
            onWheel: function(wheel) {
              if (wheel.angleDelta.y === 0) return
              root.resizeCat(wheel.angleDelta.y > 0 ? 20 : -20)
              wheel.accepted = true
            }
          }
        }
      }
    }
  }
}
