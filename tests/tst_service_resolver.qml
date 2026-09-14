import QtQuick
import QtTest
import ".." as Bongo

TestCase {
  id: testCase
  name: "BongoCatServiceResolver"

  Component {
    id: serviceComponent
    QtObject {
      property string keyboardName: "keyboard-a"
    }
  }

  Component {
    id: hostComponent
    QtObject {
      id: host
      property var _services: ({})
      property int lookups: 0
      property bool publishDuringLookup: false
      property var duringLookup: null
      function serviceFor(moduleName) {
        lookups += 1
        if (publishDuringLookup && !_services[moduleName]) {
          var next = ({})
          next[moduleName] = serviceComponent.createObject(host)
          _services = next
        }
        if (duringLookup) duringLookup()
        return _services[moduleName] || null
      }
    }
  }

  // Stock Omarchy injects this scoped surface. Its service map belongs to the
  // shell and is not observable through the facade's own properties/signals.
  Component {
    id: facadeComponent
    QtObject {
      property var barConfig: ({})
      property var _serviceLookup: null
      function serviceFor(moduleName) {
        return _serviceLookup ? _serviceLookup(moduleName) : null
      }
    }
  }

  Component {
    id: consumerComponent
    Item {
      id: consumer
      property QtObject bar: null
      property alias resolver: resolver
      readonly property QtObject bongo: resolver.service
      readonly property string selectedKeyboard: bongo
        ? bongo.keyboardName : "fallback-keyboard"
      Bongo.ServiceResolver {
        id: resolver
        host: consumer.bar ? consumer.bar.shell : null
        moduleName: "hancore.bongocat"
      }
    }
  }

  Component {
    id: barComponent
    QtObject { property QtObject shell: null }
  }

  function init() {
    failOnWarning(/.*/)
  }

  function makeHost() {
    return createTemporaryObject(hostComponent, testCase)
  }

  function makeService() {
    return createTemporaryObject(serviceComponent, testCase)
  }

  function attach(consumer, host) {
    consumer.bar = createTemporaryObject(barComponent, testCase, { shell: host })
  }

  function publish(host, service) {
    host._services = { "hancore.bongocat": service }
  }

  function test_injectionDefersLookupAndCachePublication() {
    var host = makeHost()
    host.publishDuringLookup = true
    var consumer = createTemporaryObject(consumerComponent, testCase)
    compare(host.lookups, 0)
    attach(consumer, host)
    // Injection must not enter serviceFor while host bindings are evaluating.
    compare(host.lookups, 0)
    compare(consumer.bongo, null)
    tryCompare(consumer, "selectedKeyboard", "keyboard-a")
    // Drain the notification emitted by publishing the cache inside lookup.
    wait(50)
    var calls = host.lookups
    consumer.bongo.keyboardName = "keyboard-b"
    compare(consumer.selectedKeyboard, "keyboard-b")
    wait(250)
    compare(host.lookups, calls)
  }

  function test_stockFacadeFindsServicePublishedLater() {
    var host = makeHost()
    var facade = createTemporaryObject(facadeComponent, testCase, {
      _serviceLookup: function(id) { return host.serviceFor(id) }
    })
    var consumer = createTemporaryObject(consumerComponent, testCase)
    attach(consumer, facade)
    tryVerify(function() { return host.lookups > 0 })
    compare(consumer.selectedKeyboard, "fallback-keyboard")
    var service = makeService()
    publish(host, service)
    tryCompare(consumer, "bongo", service)
    var calls = host.lookups
    wait(300)
    compare(host.lookups, calls)
  }

  function test_cacheReplacementKeepsKeyboardReactive() {
    var host = makeHost()
    var first = makeService()
    publish(host, first)
    var consumer = createTemporaryObject(consumerComponent, testCase)
    attach(consumer, host)
    tryCompare(consumer, "bongo", first)
    var second = makeService()
    second.keyboardName = "replacement-keyboard"
    publish(host, second)
    tryCompare(consumer, "bongo", second)
    compare(consumer.selectedKeyboard, "replacement-keyboard")
    second.keyboardName = "updated-keyboard"
    compare(consumer.selectedKeyboard, "updated-keyboard")
  }

  function test_scopedConfigReloadReplacesService() {
    var host = makeHost()
    var facade = createTemporaryObject(facadeComponent, testCase, {
      _serviceLookup: function(id) { return host.serviceFor(id) }
    })
    var first = makeService()
    publish(host, first)
    var consumer = createTemporaryObject(consumerComponent, testCase)
    attach(consumer, facade)
    tryCompare(consumer, "bongo", first)
    // Omarchy updates facade config before it publishes the new service map.
    facade.barConfig = { reloaded: true }
    var second = makeService()
    publish(host, second)
    tryCompare(consumer, "bongo", second)
  }

  function test_destroyedServiceReconnectsWithoutFacadeSignal() {
    var host = makeHost()
    var facade = createTemporaryObject(facadeComponent, testCase, {
      _serviceLookup: function(id) { return host.serviceFor(id) }
    })
    var first = makeService()
    publish(host, first)
    var consumer = createTemporaryObject(consumerComponent, testCase)
    attach(consumer, facade)
    tryCompare(consumer, "bongo", first)
    host._services = ({})
    first.destroy()
    tryCompare(consumer, "bongo", null)
    compare(consumer.selectedKeyboard, "fallback-keyboard")
    var second = makeService()
    publish(host, second)
    tryCompare(consumer, "bongo", second)
  }

  function test_shellReinjectionDiscardsQueuedOldLookup() {
    var oldHost = makeHost()
    var newHost = makeHost()
    var service = makeService()
    publish(newHost, service)
    var consumer = createTemporaryObject(consumerComponent, testCase)
    attach(consumer, oldHost)
    consumer.bar.shell = newHost
    tryCompare(consumer, "bongo", service)
    compare(oldHost.lookups, 0)
  }

  function test_hostChangedInsideLookupRejectsStaleResult() {
    var oldHost = makeHost()
    publish(oldHost, makeService())
    var newHost = makeHost()
    var service = makeService()
    publish(newHost, service)
    var consumer = createTemporaryObject(consumerComponent, testCase)
    attach(consumer, oldHost)
    oldHost.duringLookup = function() { consumer.bar.shell = newHost }
    tryCompare(consumer, "bongo", service)
    compare(oldHost.lookups, 1)
  }

  function test_fallbackWithoutServiceApi() {
    var consumer = createTemporaryObject(consumerComponent, testCase)
    attach(consumer, makeService())
    wait(200)
    compare(consumer.bongo, null)
    compare(consumer.selectedKeyboard, "fallback-keyboard")
  }

  function test_hostDestructionClearsService() {
    var host = makeHost()
    publish(host, makeService())
    var consumer = createTemporaryObject(consumerComponent, testCase)
    attach(consumer, host)
    tryVerify(function() { return consumer.bongo !== null })
    host.destroy()
    tryCompare(consumer.resolver, "host", null)
    tryCompare(consumer, "bongo", null)
    wait(200)
  }

  function test_destroyWithPendingSyncStopsLookups() {
    var host = makeHost()
    var consumer = createTemporaryObject(consumerComponent, testCase)
    attach(consumer, host)
    tryVerify(function() { return host.lookups > 0 })
    consumer.resolver.scheduleSync()
    consumer.destroy()
    wait(50)
    var calls = host.lookups
    host._services = ({})
    wait(300)
    compare(host.lookups, calls)
  }
}
