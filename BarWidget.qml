pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "SettingsAdapter.js" as SettingsAdapter

Panel {
  id: root

  moduleName: "hancore.bongocat"
  ipcTarget: ""
  manageIpc: false

  readonly property var bongo: bar && bar.shell
    && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null
  readonly property bool serviceAvailable: !!(bongo
    && typeof bongo.setCatWidth === "function")
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color background: bar ? bar.background : Color.background
  readonly property color accent: bar ? bar.urgent : Color.accent
  readonly property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.58)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var activeScreen: serviceAvailable ? bongo.targetScreen() : null
  readonly property int positionXValue: serviceAvailable && activeScreen
    ? Math.round(bongo.resolvedX(activeScreen))
    : ipcStatusReady ? Number(ipcStatus.x) : Math.max(0, fallbackNumber("positionX", 0))
  readonly property int positionYValue: serviceAvailable && activeScreen
    ? Math.round(bongo.resolvedY(activeScreen))
    : ipcStatusReady ? Number(ipcStatus.y) : Math.max(0, fallbackNumber("positionY", 0))
  readonly property int positionXMaximum: serviceAvailable && activeScreen
    ? Math.max(0, activeScreen.width - bongo.catWidth)
    : ipcStatusReady ? Number(ipcStatus.maxX) : 8000
  readonly property int positionYMaximum: serviceAvailable && activeScreen
    ? Math.max(0, activeScreen.height - bongo.catHeight)
    : ipcStatusReady ? Number(ipcStatus.maxY) : 8000
  readonly property bool presentationSuppressed: serviceAvailable
    ? bongo.presentationSuppressed : ipcStatus.presentationSuppressed === true
  readonly property bool catOn: serviceAvailable
    ? bongo.catActive : fallbackBool("active", true)
  readonly property bool catLocked: serviceAvailable
    ? bongo.positionLocked : fallbackBool("positionLocked", true)
  readonly property int catSize: serviceAvailable
    ? bongo.catWidth : fallbackNumber("catWidth", 280)
  readonly property string catColorMode: serviceAvailable
    ? bongo.colorMode : String(fallbackSetting("colorMode", "default"))
  readonly property string catCustomColor: serviceAvailable
    ? bongo.customColor : String(fallbackSetting("customColor", "#f0abab"))
  readonly property int pawDuration: serviceAvailable
    ? bongo.keypressDuration : fallbackNumber("keypressDuration", 100)
  readonly property string selectedMonitor: serviceAvailable
    ? bongo.monitorName : String(fallbackSetting("monitorName", ""))
  readonly property string selectedKeyboard: serviceAvailable
    ? bongo.keyboardName : String(fallbackSetting("keyboardName", ""))
  readonly property int selectedWorkspace: serviceAvailable
    ? bongo.workspaceId : fallbackNumber("workspaceId", 0)
  readonly property bool positionControlsReady: catOn
    && (serviceAvailable || ipcStatusReady)
  property var panelSessionService: null
  property var localPatch: ({})
  property var ipcStatus: ({})
  property bool ipcStatusReady: false
  property bool statusRefreshPending: false
  property var ipcKeyboards: []
  property var ipcActions: []
  property string fallbackError: ""

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (opened) {
      beginPanelSession()
      if (serviceAvailable) {
        bongo.checkInputAccess()
        bongo.scanDevices()
      } else {
        requestStatus()
        invokeIpc(["rescan"], true)
      }
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else {
      finishPanelSession()
    }
  }

  onBongoChanged: if (opened) beginPanelSession()
  onSettingsChanged: {
    localPatch = ({})
    if (opened && !serviceAvailable) requestStatus()
  }
  onPresentationSuppressedChanged: if (presentationSuppressed) close()
  Component.onDestruction: abandonPanelSession()

  function fallbackSetting(key, fallback) {
    if (localPatch && localPatch[key] !== undefined && localPatch[key] !== null)
      return localPatch[key]
    if (settings && settings[key] !== undefined && settings[key] !== null)
      return settings[key]
    return fallback
  }

  function fallbackBool(key, fallback) {
    var value = fallbackSetting(key, fallback)
    if (value === true || value === false) return value
    var text = String(value).toLowerCase()
    return text === "true" || text === "1" || text === "yes" || text === "on"
  }

  function fallbackNumber(key, fallback) {
    var value = Number(fallbackSetting(key, fallback))
    return isFinite(value) ? value : fallback
  }

  function persistFallback(patch) {
    var previous = localPatch
    var mergedPatch = SettingsAdapter.mergedEntry("", previous, null, patch)
    delete mergedPatch.id
    localPatch = mergedPatch

    var host = bar && bar.shell
    if (!host || typeof host.updateEntryInline !== "function") {
      localPatch = previous
      fallbackError = "This bar cannot save Bongo Cat settings"
      return false
    }
    var entry = SettingsAdapter.mergedEntry(moduleName, settings, previous, patch)
    var changed = JSON.stringify(entry) !== JSON.stringify(
      SettingsAdapter.mergedEntry(moduleName, settings, null, null))
    try {
      var accepted = host.updateEntryInline(moduleName, entry)
      if (changed && accepted !== true) {
        localPatch = previous
        fallbackError = "Bongo Cat settings were rejected by the bar"
        return false
      }
      fallbackError = ""
      if (changed) invokeIpc(["configure", JSON.stringify(patch)], false)
      else statusRefreshTimer.restart()
      return true
    } catch (error) {
      localPatch = previous
      fallbackError = "Bongo Cat settings could not be saved"
      return false
    }
  }

  function beginPanelSession() {
    if (panelSessionService || !serviceAvailable
        || typeof bongo.beginPanelSession !== "function") return
    panelSessionService = bongo
    panelSessionService.beginPanelSession()
  }

  function finishPanelSession() {
    if (!panelSessionService) return
    var service = panelSessionService
    panelSessionService = null
    if (typeof service.endPanelSession === "function") service.endPanelSession()
  }

  function abandonPanelSession() {
    if (!panelSessionService) return
    var service = panelSessionService
    panelSessionService = null
    if (typeof service.abandonPanelSession === "function") service.abandonPanelSession()
  }

  function toggleActive() {
    if (serviceAvailable) bongo.setCatActive(!bongo.catActive)
    else persistFallback({ active: !catOn })
  }

  function applyPositionLocked(value) {
    if (serviceAvailable) bongo.setPositionLocked(value)
    else persistFallback({ positionLocked: !!value })
  }

  function applyCatWidth(value) {
    var next = Math.max(60, Math.min(640, Math.round(Number(value) || 280)))
    if (serviceAvailable) bongo.setCatWidth(next)
    else persistFallback({ catWidth: next })
  }

  function previewCatWidth(value) {
    var next = Math.max(60, Math.min(640, Math.round(Number(value) || 280)))
    if (serviceAvailable) bongo.previewCatWidth(next)
    else localPatch = SettingsAdapter.mergedEntry("", localPatch, null,
      { catWidth: next })
  }

  function applyColorMode(value) {
    if (serviceAvailable) bongo.setColorMode(value)
    else persistFallback({ colorMode: String(value || "default") })
  }

  function applyCustomColor(value) {
    if (serviceAvailable) bongo.setCustomColor(value)
    else persistFallback({ customColor: value, colorMode: "hex" })
  }

  function applyPosition(x, y) {
    var nx = Math.max(0, Math.min(positionXMaximum, Math.round(Number(x) || 0)))
    var ny = Math.max(0, Math.min(positionYMaximum, Math.round(Number(y) || 0)))
    if (serviceAvailable) bongo.setPosition(nx, ny)
    else persistFallback({ positionX: nx, positionY: ny })
  }

  function moveFromPanel(dx, dy) {
    applyPosition(positionXValue + dx, positionYValue + dy)
  }

  function invokeIpc(args, refreshKeyboards) {
    if (serviceAvailable) return
    var next = ipcActions.slice()
    next.push({ args: args, refreshKeyboards: refreshKeyboards === true })
    ipcActions = next
    runNextIpcAction()
  }

  function runNextIpcAction() {
    if (serviceAvailable || ipcAction.running || ipcActions.length === 0) return
    var next = ipcActions.slice()
    var action = next.shift()
    ipcActions = next
    ipcAction.refreshKeyboards = action.refreshKeyboards
    ipcAction.command = ["omarchy-shell", moduleName].concat(action.args)
    ipcAction.running = true
  }

  function finishIpcAction(exitCode) {
    if (exitCode !== 0) fallbackError = "Bongo Cat service is unavailable"
    requestStatus()
    if (ipcAction.refreshKeyboards) keyboardRefreshTimer.restart()
    runNextIpcAction()
  }

  function requestStatus() {
    if (serviceAvailable) return
    if (ipcStatusQuery.running) {
      statusRefreshPending = true
      return
    }
    ipcStatusQuery.command = ["omarchy-shell", moduleName, "status"]
    ipcStatusQuery.running = true
  }

  function finishStatusRequest(exitCode) {
    if (exitCode !== 0) {
      ipcStatusReady = false
      fallbackError = "Bongo Cat service is unavailable"
    }
    if (statusRefreshPending) {
      statusRefreshPending = false
      Qt.callLater(requestStatus)
    }
  }

  function requestKeyboards() {
    if (serviceAvailable || ipcKeyboardsQuery.running) return
    ipcKeyboardsQuery.command = ["omarchy-shell", moduleName, "keyboards"]
    ipcKeyboardsQuery.running = true
  }

  function invalidateStatus() {
    ipcStatus = ({})
    ipcStatusReady = false
    fallbackError = "Bongo Cat returned an invalid status"
  }

  function takeStatus(raw) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      var numericKeys = ["x", "y", "maxX", "maxY", "keyboards"]
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)
          || typeof parsed.input !== "string"
          || typeof parsed.presentationSuppressed !== "boolean"
          || typeof parsed.needsInputAccess !== "boolean"
          || typeof parsed.accessInstalled !== "boolean"
          || typeof parsed.accessBusy !== "boolean") {
        invalidateStatus()
        return
      }
      for (var i = 0; i < numericKeys.length; ++i) {
        var rawValue = parsed[numericKeys[i]]
        var value = Number(rawValue)
        if (typeof rawValue !== "number" || !isFinite(value) || value < 0) {
          invalidateStatus()
          return
        }
      }
      ipcStatus = parsed
      ipcStatusReady = true
      fallbackError = ""
    } catch (error) {
      invalidateStatus()
    }
  }

  function takeKeyboards(raw) {
    try {
      var parsed = JSON.parse(String(raw || "[]"))
      if (!Array.isArray(parsed) || parsed.length > 512) {
        ipcKeyboards = []
        return
      }
      var sanitized = []
      for (var i = 0; i < parsed.length; ++i) {
        var option = parsed[i]
        if (!option || typeof option !== "object" || Array.isArray(option)) continue
        var value = String(option.value || "")
        var label = String(option.label || "")
        if (value.length <= 256 && label.length <= 512)
          sanitized.push({ value: value, label: label })
      }
      ipcKeyboards = sanitized
    } catch (error) {
      ipcKeyboards = []
    }
  }

  function fallbackInputStatusText() {
    if (!catOn) return "Disabled"
    if (!ipcStatusReady) return "Connecting to Bongo Cat…"
    if (ipcStatus.presentationSuppressed === true) return "Hidden for screen privacy"
    if (ipcStatus.input === "authorizing") return "Waiting for input authorization…"
    if (ipcStatus.input === "scanning") return "Scanning keyboards…"
    if (ipcStatus.input === "ready") {
      var count = Math.max(0, Number(ipcStatus.keyboards) || 0)
      return count + (count === 1 ? " keyboard active" : " keyboards active")
    }
    if (ipcStatus.input === "permission") return "Input access required"
    if (ipcStatus.input === "no-device") return "No keyboard found"
    return String(ipcStatus.accessError || fallbackError || "Input helper unavailable")
  }

  function fallbackMonitorOptions() {
    var options = [{ value: "", label: "Primary monitor" }]
    var screens = Quickshell.screens || []
    for (var i = 0; i < screens.length; ++i) {
      var name = String(screens[i].name || "")
      if (name !== "") options.push({ value: name, label: name })
    }
    return options
  }

  function fallbackKeyboardOptions() {
    // The service already includes a configured-but-missing keyboard. Keeping
    // this function independent of selectedKeyboard avoids a value/options
    // binding cycle in host-provided Dropdown implementations.
    return ipcKeyboards.slice()
  }

  Process {
    id: ipcAction
    property bool refreshKeyboards: false
    onExited: function(exitCode) { root.finishIpcAction(exitCode) }
  }

  Process {
    id: ipcStatusQuery
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.takeStatus(text)
    }
    onExited: function(exitCode) { root.finishStatusRequest(exitCode) }
  }

  Process {
    id: ipcKeyboardsQuery
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.takeKeyboards(text)
    }
  }

  Timer {
    id: statusRefreshTimer
    interval: 100
    repeat: false
    onTriggered: root.requestStatus()
  }

  Timer {
    id: keyboardRefreshTimer
    interval: 350
    repeat: false
    onTriggered: root.requestKeyboards()
  }

  Timer {
    interval: 500
    repeat: true
    running: root.opened && !root.serviceAvailable && root.ipcStatusReady
      && (root.ipcStatus.input === "scanning"
        || root.ipcStatus.input === "authorizing"
        || root.ipcStatus.accessBusy === true)
    onTriggered: root.requestStatus()
  }

  component PanelGlyphButton: Button {
    id: glyphButton

    property string glyph: ""
    property color glyphColor: selected
      ? Style.selectedStateColor(foreground, accent) : foreground
    property real glyphCanvasSize: Math.max(Style.space(22), iconSize + Style.space(4))

    iconText: ""

    OpticalGlyph {
      anchors.centerIn: parent
      width: glyphButton.glyphCanvasSize
      height: glyphButton.glyphCanvasSize
      text: glyphButton.glyph
      fontFamily: glyphButton.fontFamily
      fontSize: glyphButton.iconSize
      color: glyphButton.glyphColor
    }
  }

  component FieldLabel: Text {
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    font.bold: false
  }

  component EqualChoiceGroup: Row {
    id: choiceGroup

    property var options: []
    property string value: ""
    property color foreground: root.foreground
    property color background: root.background
    property color accent: root.accent
    property string fontFamily: root.fontFamily
    property real buttonWidth: Style.space(80)
    property int focusedIndex: -1

    signal changed(string value)

    spacing: Style.spacing.md
    height: Style.spacing.controlHeight
    activeFocusOnTab: true

    function optionValue(option) {
      return String(option && typeof option === "object" ? option.value : option)
    }

    function optionLabel(option) {
      return String(option && typeof option === "object" ? option.label : option)
    }

    function selectedIndex() {
      for (var i = 0; i < options.length; i++)
        if (optionValue(options[i]) === value) return i
      return 0
    }

    onActiveFocusChanged: focusedIndex = activeFocus ? selectedIndex() : -1

    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Left || event.key === Qt.Key_H || event.text === "h") {
        focusedIndex = Math.max(0, focusedIndex - 1)
        event.accepted = true
      } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L || event.text === "l") {
        focusedIndex = Math.min(options.length - 1, focusedIndex + 1)
        event.accepted = true
      } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter
          || event.key === Qt.Key_Space) && focusedIndex >= 0) {
        changed(optionValue(options[focusedIndex]))
        event.accepted = true
      }
    }

    Repeater {
      model: choiceGroup.options

      delegate: Button {
        required property var modelData
        required property int index

        width: choiceGroup.buttonWidth
        height: choiceGroup.height
        text: choiceGroup.optionLabel(modelData)
        active: choiceGroup.optionValue(modelData) === choiceGroup.value
        hasCursor: choiceGroup.activeFocus && choiceGroup.focusedIndex === index
        bordered: true
        foreground: choiceGroup.foreground
        background: choiceGroup.background
        accent: choiceGroup.accent
        fontFamily: choiceGroup.fontFamily
        onClicked: choiceGroup.changed(choiceGroup.optionValue(modelData))
      }
    }
  }

  component BongoKeyCatcher: Item {
    id: catcher

    property bool blocked: false
    property bool escapeBlocked: false

    signal moveRequested(int dx, int dy)
    signal activateRequested()
    signal returnRequested()
    signal closeRequested()
    signal deleteRequested()
    signal tabRequested(int direction)
    signal textKey(string text)

    focus: true
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Escape) {
        if (!escapeBlocked) {
          closeRequested()
          event.accepted = true
        }
        return
      }
      if (blocked) return

      if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
        tabRequested((event.modifiers & Qt.ShiftModifier)
          || event.key === Qt.Key_Backtab ? -1 : 1)
        event.accepted = true
      } else if (event.key === Qt.Key_Down || event.text === "j") {
        moveRequested(0, 1)
        event.accepted = true
      } else if (event.key === Qt.Key_Up || event.text === "k") {
        moveRequested(0, -1)
        event.accepted = true
      } else if (event.key === Qt.Key_Right || event.text === "l") {
        moveRequested(1, 0)
        event.accepted = true
      } else if (event.key === Qt.Key_Left || event.text === "h") {
        moveRequested(-1, 0)
        event.accepted = true
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        returnRequested()
        activateRequested()
        event.accepted = true
      } else if (event.key === Qt.Key_Space) {
        activateRequested()
        event.accepted = true
      } else if (event.text === "x" || event.text === "X") {
        deleteRequested()
        event.accepted = true
      } else if (event.text && event.text.length === 1) {
        textKey(event.text)
      }
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    fixedWidth: Style.bar.iconSlot
    labelVisible: false
    hasVisualContent: true
    active: root.catOn
    tooltipText: root.catOn
      ? "Bongo Cat · " + (root.serviceAvailable
        ? root.bongo.inputStatusText() : root.fallbackInputStatusText())
      : "Bongo Cat is off"

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.toggleActive()
      else if (buttonCode === Qt.MiddleButton) {
        if (root.serviceAvailable) root.bongo.testAnimation()
        else root.invokeIpc(["test"], false)
      } else root.toggle()
    }

    OpticalGlyph {
      anchors.centerIn: parent
      width: Style.space(24)
      height: Style.space(24)
      text: "󰄛"
      fontFamily: root.fontFamily
      fontSize: Style.font.iconLarge
      color: root.serviceAvailable && root.bongo.catColorized
        ? root.bongo.catTint : root.foreground
      opacity: root.catOn ? 1 : 0.38
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(560))

    BongoKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: !activeFocus || keyboardPicker.popupOpen || monitorPicker.popupOpen
      escapeBlocked: keyboardPicker.popupOpen || monitorPicker.popupOpen
      onCloseRequested: root.close()
      onTabRequested: function(direction) {
        if (direction < 0 && testButton.enabled) testButton.forceActiveFocus()
        else enableButton.forceActiveFocus()
      }
      onMoveRequested: function(dx, dy) {
        root.moveFromPanel(dx * 10, dy * 10)
      }
      onTextKey: function(text) {
        if (text === "t" || text === "T") {
          if (root.serviceAvailable) root.bongo.testAnimation()
          else root.invokeIpc(["test"], false)
        } else if (text === "p" || text === "P") {
          root.applyPositionLocked(!root.catLocked)
        } else if (text === "r" || text === "R") {
          if (root.serviceAvailable) {
            root.bongo.scanDevices()
            root.bongo.updateInputProcess()
          } else root.invokeIpc(["rescan"], true)
        }
      }

      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: content
          width: scroll.width
          spacing: Style.space(8)

          Row {
            width: parent.width
            height: Math.max(Style.space(38), headerActions.implicitHeight,
              Style.space(26))
            spacing: Style.space(10)

            CatImage {
              width: 62
              height: 26
              anchors.verticalCenter: parent.verticalCenter
              source: root.serviceAvailable ? root.bongo.idleSource
                : Qt.resolvedUrl("assets/bongo-cat-both-up.png")
              colorized: root.serviceAvailable ? root.bongo.catColorized : false
              tint: root.serviceAvailable ? root.bongo.catTint : "white"
            }

            Column {
              width: parent.width - 62 - headerActions.width - parent.spacing * 2
              anchors.verticalCenter: parent.verticalCenter
              spacing: 1

              Text {
                text: "Bongo Cat"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
              }
              Text {
                text: root.serviceAvailable
                  ? root.bongo.inputStatusText() : root.fallbackInputStatusText()
                color: Qt.darker(root.foreground, 1.25)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: false
                renderType: Text.NativeRendering
                elide: Text.ElideRight
                width: parent.width
              }
            }

            Row {
              id: headerActions
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(5)

              PanelGlyphButton {
                id: enableButton
                width: Style.spacing.controlHeight
                height: Style.spacing.controlHeight
                glyph: "\uf011"
                iconSize: Math.max(1, Style.font.iconLarge - 1)
                tooltipText: root.catOn ? "Disable" : "Enable"
                selected: root.catOn
                glyphColor: selected
                  ? Style.selectedStateColor(foreground, accent) : root.dim
                bordered: true
                focusable: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.toggleActive()
              }
              PanelGlyphButton {
                id: lockButton
                width: Style.spacing.controlHeight
                height: Style.spacing.controlHeight
                glyph: root.catLocked ? "\uf023" : "\uf09c"
                iconSize: Math.max(1, Style.font.iconLarge - 1)
                tooltipText: root.catLocked
                  ? "Locked · Click to unlock" : "Unlocked · Click to lock"
                selected: root.catLocked
                glyphColor: selected
                  ? Style.selectedStateColor(foreground, accent) : root.accent
                enabled: root.catOn
                opacity: enabled ? 1 : 0.38
                bordered: true
                focusable: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.applyPositionLocked(!root.catLocked)
              }
              PanelGlyphButton {
                id: testButton
                width: Style.spacing.controlHeight
                height: Style.spacing.controlHeight
                glyph: "\uf0d0"
                iconSize: Math.max(1, Style.font.iconLarge - 1)
                tooltipText: "Test Animation (T)"
                enabled: root.catOn
                opacity: enabled ? 1 : 0.38
                bordered: true
                focusable: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: {
                  if (root.serviceAvailable) root.bongo.testAnimation()
                  else root.invokeIpc(["test"], false)
                }
              }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }
          FieldLabel {
            width: parent.width
            text: "APPEARANCE"
          }

          Row {
            width: parent.width
            spacing: Style.space(7)

            FieldLabel {
              width: 38
              anchors.verticalCenter: parent.verticalCenter
              text: "Size"
            }
            Button {
              id: sizeDownButton
              width: Style.spacing.controlHeight
              height: Style.spacing.controlHeight
              text: "−"
              tooltipText: "20 px smaller"
              bordered: true
              focusable: true
              foreground: root.foreground
              onClicked: root.applyCatWidth(root.catSize - 20)
            }
            PanelSlider {
              width: Math.max(80, parent.width - 38 - sizeDownButton.width
                - sizeUpButton.width - sizeValue.width - parent.spacing * 4)
              anchors.verticalCenter: parent.verticalCenter
              bar: root.bar
              value: root.catSize
              minimum: root.serviceAvailable ? root.bongo.minimumCatWidth : 60
              maximum: 640
              step: 20
              integer: true
              onMoved: function(next) { root.previewCatWidth(next) }
              onReleased: function(next) { root.applyCatWidth(next) }
            }
            Text {
              id: sizeValue
              width: 52
              anchors.verticalCenter: parent.verticalCenter
              text: root.catSize + " px"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
            }
            Button {
              id: sizeUpButton
              width: Style.spacing.controlHeight
              height: Style.spacing.controlHeight
              text: "+"
              tooltipText: "20 px larger"
              bordered: true
              focusable: true
              foreground: root.foreground
              onClicked: root.applyCatWidth(root.catSize + 20)
            }
          }

          EqualChoiceGroup {
            id: sizePresetGroup
            anchors.horizontalCenter: parent.horizontalCenter
            options: [
              { value: "60", label: "Small" },
              { value: "280", label: "Medium" },
              { value: "420", label: "Large" }
            ]
            value: String(root.catSize)
            onChanged: function(next) { root.applyCatWidth(parseInt(next, 10)) }
          }

          Item {
            width: parent.width
            height: colorModeGroup.height

            FieldLabel {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Color"
            }

            EqualChoiceGroup {
              id: colorModeGroup
              anchors.horizontalCenter: parent.horizontalCenter
              buttonWidth: sizePresetGroup.buttonWidth
              options: [
                { value: "default", label: "Default" },
                { value: "theme", label: "Theme" },
                { value: "hex", label: "Hex" }
              ]
              value: root.catColorMode
              onChanged: function(next) { root.applyColorMode(next) }
            }
          }

          Row {
            visible: root.catColorMode === "hex"
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(8)

            Rectangle {
              width: 26
              height: 26
              radius: Style.cornerRadius
              color: root.catCustomColor
              border.width: 1
              border.color: root.foreground
            }
            TextField {
              id: hexField
              width: 130
              text: root.catCustomColor
              placeholderText: "#RRGGBB"
              foreground: root.foreground
              accent: root.accent
              font.family: root.fontFamily
              validator: RegularExpressionValidator {
                regularExpression: /^#[0-9a-fA-F]{6}$/
              }
              onTextEdited: if (acceptableInput) root.applyCustomColor(text)
              onEditingFinished: if (acceptableInput) root.applyCustomColor(text)
              onActiveFocusChanged: {
                if (!activeFocus && !acceptableInput) text = root.catCustomColor
              }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }
          FieldLabel {
            width: parent.width
            text: "POSITION"
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            NumberField {
              id: positionXField
              width: (parent.width - parent.spacing) / 2
              enabled: root.positionControlsReady
              label: ""
              value: root.positionXValue
              from: 0
              to: root.positionXMaximum
              stepSize: 10
              fieldWidth: width
              field.leftPadding: Style.space(34)
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onModified: function(next) {
                root.applyPosition(next, root.positionYValue)
              }

              Text {
                parent: positionXField.field
                z: 2
                anchors.left: parent.left
                anchors.leftMargin: Style.space(11)
                anchors.verticalCenter: parent.verticalCenter
                text: "X"
                color: positionXField.enabled ? root.dim : Qt.darker(root.dim, 1.5)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
            }
            NumberField {
              id: positionYField
              width: (parent.width - parent.spacing) / 2
              enabled: root.positionControlsReady
              label: ""
              value: root.positionYValue
              from: 0
              to: root.positionYMaximum
              stepSize: 10
              fieldWidth: width
              field.leftPadding: Style.space(34)
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onModified: function(next) {
                root.applyPosition(root.positionXValue, next)
              }

              Text {
                parent: positionYField.field
                z: 2
                anchors.left: parent.left
                anchors.leftMargin: Style.space(11)
                anchors.verticalCenter: parent.verticalCenter
                text: "Y"
                color: positionYField.enabled ? root.dim : Qt.darker(root.dim, 1.5)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
            }
          }

          Row {
            id: positionActions
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(5)
            readonly property real controlWidth: Style.space(52)
            readonly property real controlHeight: Style.spacing.controlHeight

            PanelGlyphButton {
              width: positionActions.controlWidth
              height: positionActions.controlHeight
              glyph: "\uf060"
              iconSize: Style.font.icon
              tooltipText: "10 px left"
              enabled: root.positionControlsReady
              opacity: enabled ? 1 : 0.38
              bordered: true
              focusable: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.moveFromPanel(-10, 0)
            }
            PanelGlyphButton {
              width: positionActions.controlWidth
              height: positionActions.controlHeight
              glyph: "\uf062"
              iconSize: Style.font.icon
              tooltipText: "10 px up"
              enabled: root.positionControlsReady
              opacity: enabled ? 1 : 0.38
              bordered: true
              focusable: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.moveFromPanel(0, -10)
            }
            PanelGlyphButton {
              width: positionActions.controlWidth
              height: positionActions.controlHeight
              glyph: "\uf063"
              iconSize: Style.font.icon
              tooltipText: "10 px down"
              enabled: root.positionControlsReady
              opacity: enabled ? 1 : 0.38
              bordered: true
              focusable: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.moveFromPanel(0, 10)
            }
            PanelGlyphButton {
              width: positionActions.controlWidth
              height: positionActions.controlHeight
              glyph: "\uf061"
              iconSize: Style.font.icon
              tooltipText: "10 px right"
              enabled: root.positionControlsReady
              opacity: enabled ? 1 : 0.38
              bordered: true
              focusable: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.moveFromPanel(10, 0)
            }
            Button {
              width: positionActions.controlWidth
              height: positionActions.controlHeight
              text: "Reset"
              enabled: root.catOn
              opacity: enabled ? 1 : 0.38
              bordered: true
              focusable: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: {
                if (root.serviceAvailable) root.bongo.resetPosition()
                else {
                  root.ipcStatusReady = false
                  root.persistFallback({ positionX: -1, positionY: -1 })
                }
              }
            }
          }

          Row {
            width: parent.width
            height: Math.max(pawControl.implicitHeight, monitorControl.implicitHeight)
            spacing: Style.space(8)

            Column {
              id: pawControl
              width: (parent.width - parent.spacing) / 2
              spacing: Style.spacing.labelGap

              FieldLabel {
                text: "Paw (ms)"
              }

              NumberField {
                width: parent.width
                label: ""
                value: root.pawDuration
                from: 10
                to: 5000
                stepSize: 5
                fieldWidth: width
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onModified: function(next) {
                  if (root.serviceAvailable) root.bongo.setKeypressDuration(next)
                  else root.persistFallback({ keypressDuration: next })
                }
              }
            }

            Column {
              id: monitorControl
              width: (parent.width - parent.spacing) / 2
              spacing: Style.spacing.labelGap

              FieldLabel {
                text: "Monitor"
              }

              Dropdown {
                id: monitorPicker
                width: parent.width
                label: ""
                showLabel: false
                value: root.selectedMonitor
                options: root.serviceAvailable
                  ? root.bongo.monitorOptions() : root.fallbackMonitorOptions()
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onChanged: function(next) {
                  if (root.serviceAvailable) root.bongo.setMonitorName(next)
                  else root.persistFallback({ monitorName: String(next || "") })
                }
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.spacing.labelGap

            FieldLabel {
              text: "Show in Workspace"
            }

            Row {
              id: workspaceChoices
              width: parent.width
              height: Style.spacing.controlHeight
              spacing: Style.space(4)
              readonly property real allWidth: Style.space(44)
              readonly property real workspaceWidth:
                (width - allWidth - spacing * 10) / 10

              Button {
                width: workspaceChoices.allWidth
                height: workspaceChoices.height
                text: "All"
                active: root.selectedWorkspace === 0
                bordered: true
                focusable: true
                foreground: root.foreground
                background: root.background
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: {
                  if (root.serviceAvailable) root.bongo.setWorkspaceId(0)
                  else root.persistFallback({ workspaceId: 0 })
                }
              }

              Repeater {
                model: 10

                Button {
                  required property int index
                  readonly property int workspaceNumber: index + 1

                  width: workspaceChoices.workspaceWidth
                  height: workspaceChoices.height
                  text: String(workspaceNumber)
                  active: root.selectedWorkspace === workspaceNumber
                  bordered: true
                  focusable: true
                  foreground: root.foreground
                  background: root.background
                  accent: root.accent
                  fontFamily: root.fontFamily
                  onClicked: {
                    if (root.serviceAvailable) root.bongo.setWorkspaceId(workspaceNumber)
                    else root.persistFallback({ workspaceId: workspaceNumber })
                  }
                }
              }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }
          Row {
            width: parent.width
            height: Math.max(inputHeader.implicitHeight, inputRescanButton.implicitHeight)
            spacing: Style.space(8)

            FieldLabel {
              id: inputHeader
              width: parent.width - inputRescanButton.width - parent.spacing
              anchors.verticalCenter: parent.verticalCenter
              text: "INPUT"
            }

            Button {
              id: inputRescanButton
              anchors.verticalCenter: parent.verticalCenter
              height: Style.spacing.controlHeight
              text: (root.serviceAvailable && root.bongo.deviceScanRunning)
                || (!root.serviceAvailable && root.ipcStatus.input === "scanning")
                ? "Scanning…" : "Rescan"
              enabled: root.serviceAvailable
                ? !root.bongo.deviceScanRunning : !ipcAction.running
              bordered: true
              focusable: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: {
                if (root.serviceAvailable) {
                  root.bongo.scanDevices()
                  root.bongo.updateInputProcess()
                } else root.invokeIpc(["rescan"], true)
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.spacing.labelGap

            FieldLabel {
              text: "Keyboard"
            }

            Dropdown {
              id: keyboardPicker
              width: parent.width
              label: ""
              showLabel: false
              value: root.selectedKeyboard
              options: root.serviceAvailable
                ? root.bongo.keyboardOptions() : root.fallbackKeyboardOptions()
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onChanged: function(next) {
                if (root.serviceAvailable) root.bongo.setKeyboardName(next)
                else root.persistFallback({ keyboardName: String(next || "") })
              }
            }
          }

          Text {
            visible: text !== ""
            width: parent.width
            text: root.serviceAvailable ? root.bongo.accessError
              : String(root.ipcStatus.accessError || root.fallbackError || "")
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            horizontalAlignment: Text.AlignHCenter
          }

          Row {
            visible: root.serviceAvailable
              ? ((root.bongo.needsInputAccess && !root.bongo.accessInstalled)
                || root.bongo.accessInstalled)
              : root.ipcStatusReady && ((root.ipcStatus.needsInputAccess === true
                && root.ipcStatus.accessInstalled !== true)
                || root.ipcStatus.accessInstalled === true)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(8)

            Button {
              visible: root.serviceAvailable
                ? (root.bongo.needsInputAccess && !root.bongo.accessInstalled)
                : (root.ipcStatus.needsInputAccess === true
                  && root.ipcStatus.accessInstalled !== true)
              height: Style.spacing.controlHeight
              text: (root.serviceAvailable ? root.bongo.accessBusy
                : root.ipcStatus.accessBusy === true) ? "Allowing…" : "Allow Input"
              tooltipText: "Session-only raw keyboard access; trusts user-owned plugin files"
              enabled: root.serviceAvailable
                ? !root.bongo.accessBusy : root.ipcStatus.accessBusy !== true
              bordered: true
              focusable: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: {
                if (root.serviceAvailable) root.bongo.setInputAccess(true)
                else root.invokeIpc(["allowInput"], false)
              }
            }
            Button {
              visible: root.serviceAvailable
                ? root.bongo.accessInstalled : root.ipcStatus.accessInstalled === true
              height: Style.spacing.controlHeight
              text: (root.serviceAvailable ? root.bongo.accessBusy
                : root.ipcStatus.accessBusy === true) ? "Cancel Input" : "Revoke Input"
              tooltipText: "Close the session keyboard descriptors"
              enabled: true
              bordered: true
              focusable: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: {
                if (root.serviceAvailable) root.bongo.setInputAccess(false)
                else root.invokeIpc(["revokeInput"], false)
              }
            }
          }
        }
      }
    }
  }
}
