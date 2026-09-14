import QtQuick

// Keep serviceFor() out of property bindings: publishing the shell's service
// cache can otherwise re-enter a binding that is still reading the service.
Item {
  id: root

  visible: false
  property QtObject host: null
  property string moduleName: ""
  // A typed QObject reference is cleared (and notifies) when the service dies.
  property QtObject service: null
  property bool disposing: false

  function scheduleSync() {
    if (disposing) return
    retryTimer.stop()
    retryTimer.interval = 100
    Qt.callLater(syncService)
  }

  function syncService() {
    if (disposing) return
    var currentHost = host
    var currentModule = moduleName
    var next = currentHost && typeof currentHost.serviceFor === "function"
      ? currentHost.serviceFor(currentModule) : null
    // A lookup may itself cause host/config changes. Never adopt its result
    // after the bar facade has been replaced or this resolver has been retired.
    if (disposing || host !== currentHost || moduleName !== currentModule) return
    service = next
    if (service || !currentHost || typeof currentHost.serviceFor !== "function") {
      retryTimer.stop()
    } else {
      // Scoped stock-bar facades do not expose a service-cache notification.
      // Retry delayed publication with backoff; stop as soon as it resolves.
      retryTimer.start()
    }
  }

  onHostChanged: {
    service = null
    scheduleSync()
  }
  onModuleNameChanged: {
    service = null
    scheduleSync()
  }
  onServiceChanged: if (!service) scheduleSync()
  Component.onCompleted: scheduleSync()
  Component.onDestruction: {
    disposing = true
    retryTimer.stop()
  }

  Connections {
    target: root.host
    ignoreUnknownSignals: true
    function onBarConfigChanged() {
      var resolver = root
      if (resolver) resolver.scheduleSync()
    }
    function onShellConfigChanged() {
      var resolver = root
      if (resolver) resolver.scheduleSync()
    }
    function on_ServicesChanged() {
      var resolver = root
      if (resolver) resolver.scheduleSync()
    }
  }

  Timer {
    id: retryTimer
    interval: 100
    repeat: false
    onTriggered: {
      interval = Math.min(interval * 2, 2000)
      root.syncService()
    }
  }
}
