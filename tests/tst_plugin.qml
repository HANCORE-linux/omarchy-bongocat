import QtQuick
import QtTest
import ".." as Bongo
import "../PrivacyState.js" as PrivacyState
import "../SettingsAdapter.js" as SettingsAdapter

TestCase {
  id: testCase
  name: "BongoCatPlugin"

  Bongo.PawAnimator {
    id: pawAnimator
  }

  QtObject {
    id: screensaverToplevel
    property var lastIpcObject: ({ class: "org.omarchy.screensaver" })
  }

  QtObject {
    id: otherToplevel
    property var lastIpcObject: ({ class: "org.example.other" })
  }

  property list<QtObject> qmlToplevels: [screensaverToplevel, otherToplevel]

  function init() {
    pawAnimator.releaseAll()
    pawAnimator.keypressDuration = 100
    pawAnimator.testAnimationDuration = 200
  }

  function cleanup() {
    pawAnimator.releaseAll()
  }

  function test_pawFrameSelectionMatchesUpstream() {
    compare(pawAnimator.holdDuration(1, 100), 10)
    compare(pawAnimator.holdDuration(6000, 100), 5000)
    compare(pawAnimator.frameFile, "bongo-cat-both-up.png")
    pawAnimator.leftDown = true
    compare(pawAnimator.frameFile, "bongo-cat-left-down.png")
    pawAnimator.rightDown = true
    compare(pawAnimator.frameFile, "bongo-cat-both-down.png")
    pawAnimator.leftDown = false
    compare(pawAnimator.frameFile, "bongo-cat-right-down.png")
  }

  function test_repeatedPawPressExtendsDeadline() {
    pawAnimator.keypressDuration = 80
    pawAnimator.pressLeft()
    wait(50)
    pawAnimator.pressLeft()
    wait(50)
    compare(pawAnimator.leftDown, true)
    tryVerify(function() { return !pawAnimator.leftDown }, 100)
  }

  function test_pawDeadlinesExpireIndependently() {
    pawAnimator.keypressDuration = 100
    pawAnimator.pressLeft()
    wait(40)
    pawAnimator.pressRight()
    compare(pawAnimator.frameFile, "bongo-cat-both-down.png")
    wait(70)
    compare(pawAnimator.leftDown, false)
    compare(pawAnimator.rightDown, true)
    tryVerify(function() { return !pawAnimator.rightDown }, 100)
  }

  function test_upstreamTestAnimationUsesOnePawForTwoHundredMs() {
    pawAnimator.testAnimation(0.1)
    compare(pawAnimator.leftDown, true)
    compare(pawAnimator.rightDown, false)
    wait(120)
    compare(pawAnimator.leftDown, true)
    tryVerify(function() { return !pawAnimator.leftDown }, 120)

    pawAnimator.testAnimation(0.9)
    compare(pawAnimator.leftDown, false)
    compare(pawAnimator.rightDown, true)
  }

  function test_scopedBarConfigLookup() {
    var entry = {
      id: "hancore.bongocat",
      active: false,
      positionX: 1475,
      shibumiModule: true
    }
    var config = { layout: { left: [], center: [], right: [entry] } }

    var found = SettingsAdapter.settingsFor(config, "hancore.bongocat")
    compare(found.active, false)
    compare(found.positionX, 1475)
    compare(found.shibumiModule, true)
  }

  function test_entryMergePreservesHostMetadataAndAppliesPatch() {
    var merged = SettingsAdapter.mergedEntry("hancore.bongocat",
      { id: "hancore.bongocat", catWidth: 280, shibumiModule: true },
      { catWidth: 320 }, { active: false })

    compare(merged.id, "hancore.bongocat")
    compare(merged.catWidth, 320)
    compare(merged.active, false)
    compare(merged.shibumiModule, true)
  }

  function test_persistenceMergeOverwritesOnlyCurrentlyDirtyKeys() {
    var merged = SettingsAdapter.mergeDirtySettings(
      { catWidth: 420, active: true, shibumiModule: true },
      { catWidth: 320, active: false, shibumiModule: true },
      { active: true })

    compare(merged.catWidth, 420)
    compare(merged.active, false)
    compare(merged.shibumiModule, true)
  }

  function test_journalUsesHostForHistoricalAndLocalForDirtyKeys() {
    var values = SettingsAdapter.journalValues(
      { catWidth: 320, active: false },
      { catWidth: 420, active: true },
      { catWidth: true, active: true },
      { active: true }, {})

    compare(values.catWidth, 420)
    compare(values.active, false)

    var inFlight = SettingsAdapter.journalValues(
      { catWidth: 320 }, { catWidth: 420 }, { catWidth: true }, {},
      { catWidth: 320 })
    compare(inFlight.catWidth, 320)

    // Service supplies a host snapshot canonicalized with its defaults, so a
    // removed historical key follows the default instead of stale local state.
    var removed = SettingsAdapter.journalValues(
      { catWidth: 320 }, { catWidth: 280 }, { catWidth: true }, {}, {})
    compare(removed.catWidth, 280)
  }

  function test_journalClearsOnlyAfterAnotherRuntimeLoadedMatchingSettings() {
    var patch = { catWidth: 320, active: false }
    var stored = { catWidth: 320, active: false }

    verify(!SettingsAdapter.journalIsDurable("instance-a", "instance-a",
      stored, patch))
    verify(!SettingsAdapter.journalIsDurable("instance-a", "instance-b",
      { catWidth: 280, active: false }, patch))
    verify(SettingsAdapter.journalIsDurable("instance-a", "instance-b",
      stored, patch))
  }

  function test_legacyFullConfigLookup() {
    var entry = { id: "hancore.bongocat", catWidth: 420 }
    var config = {
      bar: { layout: { left: [entry], center: [], right: [] } },
      plugins: []
    }

    compare(SettingsAdapter.settingsFor(config, "hancore.bongocat").catWidth, 420)
  }

  function test_lookupRejectsMissingOrMalformedLayout() {
    compare(SettingsAdapter.settingsFor(null, "hancore.bongocat"), null)
    compare(SettingsAdapter.settingsFor({}, "hancore.bongocat"), null)
    compare(SettingsAdapter.settingsFor({ layout: { right: {} } },
      "hancore.bongocat"), null)
    compare(SettingsAdapter.settingsFor({ layout: { right: [{ id: "other" }] } },
      "hancore.bongocat"), null)
  }

  function test_privacyToplevelCountHandlesInitialAndMalformedModels() {
    var models = [
      { lastIpcObject: { class: "org.omarchy.screensaver" } },
      { lastIpcObject: { initialClass: "org.omarchy.screensaver" } },
      { lastIpcObject: { class: "org.example.other" } },
      null
    ]
    compare(PrivacyState.matchingToplevelCount(models,
      "org.omarchy.screensaver"), 2)
    verify(!Array.isArray(qmlToplevels))
    compare(PrivacyState.matchingToplevelCount(qmlToplevels,
      "org.omarchy.screensaver"), 1)
    compare(PrivacyState.matchingToplevelCount({},
      "org.omarchy.screensaver"), 0)
    compare(PrivacyState.matchingToplevelCount({ length: 16385 },
      "org.omarchy.screensaver"), 1)
  }

  function test_privacyRawWindowTrackingIsIdempotent() {
    var first = PrivacyState.windowsAfter({}, "0xabc", true)
    compare(first.count, 1)
    var duplicate = PrivacyState.windowsAfter(first.windows, "0xabc", true)
    compare(duplicate.count, 1)
    var second = PrivacyState.windowsAfter(duplicate.windows, "0xdef", true)
    compare(second.count, 2)
    var closed = PrivacyState.windowsAfter(second.windows, "abc", false)
    compare(closed.count, 1)
    compare(closed.windows["0xdef"], true)

    var pending = PrivacyState.windowsAfter({}, "abc", true)
    var staleSnapshot = PrivacyState.withoutConfirmedWindows(
      pending.windows, {})
    compare(staleSnapshot.count, 1)
    var adopted = PrivacyState.withoutConfirmedWindows(
      staleSnapshot.windows, { "0xabc": true })
    compare(adopted.count, 0)

    compare(PrivacyState.eventParts({ data: "0x1,2,org.omarchy.screensaver,title" },
      4)[2], "org.omarchy.screensaver")
  }

}
