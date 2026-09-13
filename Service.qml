pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "PrivacyState.js" as PrivacyState
import "SettingsAdapter.js" as SettingsAdapter

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string moduleName: "hancore.bongocat"
  readonly property string runtimeHome: Quickshell.env("XDG_RUNTIME_DIR")
  readonly property string runtimeInstanceId: String(Quickshell.instanceId || "")
  readonly property string helperPath: localPath("helper/bongo-input")
  readonly property string accessScript: localPath("helper/input-access")
  readonly property string pendingSettingsPath: runtimeHome
    + "/omarchy/bongocat/pending-settings.json"

  property var pluginSettings: ({})
  property int panelSessionCount: 0
  property bool settingsDirty: false
  property var pendingSettingKeys: ({})
  property var pendingRecoveryPatch: ({})
  property var journalSettingKeys: ({})
  property string pendingJournalInstanceId: ""
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
  property int keypressDuration: 100
  property string keyboardName: ""
  property string monitorName: ""
  property int workspaceId: 0
  property string colorMode: "default"
  property string customColor: "#f0abab"
  readonly property string screensaverClass: "org.omarchy.screensaver"
  property var modelScreensaverWindows: ({})
  property int modelScreensaverWindowCount: 0
  property var eventScreensaverWindows: ({})
  property int eventScreensaverWindowCount: 0
  // Omarchy 4.0.3 does not expose idle/lock service objects to third-party
  // services. Track the public Hyprland toplevel model instead, including its
  // initial contents and reconnect-driven replacements. Session-lock surfaces
  // are compositor-exclusive; the ordinary bar-off preference is unrelated.
  readonly property bool presentationSuppressed:
    modelScreensaverWindowCount > 0 || eventScreensaverWindowCount > 0
  readonly property bool catVisible: catActive && !presentationSuppressed
  readonly property bool catColorized: colorMode !== "default"
  readonly property color catTint: colorMode === "theme"
    ? Color.accent : customColor

  property alias leftDown: pawAnimator.leftDown
  property alias rightDown: pawAnimator.rightDown
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
  property bool runtimeStarted: false

  readonly property string frameFile: pawAnimator.frameFile
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
      keypressDuration: 100,
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
        if (key !== "id" && key !== "__proto__" && key !== "constructor"
            && key !== "prototype") merged[key] = settings[key]
      }
    }
    return merged
  }

  function applySettings(settings) {
    var next = mergedSettings(settings)
    var oldActive = catActive
    var oldKeyboard = keyboardName

    catActive = boolValue(next.active, true)
    positionLocked = boolValue(next.positionLocked, true)
    positionX = intValue(next.positionX, -1, -1, 16000)
    positionY = intValue(next.positionY, -1, -1, 16000)
    catWidth = intValue(next.catWidth, 280, minimumCatWidth, maximumCatWidth)
    keypressDuration = intValue(next.keypressDuration, 100, 10, 5000)
    keyboardName = String(next.keyboardName || "")
    monitorName = String(next.monitorName || "")
    workspaceId = intValue(next.workspaceId, 0, 0, 10)
    var nextMode = String(next.colorMode || "default")
    colorMode = nextMode === "theme" || nextMode === "hex" ? nextMode : "default"
    var nextColor = String(next.customColor || "#f0abab")
    customColor = /^#[0-9a-fA-F]{6}$/.test(nextColor) ? nextColor : "#f0abab"

    // Keep the persisted snapshot canonical while preserving ordinary
    // host-owned entry metadata such as Shibumi's module marker.
    next.active = catActive
    next.positionLocked = positionLocked
    next.positionX = positionX
    next.positionY = positionY
    next.catWidth = catWidth
    next.keypressDuration = keypressDuration
    next.keyboardName = keyboardName
    next.monitorName = monitorName
    next.workspaceId = workspaceId
    next.colorMode = colorMode
    next.customColor = customColor
    pluginSettings = next

    if (runtimeStarted && (oldActive !== catActive || oldKeyboard !== keyboardName))
      updateInputProcess()
  }

  function settingsFromConfig(config) {
    return SettingsAdapter.settingsFor(config, moduleName)
  }

  function settingsFromShell() {
    if (!shell) return null
    if ("barConfig" in shell && shell.barConfig)
      return settingsFromConfig(shell.barConfig)
    // Compatibility with older trusted hosts that injected the full config.
    return "shellConfig" in shell && shell.shellConfig
      ? settingsFromConfig(shell.shellConfig) : null
  }

  function syncFromShell() {
    if (panelSessionCount > 0 || settingsDirty || persistVerificationPending) return
    var found = settingsFromShell()
    if (!found) return
    applySettings(found)
    // An accepted host mutation is only an in-memory acknowledgement. Keep
    // the recovery journal current until another Quickshell incarnation has
    // proved that the values reached shell.json.
    if (Object.keys(journalSettingKeys).length > 0) writePendingJournal()
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
    // During a panel session, historical journal keys must still follow newer
    // host updates. Only currently dirty or in-flight keys belong to local
    // state; otherwise crash recovery could roll an external write back.
    var hostSettings = settingsFromShell()
    var canonicalHost = hostSettings ? mergedSettings(hostSettings) : null
    var values = SettingsAdapter.journalValues(pluginSettings,
      canonicalHost, journalSettingKeys, pendingSettingKeys,
      persistVerificationPatch)
    if (Object.keys(values).length === 0) return
    pendingJournalInstanceId = runtimeInstanceId
    pendingSettingsFile.setText(JSON.stringify({
      version: 2,
      instanceId: runtimeInstanceId,
      settings: values
    }) + "\n")
  }

  function clearPendingJournal() {
    pendingJournalInstanceId = ""
    pendingRecoveryPatch = ({})
    pendingSettingKeys = ({})
    journalSettingKeys = ({})
    pendingSettingsFile.setText("")
  }

  function verifyPersistedSettings() {
    if (!persistVerificationPending) return
    var stored = settingsFromShell()
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
      Qt.callLater(persistPendingSettings)
    } else {
      // Do not clear on barConfigChanged: Omarchy publishes that in-memory
      // snapshot before its asynchronous FileView write reaches disk.
      writePendingJournal()
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
      if (parsed && (parsed.version === 1 || parsed.version === 2)
          && parsed.settings && typeof parsed.settings === "object"
          && !Array.isArray(parsed.settings)) {
        var recovered = ({})
        var allowed = Object.keys(defaults())
        var keys = Object.keys(parsed.settings)
        for (var i = 0; i < keys.length; ++i) {
          var key = keys[i]
          if (allowed.indexOf(key) !== -1) recovered[key] = parsed.settings[key]
        }
        pendingJournalInstanceId = parsed.version === 2
          ? String(parsed.instanceId || "") : ""
        pendingRecoveryPatch = recovered
        if (Object.keys(recovered).length > 0) recoverPendingJournal()
        else clearPendingJournal()
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
    if (SettingsAdapter.journalIsDurable(pendingJournalInstanceId,
        runtimeInstanceId, shellSettings, pendingRecoveryPatch)) {
      clearPendingJournal()
      return
    }

    var latest = mergedSettings(shellSettings)
    var modified = ({})
    var allowed = Object.keys(defaults())
    for (var i = 0; i < keys.length; ++i) {
      var key = keys[i]
      if (allowed.indexOf(key) === -1) continue
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
    journalSettingKeys = modified
    settingsDirty = true
    persistPendingSettings()
  }

  function persistPendingSettings() {
    if (!settingsDirty) return
    writePendingJournal()
    if (persistVerificationPending) return
    if (!shell || typeof shell.updateEntryInline !== "function") {
      persistenceRetryTimer.restart()
      return
    }
    var shellSettings = settingsFromShell()
    if (!shellSettings) {
      persistenceRetryTimer.restart()
      return
    }

    var local = mergedSettings(pluginSettings)
    var latest = SettingsAdapter.mergeDirtySettings(
      mergedSettings(shellSettings), local, pendingSettingKeys)
    var verification = ({})
    for (var key in pendingSettingKeys) {
      if (pendingSettingKeys[key]) verification[key] = local[key]
    }

    applySettings(latest)
    pendingSettingKeys = ({})
    settingsDirty = false
    persistVerificationPatch = verification
    persistVerificationPending = true
    persistVerificationAttempts = 0
    try {
      // This is the scoped Omarchy 4.0.3 persistence API. It accepts only the
      // calling plugin's entry and keeps unrelated shell.json fields intact.
      shell.updateEntryInline(moduleName, latest)
      Qt.callLater(verifyPersistedSettings)
      if (persistVerificationPending) persistenceVerificationTimer.restart()
    } catch (error) {
      console.warn("Bongo Cat could not persist shell settings")
      retryUnverifiedPersistence()
    }
  }

  function patchSettings(patch) {
    var next = mergedSettings(pluginSettings)
    var dirty = ({})
    var journal = ({})
    var allowed = Object.keys(defaults())
    for (var key in pendingSettingKeys) dirty[key] = pendingSettingKeys[key]
    for (var journalKey in journalSettingKeys)
      journal[journalKey] = journalSettingKeys[journalKey]
    for (var patchKey in patch) {
      if (allowed.indexOf(patchKey) === -1) continue
      next[patchKey] = patch[patchKey]
      dirty[patchKey] = true
      journal[patchKey] = true
    }
    applySettings(next)
    pendingSettingKeys = dirty
    journalSettingKeys = journal
    settingsDirty = true
    if (panelSessionCount > 0 || persistVerificationPending) writePendingJournal()
    else persistPendingSettings()
  }

  function applyIpcSettings(rawPatch) {
    var text = String(rawPatch || "")
    if (text.length === 0 || text.length > 4096) return false
    try {
      var parsed = JSON.parse(text)
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return false
      var allowed = Object.keys(defaults())
      var keys = Object.keys(parsed)
      var accepted = ({})
      for (var i = 0; i < keys.length; ++i) {
        var key = keys[i]
        if (allowed.indexOf(key) !== -1) accepted[key] = parsed[key]
      }
      if (Object.keys(accepted).length === 0) return false
      patchSettings(accepted)
      return true
    } catch (error) {
      return false
    }
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
    patchSettings({ keypressDuration: intValue(value, 100, 10, 5000) })
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

  function refreshPresentationSuppression() {
    var toplevels = Hyprland.toplevels ? Hyprland.toplevels.values : []
    var snapshot = PrivacyState.matchingToplevels(toplevels || [], screensaverClass)
    modelScreensaverWindows = snapshot.windows
    modelScreensaverWindowCount = snapshot.count
    // Once the authoritative model has observed a raw-open address, it owns
    // that lifetime. Until then, retain the event entry across stale snapshots.
    var unconfirmed = PrivacyState.withoutConfirmedWindows(
      eventScreensaverWindows, snapshot.windows)
    eventScreensaverWindows = unconfirmed.windows
    eventScreensaverWindowCount = unconfirmed.count
  }

  function setScreensaverWindow(address, visible) {
    var next = PrivacyState.windowsAfter(eventScreensaverWindows, address, visible)
    eventScreensaverWindows = next.windows
    eventScreensaverWindowCount = next.count
  }

  function handleHyprlandEvent(event) {
    var name = String(event && event.name ? event.name : "")
    if (name === "openwindow") {
      var opened = PrivacyState.eventParts(event, 4)
      if (String(opened[2] || "") === screensaverClass)
        setScreensaverWindow(opened[0], true)
    } else if (name === "closewindow") {
      var closed = PrivacyState.eventParts(event, 1)
      setScreensaverWindow(closed[0], false)
    }
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

  function pressLeft() { pawAnimator.pressLeft() }
  function pressRight() { pawAnimator.pressRight() }
  function testAnimation() { pawAnimator.testAnimation() }

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
      pawAnimator.releaseAll()
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
      pawAnimator.releaseAll()
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

  function startRuntime() {
    if (runtimeStarted) return
    runtimeStarted = true
    syncFromShell()
    loadPendingJournal(pendingSettingsFile.text())
    refreshPresentationSuppression()
    scanDevices()
    updateInputProcess()
    checkInputAccess()
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
    target: Hyprland
    function onRawEvent(event) { root.handleHyprlandEvent(event) }
  }

  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() { presentationRefreshTimer.restart() }
  }

  Connections {
    target: root.shell
    ignoreUnknownSignals: true
    function synchronizeSettings(service) {
      // Config signals can already be queued while a plugin instance is being
      // destroyed during a shell reload. Do not dereference that dead context.
      if (!service) return
      service.verifyPersistedSettings()
      service.syncFromShell()
      service.recoverPendingJournal()
      service.writePendingJournal()
    }
    function onBarConfigChanged() { synchronizeSettings(root) }
    function onShellConfigChanged() { synchronizeSettings(root) }
  }

  Component.onCompleted: {
    applySettings(defaults())
    // The host injects the scoped shell facade immediately after createObject.
    // Defer side effects so persisted active:false is honored before scanning.
    Qt.callLater(startRuntime)
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

  Timer {
    id: presentationRefreshTimer
    interval: 100
    repeat: false
    onTriggered: root.refreshPresentationSuppression()
  }

  Timer {
    id: persistenceVerificationTimer
    interval: 250
    repeat: true
    onTriggered: {
      root.persistVerificationAttempts += 1
      root.verifyPersistedSettings()
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

  PawAnimator {
    id: pawAnimator
    keypressDuration: root.keypressDuration
    testAnimationDuration: 200
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
    function configure(patchJson: string): bool {
      return root.applyIpcSettings(patchJson)
    }
    function keyboards(): string { return JSON.stringify(root.keyboardOptions()) }
    function status(): string {
      var screenObject = root.targetScreen()
      return JSON.stringify({
        active: root.catActive,
        locked: root.positionLocked,
        input: root.inputState,
        keyboards: root.inputCount,
        keyboardName: root.keyboardName,
        x: screenObject ? Math.round(root.resolvedX(screenObject))
          : Math.max(0, root.positionX),
        y: screenObject ? Math.round(root.resolvedY(screenObject))
          : Math.max(0, root.positionY),
        maxX: screenObject ? Math.max(0, screenObject.width - root.catWidth) : 16000,
        maxY: screenObject ? Math.max(0, screenObject.height - root.catHeight) : 16000,
        width: root.catWidth,
        duration: root.keypressDuration,
        monitor: root.monitorName,
        workspace: root.workspaceId,
        colorMode: root.colorMode,
        customColor: root.customColor,
        presentationSuppressed: root.presentationSuppressed,
        needsInputAccess: root.needsInputAccess,
        accessInstalled: root.accessInstalled,
        accessBusy: root.accessBusy,
        accessError: root.accessError
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
