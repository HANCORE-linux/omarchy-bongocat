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

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (opened && bongo) {
      bongo.checkInputAccess()
      bongo.scanDevices()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }
  }

  function toggleActive() {
    if (bongo) bongo.setCatActive(!bongo.catActive)
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    fixedWidth: 36
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

    CatImage {
      anchors.centerIn: parent
      width: 32
      height: 16
      source: root.bongo ? root.bongo.idleSource
        : Qt.resolvedUrl("assets/bongo-cat-both-up.png")
      colorized: root.bongo ? root.bongo.catColorized : false
      tint: root.bongo ? root.bongo.catTint : "white"
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

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: !activeFocus || keyboardPicker.popupOpen || monitorPicker.popupOpen
      onCloseRequested: root.close()
      onTabRequested: function(direction) {
        if (direction < 0) testButton.forceActiveFocus()
        else enableButton.forceActiveFocus()
      }
      onMoveRequested: function(dx, dy) {
        if (!root.bongo || root.bongo.positionLocked) return
        root.bongo.nudgePosition(dx * 10, dy * 10)
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
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                width: parent.width
              }
            }

            Row {
              id: headerActions
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(5)

              Button {
                id: enableButton
                width: 36
                iconText: "󰐥"
                tooltipText: root.bongo && root.bongo.catActive ? "Disable" : "Enable"
                selected: root.bongo && root.bongo.catActive
                bordered: true
                focusable: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: root.toggleActive()
              }
              Button {
                id: lockButton
                width: 36
                iconText: root.bongo && root.bongo.positionLocked ? "󰌾" : "󰌿"
                tooltipText: root.bongo && root.bongo.positionLocked ? "Unlock & Drag" : "Lock Position"
                selected: root.bongo && root.bongo.positionLocked
                enabled: root.bongo && root.bongo.catActive
                bordered: true
                focusable: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: {
                  if (!root.bongo) return
                  if (root.bongo.positionLocked) {
                    root.bongo.setPositionLocked(false)
                    root.close()
                  } else {
                    root.bongo.setPositionLocked(true)
                  }
                }
              }
              Button {
                id: testButton
                width: 36
                iconText: "󰜺"
                tooltipText: "Test Animation (T)"
                enabled: root.bongo && root.bongo.catActive
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
          PanelSectionHeader {
            width: parent.width
            text: "APPEARANCE"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            width: parent.width
            spacing: Style.space(7)

            Text {
              width: 38
              anchors.verticalCenter: parent.verticalCenter
              text: "Size"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Button {
              id: sizeDownButton
              width: 36
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
              minimum: 120
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
              width: 36
              text: "+"
              tooltipText: "20 px larger"
              bordered: true
              focusable: true
              foreground: root.foreground
              onClicked: if (root.bongo) root.bongo.resizeCat(20)
            }
          }

          ButtonGroup {
            anchors.horizontalCenter: parent.horizontalCenter
            options: [
              { value: "180", label: "Small" },
              { value: "280", label: "Medium" },
              { value: "420", label: "Large" }
            ]
            value: root.bongo ? String(root.bongo.catWidth) : "280"
            foreground: root.foreground
            background: root.background
            accent: root.accent
            fontFamily: root.fontFamily
            onChanged: function(next) {
              if (root.bongo) root.bongo.setCatWidth(parseInt(next, 10))
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {
              width: 38
              anchors.verticalCenter: parent.verticalCenter
              text: "Color"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            ButtonGroup {
              options: [
                { value: "default", label: "Default" },
                { value: "theme", label: "Theme" },
                { value: "hex", label: "Hex" }
              ]
              value: root.bongo ? root.bongo.colorMode : "default"
              foreground: root.foreground
              background: root.background
              accent: root.accent
              fontFamily: root.fontFamily
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
          PanelSectionHeader {
            width: parent.width
            text: "POSITION"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            NumberField {
              width: (parent.width - parent.spacing) / 2
              enabled: root.bongo && !root.bongo.positionLocked
              label: "X"
              value: root.positionXValue
              from: 0
              to: root.positionXMaximum
              stepSize: 10
              fieldWidth: width
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onModified: function(next) {
                if (root.bongo) root.bongo.setPosition(next, root.positionYValue)
              }
            }
            NumberField {
              width: (parent.width - parent.spacing) / 2
              enabled: root.bongo && !root.bongo.positionLocked
              label: "Y"
              value: root.positionYValue
              from: 0
              to: root.positionYMaximum
              stepSize: 10
              fieldWidth: width
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onModified: function(next) {
                if (root.bongo) root.bongo.setPosition(root.positionXValue, next)
              }
            }
          }

          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(5)

            Button {
              iconText: "󰁍"
              tooltipText: "10 px left"
              enabled: root.bongo && !root.bongo.positionLocked
              bordered: true
              focusable: true
              foreground: root.foreground
              onClicked: root.bongo.nudgePosition(-10, 0)
            }
            Button {
              iconText: "󰁅"
              tooltipText: "10 px up"
              enabled: root.bongo && !root.bongo.positionLocked
              bordered: true
              focusable: true
              foreground: root.foreground
              onClicked: root.bongo.nudgePosition(0, -10)
            }
            Button {
              iconText: "󰁝"
              tooltipText: "10 px down"
              enabled: root.bongo && !root.bongo.positionLocked
              bordered: true
              focusable: true
              foreground: root.foreground
              onClicked: root.bongo.nudgePosition(0, 10)
            }
            Button {
              iconText: "󰁔"
              tooltipText: "10 px right"
              enabled: root.bongo && !root.bongo.positionLocked
              bordered: true
              focusable: true
              foreground: root.foreground
              onClicked: root.bongo.nudgePosition(10, 0)
            }
            Button {
              text: "Reset"
              enabled: root.bongo && !root.bongo.positionLocked
              bordered: true
              focusable: true
              foreground: root.foreground
              onClicked: root.bongo.resetPosition()
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            NumberField {
              width: (parent.width - parent.spacing) / 2
              label: "Paw (ms)"
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
            Dropdown {
              id: monitorPicker
              width: (parent.width - parent.spacing) / 2
              label: "Monitor"
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

          PanelSeparator { width: parent.width; foreground: root.foreground }
          PanelSectionHeader {
            width: parent.width
            text: "INPUT"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Dropdown {
            id: keyboardPicker
            width: parent.width
            label: "Keyboard"
            value: root.bongo ? root.bongo.keyboardName : ""
            options: root.bongo ? root.bongo.keyboardOptions() : []
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onChanged: function(next) {
              if (root.bongo) root.bongo.setKeyboardName(next)
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
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(8)

            Button {
              visible: root.bongo && root.bongo.needsInputAccess
                && !root.bongo.accessInstalled
              text: root.bongo && root.bongo.accessBusy ? "Allowing…" : "Allow Input"
              enabled: root.bongo && !root.bongo.accessBusy
              bordered: true
              focusable: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.bongo.setInputAccess(true)
            }
            Button {
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
            Button {
              visible: root.bongo && root.bongo.accessInstalled
              text: "Revoke Input"
              enabled: root.bongo && !root.bongo.accessBusy
              focusable: true
              foreground: root.dim
              fontFamily: root.fontFamily
              onClicked: root.bongo.setInputAccess(false)
            }
          }
        }
      }
    }
  }
}
