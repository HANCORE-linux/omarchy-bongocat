import QtQuick
import QtQuick.Effects

Item {
  id: root

  property url source
  property bool colorized: false
  property color tint: "white"
  property int fillMode: Image.Stretch
  property bool smooth: true
  property bool mipmap: true

  Image {
    id: original
    anchors.fill: parent
    visible: !root.colorized
    source: root.source
    fillMode: root.fillMode
    smooth: root.smooth
    mipmap: root.mipmap
    cache: true
  }

  MultiEffect {
    anchors.fill: parent
    visible: root.colorized
    source: original
    colorization: 1
    colorizationColor: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 1)
    opacity: root.tint.a
  }
}
