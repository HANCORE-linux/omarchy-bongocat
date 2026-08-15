pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

Panel {
  id: root

  moduleName: "hancore.bongocat"
  ipcTarget: ""
  manageIpc: false

  readonly property var bongo: bar && bar.shell
    && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color background: bar ? bar.background : Color.background
  readonly property color accent: bar ? bar.urgent : Color.accent
  readonly property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.58)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var activeScreen: bongo ? bongo.targetScreen() : null
  readonly property int positionXValue: bongo && activeScreen
    ? Math.round(bongo.resolvedX(activeScreen)) : 0
  readonly property int positionYValue: bongo && activeScreen
    ? Math.round(bongo.resolvedY(activeScreen)) : 0
  readonly property int positionXMaximum: bongo && activeScreen
    ? Math.max(0, activeScreen.width - bongo.catWidth) : 8000
  readonly property int positionYMaximum: bongo && activeScreen
    ? Math.max(0, activeScreen.height - bongo.catHeight) : 8000
  readonly property bool presentationSuppressed: bongo
    ? bongo.presentationSuppressed : false
  property var panelSessionService: null

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (opened) {
      beginPanelSession()
      if (bongo) {
        bongo.checkInputAccess()
        bongo.scanDevices()
      }
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else {
      finishPanelSession()
    }
  }

  onBongoChanged: if (opened) beginPanelSession()
  onPresentationSuppressedChanged: if (presentationSuppressed) close()
  Component.onDestruction: abandonPanelSession()

  function beginPanelSession() {
    if (panelSessionService || !bongo
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
    if (bongo) bongo.setCatActive(!bongo.catActive)
  }

  function moveFromPanel(dx, dy) {
    if (!bongo) return
    bongo.setPosition(positionXValue + dx, positionYValue + dy)
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
    active: root.bongo && root.bongo.catActive
    tooltipText: !root.bongo ? "Loading Bongo Cat…"
      : root.bongo.catActive ? "Bongo Cat · " + root.bongo.inputStatusText()
      : "Bongo Cat is off"

    onPressed: function(buttonCode) {
      if (!root.bongo) return
      if (buttonCode === Qt.RightButton) root.toggleActive()
      else if (buttonCode === Qt.MiddleButton) root.bongo.testAnimation()
      else root.toggle()
    }

    OpticalGlyph {
      anchors.centerIn: parent
      width: Style.space(24)
      height: Style.space(24)
      text: "󰄛"
      fontFamily: root.fontFamily
      fontSize: Style.font.iconLarge
      color: root.bongo && root.bongo.catColorized
        ? root.bongo.catTint : root.foreground
      opacity: root.bongo && root.bongo.catActive ? 1 : 0.38
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
        if (!root.bongo) return
        if (text === "t" || text === "T") root.bongo.testAnimation()
        else if (text === "p" || text === "P")
          root.bongo.setPositionLocked(!root.bongo.positionLocked)
        else if (text === "r" || text === "R") {
          root.bongo.scanDevices()
          root.bongo.updateInputProcess()
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
              source: root.bongo ? root.bongo.idleSource
                : Qt.resolvedUrl("assets/bongo-cat-both-up.png")
              colorized: root.bongo ? root.bongo.catColorized : false
              tint: root.bongo ? root.bongo.catTint : "white"
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
                text: root.bongo ? root.bongo.inputStatusText() : "Loading…"
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
                tooltipText: root.bongo && root.bongo.catActive ? "Disable" : "Enable"
                selected: root.bongo && root.bongo.catActive
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
                glyph: root.bongo && root.bongo.positionLocked ? "\uf023" : "\uf09c"
                iconSize: Math.max(1, Style.font.iconLarge - 1)
                tooltipText: root.bongo && root.bongo.positionLocked
                  ? "Locked · Click to unlock" : "Unlocked · Click to lock"
                selected: root.bongo && root.bongo.positionLocked
                glyphColor: selected
                  ? Style.selectedStateColor(foreground, accent) : root.accent
                enabled: root.bongo && root.bongo.catActive
                opacity: enabled ? 1 : 0.38
                bordered: true
                focusable: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: {
                  if (root.bongo)
                    root.bongo.setPositionLocked(!root.bongo.positionLocked)
                }
              }
              PanelGlyphButton {
                id: testButton
                width: Style.spacing.controlHeight
                height: Style.spacing.controlHeight
                glyph: "\uf0d0"
                iconSize: Math.max(1, Style.font.iconLarge - 1)
                tooltipText: "Test Animation (T)"
                enabled: root.bongo && root.bongo.catActive
                opacity: enabled ? 1 : 0.38
                bordered: true
                focusable: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.bongo.testAnimation()
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
              onClicked: if (root.bongo) root.bongo.resizeCat(-20)
            }
            PanelSlider {
              width: Math.max(80, parent.width - 38 - sizeDownButton.width
                - sizeUpButton.width - sizeValue.width - parent.spacing * 4)
              anchors.verticalCenter: parent.verticalCenter
              bar: root.bar
              value: root.bongo ? root.bongo.catWidth : 280
              minimum: root.bongo ? root.bongo.minimumCatWidth : 60
              maximum: 640
              step: 20
              integer: true
              onMoved: function(next) {
                if (root.bongo) root.bongo.previewCatWidth(next)
              }
              onReleased: function(next) {
                if (root.bongo) root.bongo.setCatWidth(next)
              }
            }
            Text {
              id: sizeValue
              width: 52
              anchors.verticalCenter: parent.verticalCenter
              text: (root.bongo ? root.bongo.catWidth : 280) + " px"
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
              onClicked: if (root.bongo) root.bongo.resizeCat(20)
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
            value: root.bongo ? String(root.bongo.catWidth) : "280"
            onChanged: function(next) {
              if (root.bongo) root.bongo.setCatWidth(parseInt(next, 10))
            }
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
              value: root.bongo ? root.bongo.colorMode : "default"
              onChanged: function(next) {
                if (root.bongo) root.bongo.setColorMode(next)
              }
            }
          }

          Row {
            visible: root.bongo && root.bongo.colorMode === "hex"
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(8)

            Rectangle {
              width: 26
              height: 26
              radius: Style.cornerRadius
              color: root.bongo ? root.bongo.customColor : "#f0abab"
              border.width: 1
              border.color: root.foreground
            }
            TextField {
              id: hexField
              width: 130
              text: root.bongo ? root.bongo.customColor : "#f0abab"
              placeholderText: "#RRGGBB"
              foreground: root.foreground
              accent: root.accent
              font.family: root.fontFamily
              validator: RegularExpressionValidator {
                regularExpression: /^#[0-9a-fA-F]{6}$/
              }
              onTextEdited: if (root.bongo && acceptableInput)
                root.bongo.setCustomColor(text)
              onEditingFinished: if (root.bongo && acceptableInput)
                root.bongo.setCustomColor(text)
              onActiveFocusChanged: {
                if (!activeFocus && !acceptableInput && root.bongo)
                  text = root.bongo.customColor
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
              enabled: root.bongo && root.bongo.catActive
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
                if (root.bongo) root.bongo.setPosition(next, root.positionYValue)
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
              enabled: root.bongo && root.bongo.catActive
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
                if (root.bongo) root.bongo.setPosition(root.positionXValue, next)
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
              enabled: root.bongo && root.bongo.catActive
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
              enabled: root.bongo && root.bongo.catActive
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
              enabled: root.bongo && root.bongo.catActive
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
              enabled: root.bongo && root.bongo.catActive
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
              enabled: root.bongo && root.bongo.catActive
              opacity: enabled ? 1 : 0.38
              bordered: true
              focusable: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.bongo.resetPosition()
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
                value: root.bongo ? root.bongo.keypressDuration : 105
                from: 40
                to: 500
                stepSize: 5
                fieldWidth: width
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onModified: function(next) {
                  if (root.bongo) root.bongo.setKeypressDuration(next)
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
                value: root.bongo ? root.bongo.monitorName : ""
                options: root.bongo ? root.bongo.monitorOptions() : []
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onChanged: function(next) {
                  if (root.bongo) root.bongo.setMonitorName(next)
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
                active: root.bongo && root.bongo.workspaceId === 0
                bordered: true
                focusable: true
                foreground: root.foreground
                background: root.background
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: if (root.bongo) root.bongo.setWorkspaceId(0)
              }

              Repeater {
                model: 10

                Button {
                  required property int index
                  readonly property int workspaceNumber: index + 1

                  width: workspaceChoices.workspaceWidth
                  height: workspaceChoices.height
                  text: String(workspaceNumber)
                  active: root.bongo
                    && root.bongo.workspaceId === workspaceNumber
                  bordered: true
                  focusable: true
                  foreground: root.foreground
                  background: root.background
                  accent: root.accent
                  fontFamily: root.fontFamily
                  onClicked: if (root.bongo)
                    root.bongo.setWorkspaceId(workspaceNumber)
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
              text: root.bongo && root.bongo.deviceScanRunning ? "Scanning…" : "Rescan"
              enabled: root.bongo && !root.bongo.deviceScanRunning
              bordered: true
              focusable: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: {
                root.bongo.scanDevices()
                root.bongo.updateInputProcess()
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
              value: root.bongo ? root.bongo.keyboardName : ""
              options: root.bongo ? root.bongo.keyboardOptions() : []
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onChanged: function(next) {
                if (root.bongo) root.bongo.setKeyboardName(next)
              }
            }
          }

          Text {
            visible: root.bongo && root.bongo.accessError !== ""
            width: parent.width
            text: root.bongo ? root.bongo.accessError : ""
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            horizontalAlignment: Text.AlignHCenter
          }

          Row {
            visible: root.bongo && ((root.bongo.needsInputAccess
              && !root.bongo.accessInstalled) || root.bongo.accessInstalled)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(8)

            Button {
              visible: root.bongo && root.bongo.needsInputAccess
                && !root.bongo.accessInstalled
              height: Style.spacing.controlHeight
              text: root.bongo && root.bongo.accessBusy ? "Allowing…" : "Allow Input"
              tooltipText: "Session-only raw keyboard access; trusts user-owned plugin files"
              enabled: root.bongo && !root.bongo.accessBusy
              bordered: true
              focusable: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.bongo.setInputAccess(true)
            }
            Button {
              visible: root.bongo && root.bongo.accessInstalled
              height: Style.spacing.controlHeight
              text: root.bongo && root.bongo.accessBusy ? "Cancel Input" : "Revoke Input"
              tooltipText: "Close the session keyboard descriptors"
              enabled: root.bongo
              bordered: true
              focusable: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.bongo.setInputAccess(false)
            }
          }
        }
      }
    }
  }
}
