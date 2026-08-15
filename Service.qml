pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string moduleName: "hancore.bongocat"
  readonly property string home: Quickshell.env("HOME")
  readonly property string runtimeHome: Quickshell.env("XDG_RUNTIME_DIR")
  readonly property string helperPath: localPath("helper/bongo-input")
  readonly property string accessScript: localPath("helper/input-access")
  readonly property string pendingSettingsPath: runtimeHome
    + "/omarchy/bongocat/pending-settings.json"

  property var pluginSettings: ({})
  property int panelSessionCount: 0
  property bool settingsDirty: false
  property var pendingSettingKeys: ({})
  property var pendingRecoveryPatch: ({})
  property bool pendingJournalLoaded: false
  property bool persistVerificationPending: false
  property var persistVerificationPatch: ({})
  property int persistVerificationAttempts: 0
  property int persistenceFailureCount: 0
  property bool catActive: true
  property bool positionLocked: true
  property int positionX: -1
  property int positionY: -1
  readonly property int minimumCatWidth: 60
  readonly property int maximumCatWidth: 640
  property int catWidth: 280
  readonly property int catHeight: Math.max(1, Math.round(catWidth * 360 / 864))
  // All animation frames reserve 15 source pixels above the visible cat.
  readonly property int frameTopInset: Math.max(0, Math.round(catHeight * 15 / 360))
  property int keypressDuration: 105
  property string keyboardName: ""
  property string monitorName: ""
  property int workspaceId: 0
  property string colorMode: "default"
  property string customColor: "#f0abab"
  readonly property var idleService: shell && typeof shell.serviceFor === "function"
    ? shell.serviceFor("omarchy.idle") : null
  readonly property var lockService: shell && typeof shell.serviceFor === "function"
    ? shell.serviceFor("omarchy.lock") : null
  readonly property bool presentationSuppressed:
    (idleService && idleService.screensaverWindowCount > 0)
    || (lockService && lockService.locked)
  readonly property bool catVisible: catActive && !presentationSuppressed
  readonly property bool catColorized: colorMode !== "default"
  readonly property color catTint: colorMode === "theme"
    ? Color.accent : customColor

  property bool leftDown: false
  property bool rightDown: false
  readonly property bool helperReady: true
  property string inputState: "scanning"
  property int inputCount: 0
  property var devices: []
  property bool deviceScanRunning: false
  property bool accessBusy: false
  property bool sessionAccessGranted: false
  readonly property bool accessInstalled: sessionAccessGranted
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
      workspaceId: 0,
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
    catWidth = intValue(next.catWidth, 280, minimumCatWidth, maximumCatWidth)
    keypressDuration = intValue(next.keypressDuration, 105, 40, 500)
    keyboardName = String(next.keyboardName || "")
    monitorName = String(next.monitorName || "")
    workspaceId = intValue(next.workspaceId, 0, 0, 10)
    var nextMode = String(next.colorMode || "default")
    colorMode = nextMode === "theme" || nextMode === "hex" ? nextMode : "default"
    var nextColor = String(next.customColor || "#f0abab")
    customColor = /^#[0-9a-fA-F]{6}$/.test(nextColor) ? nextColor : "#f0abab"

    if (oldActive !== catActive || oldKeyboard !== keyboardName)
      updateInputProcess()
  }

  function settingsFromConfig(config) {
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

  function settingsFromShell() {
    return shell ? settingsFromConfig(shell.shellConfig) : null
  }

  function shellConfigFromDisk() {
    if (!shell || String(shell.userConfigPath || "") === "") return null
    shellConfigProbe.reload()
    try {
      return JSON.parse(String(shellConfigProbe.text()))
    } catch (error) {
      console.warn("Bongo Cat could not read the latest shell settings")
      return null
    }
  }

  function configWithSettings(config, settings) {
    var nextConfig = JSON.parse(JSON.stringify(config))
    var entry = settingsFromConfig(nextConfig)
    if (!entry) return null
    for (var oldKey in entry) {
      if (oldKey !== "id") delete entry[oldKey]
    }
    entry.id = moduleName
    for (var key in settings) {
      if (key !== "id") entry[key] = settings[key]
    }
    return nextConfig
  }

  function syncFromShell() {
    if (panelSessionCount > 0 || settingsDirty || persistVerificationPending) return
    var found = settingsFromShell()
    if (found) applySettings(found)
  }

  function beginPanelSession() {
    panelSessionCount += 1
  }

  function endPanelSession() {
    panelSessionCount = Math.max(0, panelSessionCount - 1)
    if (panelSessionCount !== 0) return
    if (settingsDirty) persistPendingSettings()
    else syncFromShell()
  }

  function abandonPanelSession() {
    panelSessionCount = Math.max(0, panelSessionCount - 1)
    if (panelSessionCount === 0 && settingsDirty)
      abandonedSessionTimer.restart()
  }

  function writePendingJournal() {
    if (!settingsDirty) return
    var values = ({})
    for (var key in pendingSettingKeys) {
      if (pendingSettingKeys[key]) values[key] = pluginSettings[key]
    }
    pendingSettingsFile.setText(JSON.stringify({ version: 1, settings: values }) + "\n")
  }

  function clearPendingJournal() {
    pendingSettingsFile.setText("")
  }

  function verifyPersistedSettings(raw) {
    if (!persistVerificationPending) return
    var config = null
    try {
      config = JSON.parse(String(raw || ""))
    } catch (error) {
      return
    }
    var stored = settingsFromConfig(config)
    if (!stored) return
    var keys = Object.keys(persistVerificationPatch)
    for (var i = 0; i < keys.length; ++i) {
      var key = keys[i]
      if (JSON.stringify(stored[key]) !== JSON.stringify(persistVerificationPatch[key]))
        return
    }

    persistVerificationPending = false
    persistVerificationPatch = ({})
    persistVerificationAttempts = 0
    persistenceFailureCount = 0
    persistenceRetryTimer.interval = 1000
    persistenceVerificationTimer.stop()
    if (settingsDirty) {
      writePendingJournal()
    } else {
      pendingSettingKeys = ({})
      clearPendingJournal()
      syncFromShell()
    }
  }

  function retryUnverifiedPersistence() {
    if (!persistVerificationPending) return
    persistenceVerificationTimer.stop()
    var keys = Object.keys(persistVerificationPatch)
    for (var i = 0; i < keys.length; ++i)
      pendingSettingKeys[keys[i]] = true
    persistVerificationPending = false
    persistVerificationPatch = ({})
    persistVerificationAttempts = 0
    settingsDirty = true
    writePendingJournal()
    persistenceFailureCount = Math.min(5, persistenceFailureCount + 1)
    persistenceRetryTimer.interval = Math.min(30000,
      1000 * Math.pow(2, persistenceFailureCount - 1))
    persistenceRetryTimer.restart()
  }

  function loadPendingJournal(raw) {
    if (pendingJournalLoaded) return
    pendingJournalLoaded = true
    var text = String(raw || "").trim()
    if (text === "") return
    try {
      var parsed = JSON.parse(text)
      if (parsed && parsed.version === 1 && parsed.settings
          && typeof parsed.settings === "object") {
        pendingRecoveryPatch = parsed.settings
        recoverPendingJournal()
      } else {
        clearPendingJournal()
      }
    } catch (error) {
      console.warn("Bongo Cat pending settings are invalid; discarding them")
      clearPendingJournal()
    }
  }

  function recoverPendingJournal() {
    if (!shell || !pendingRecoveryPatch) return
    var keys = Object.keys(pendingRecoveryPatch)
    if (keys.length === 0) return
    var shellSettings = settingsFromShell()
    if (!shellSettings) return

    var latest = mergedSettings(shellSettings)
    var modified = ({})
    for (var i = 0; i < keys.length; ++i) {
      var key = keys[i]
      if (!(key in defaults())) continue
      latest[key] = pendingRecoveryPatch[key]
      modified[key] = true
    }

    pendingRecoveryPatch = ({})
    if (Object.keys(modified).length === 0) {
      clearPendingJournal()
      return
    }
    applySettings(latest)
    pendingSettingKeys = modified
    settingsDirty = true
    persistPendingSettings()
  }

  function persistPendingSettings() {
    if (!settingsDirty) return
    writePendingJournal()
    if (!shell || typeof shell.persistShellConfig !== "function") {
      persistenceRetryTimer.restart()
      return
    }
    var diskConfig = shellConfigFromDisk()
    var diskSettings = settingsFromConfig(diskConfig)
    if (!diskSettings) {
      persistenceRetryTimer.restart()
      return
    }

    var local = mergedSettings(pluginSettings)
    var latest = mergedSettings(diskSettings)
    var verification = ({})
    for (var key in pendingSettingKeys) {
      if (!pendingSettingKeys[key]) continue
      latest[key] = local[key]
      verification[key] = local[key]
    }
    var nextConfig = configWithSettings(diskConfig, latest)
    if (!nextConfig) {
      persistenceRetryTimer.restart()
      return
    }

    applySettings(latest)
    settingsDirty = false
    persistVerificationPatch = verification
    persistVerificationPending = true
    persistVerificationAttempts = 0
    try {
      shell.persistShellConfig(nextConfig)
      persistenceVerificationTimer.restart()
    } catch (error) {
      console.warn("Bongo Cat could not persist shell settings")
      retryUnverifiedPersistence()
    }
  }

  function patchSettings(patch) {
    var next = mergedSettings(pluginSettings)
    var modified = ({})
    for (var key in pendingSettingKeys) modified[key] = pendingSettingKeys[key]
    for (var patchKey in patch) {
      next[patchKey] = patch[patchKey]
      modified[patchKey] = true
    }
    applySettings(next)
    pendingSettingKeys = modified
    settingsDirty = true
    if (panelSessionCount > 0) writePendingJournal()
    else persistPendingSettings()
  }

  function setCatActive(value) { patchSettings({ active: !!value }) }
  function setPositionLocked(value) { patchSettings({ positionLocked: !!value }) }
  function previewCatWidth(value) {
    catWidth = intValue(value, catWidth, minimumCatWidth, maximumCatWidth)
  }
  function setCatWidth(value) {
    patchSettings({
      catWidth: intValue(value, catWidth, minimumCatWidth, maximumCatWidth)
    })
  }
  function resizeCat(delta) { setCatWidth(catWidth + delta) }
  function setKeypressDuration(value) {
    patchSettings({ keypressDuration: intValue(value, 105, 40, 500) })
  }
  function setKeyboardName(value) { patchSettings({ keyboardName: String(value || "") }) }
  function setMonitorName(value) { patchSettings({ monitorName: String(value || "") }) }
  function setWorkspaceId(value) {
    patchSettings({ workspaceId: intValue(value, 0, 0, 10) })
  }
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

  function workspaceEnabled(screenObject) {
    if (workspaceId === 0) return true
    var monitor = screenObject ? Hyprland.monitorFor(screenObject) : null
    var active = monitor ? monitor.activeWorkspace : Hyprland.focusedWorkspace
    return active !== null && active !== undefined && active.id === workspaceId
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

  function resolvedWindowY(screenObject) {
    var resolved = resolvedY(screenObject)
    return positionY < 0 ? resolved : resolved - frameTopInset
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
      accessBusy = false
      if (sessionAccessGranted && inputState === "permission") {
        sessionAccessGranted = false
        accessError = "The authorized input helper could not open the keyboard"
      }
    }
  }

  function inputCommand() {
    var arguments = ["--watch"]
    if (keyboardName !== "") arguments.push("--name", keyboardName)
    if (sessionAccessGranted)
      return [accessScript, "watch", helperPath].concat(arguments)
    return [helperPath].concat(arguments)
  }

  function startInputProcess() {
    if (!helperReady || !catActive || inputProcess.running) return
    inputProcess.command = inputCommand()
    inputState = sessionAccessGranted ? "authorizing" : "scanning"
    accessBusy = sessionAccessGranted
    inputProcess.running = true
  }

  function updateInputProcess() {
    inputRestart.stop()
    if (!catActive) {
      sessionAccessGranted = false
      if (inputProcess.running) {
        inputStopRequested = true
        inputProcess.running = false
      }
      inputState = "disabled"
      inputCount = 0
      leftDown = false
      rightDown = false
      accessBusy = false
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

  function inputProcessExited(exitCode) {
    accessBusy = false
    if (!catActive || !helperReady) {
      inputStopRequested = false
      return
    }
    if (inputStopRequested) {
      inputStopRequested = false
      inputRestart.interval = 150
      inputRestart.restart()
      return
    }
    if (sessionAccessGranted) {
      sessionAccessGranted = false
      inputState = "permission"
      inputCount = 0
      leftDown = false
      rightDown = false
      if (accessError === "")
        accessError = exitCode === 126 || exitCode === 127
          ? "Input authorization was cancelled" : "Authorized input helper stopped"
      return
    }

    inputFailureCount = Math.min(8, inputFailureCount + 1)
    inputState = "error"
    inputRestart.interval = Math.min(30000,
      500 * Math.pow(2, inputFailureCount - 1))
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
      options.push({ value: name, label: name })
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
    if (presentationSuppressed) return "Hidden for screen privacy"
    if (inputState === "authorizing") return "Waiting for input authorization…"
    if (inputState === "scanning") return "Scanning keyboards…"
    if (inputState === "ready")
      return inputCount + (inputCount === 1 ? " keyboard active" : " keyboards active")
    if (inputState === "permission") return "Input access required"
    if (inputState === "no-device") return "No keyboard found"
    return accessError !== "" ? accessError : "Input helper unavailable"
  }

  function checkInputAccess() {
    // Session access is represented by the lifetime of inputProcess only.
  }

  function setInputAccess(allow) {
    if (accessBusy && allow) return
    accessError = ""
    sessionAccessGranted = !!allow
    accessBusy = !!allow
    updateInputProcess()
  }

  onShellChanged: {
    syncFromShell()
    recoverPendingJournal()
  }

  Connections {
    target: root.shell
    function onShellConfigChanged() {
      root.syncFromShell()
      root.recoverPendingJournal()
    }
  }

  Component.onCompleted: {
    applySettings(defaults())
    loadPendingJournal(pendingSettingsFile.text())
    scanDevices()
    updateInputProcess()
    checkInputAccess()
  }

  FileView {
    id: pendingSettingsFile
    path: root.pendingSettingsPath
    preload: false
    blockLoading: true
    blockWrites: true
    atomicWrites: true
    printErrors: false
    onLoadFailed: root.pendingJournalLoaded = true
    onSaveFailed: console.warn("Bongo Cat could not save pending settings")
  }

  FileView {
    id: shellConfigProbe
    path: root.shell ? root.shell.userConfigPath : ""
    preload: false
    blockLoading: true
    blockAllReads: true
    watchChanges: true
    printErrors: false
    onLoaded: root.verifyPersistedSettings(text())
    onFileChanged: reload()
  }

  Timer {
    id: persistenceVerificationTimer
    interval: 250
    repeat: true
    onTriggered: {
      root.persistVerificationAttempts += 1
      shellConfigProbe.reload()
      root.verifyPersistedSettings(shellConfigProbe.text())
      if (root.persistVerificationPending
          && root.persistVerificationAttempts >= 20)
        root.retryUnverifiedPersistence()
    }
  }

  Timer {
    id: persistenceRetryTimer
    interval: 1000
    repeat: false
    onTriggered: root.persistPendingSettings()
  }

  // A bar rebuild may abandon the panel while the long-lived service survives.
  // Delay persistence so full plugin/shell teardown destroys this timer first.
  Timer {
    id: abandonedSessionTimer
    interval: 750
    repeat: false
    onTriggered: {
      if (root.panelSessionCount === 0 && root.settingsDirty)
        root.persistPendingSettings()
    }
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

  Process {
    id: inputProcess
    stdout: SplitParser {
      onRead: function(line) { root.handleInputLine(line) }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var message = String(text || "").trim()
        if (message !== "") root.accessError = message.split("\n")[0]
      }
    }
    onExited: function(exitCode) { root.inputProcessExited(exitCode) }
  }

  Process {
    id: deviceScan
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyDeviceList(text)
    }
    onExited: root.deviceScanRunning = false
  }

  IpcHandler {
    target: root.moduleName

    function toggle(): void { root.setCatActive(!root.catActive) }
    function enable(): void { root.setCatActive(true) }
    function disable(): void { root.setCatActive(false) }
    function lock(): void { root.setPositionLocked(true) }
    function unlock(): void { root.setPositionLocked(false) }
    function resize(width: int): void { root.setCatWidth(width) }
    function workspace(id: int): void { root.setWorkspaceId(id) }
    function test(): void { root.testAnimation() }
    function rescan(): void { root.scanDevices(); root.updateInputProcess() }
    function allowInput(): void { root.setInputAccess(true) }
    function revokeInput(): void { root.setInputAccess(false) }
    function status(): string {
      return JSON.stringify({
        active: root.catActive,
        locked: root.positionLocked,
        input: root.inputState,
        keyboards: root.inputCount,
        x: root.positionX,
        y: root.positionY,
        width: root.catWidth,
        workspace: root.workspaceId
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
        visible: root.catVisible && root.positionLocked
          && root.screenEnabled(screenScope.modelData)
          && root.workspaceEnabled(screenScope.modelData)
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
          top: root.positionY >= 0 ? root.resolvedWindowY(screenScope.modelData) : 0
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
        visible: root.catVisible && !root.positionLocked
          && root.screenEnabled(screenScope.modelData)
          && root.workspaceEnabled(screenScope.modelData)
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
          y: root.resolvedWindowY(screenScope.modelData)
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
              root.previewPosition(point.x - pressOffsetX,
                point.y - pressOffsetY + root.frameTopInset, screenScope.modelData)
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
