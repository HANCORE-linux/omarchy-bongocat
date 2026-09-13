import QtQuick

// Four-state paw animator matching wayland-bongocat's deadline semantics.
Item {
  id: root

  visible: false
  width: 0
  height: 0

  property int keypressDuration: 100
  property int testAnimationDuration: 200
  property bool leftDown: false
  property bool rightDown: false
  readonly property string frameFile: leftDown && rightDown
    ? "bongo-cat-both-down.png"
    : leftDown ? "bongo-cat-left-down.png"
    : rightDown ? "bongo-cat-right-down.png"
    : "bongo-cat-both-up.png"

  function holdDuration(requested, fallback) {
    var value = requested === undefined ? fallback : Number(requested)
    if (!isFinite(value)) value = fallback
    return Math.max(10, Math.min(5000, Math.round(value)))
  }

  function pressLeft(duration) {
    leftDown = true
    leftRelease.interval = holdDuration(duration, keypressDuration)
    leftRelease.restart()
  }

  function pressRight(duration) {
    rightDown = true
    rightRelease.interval = holdDuration(duration, keypressDuration)
    rightRelease.restart()
  }

  function testAnimation(randomValue) {
    var choice = randomValue === undefined ? Math.random() : Number(randomValue)
    if (!isFinite(choice)) choice = 0
    if (choice < 0.5) pressLeft(testAnimationDuration)
    else pressRight(testAnimationDuration)
  }

  function releaseAll() {
    leftRelease.stop()
    rightRelease.stop()
    leftDown = false
    rightDown = false
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
}
