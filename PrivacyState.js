.pragma library

function toplevelClass(toplevel) {
  if (!toplevel || typeof toplevel !== "object") return ""
  var object = toplevel.lastIpcObject
  if (!object || typeof object !== "object") return ""
  return String(object.class || object.initialClass || "")
}

function normalizedAddress(address) {
  var value = String(address || "").trim().toLowerCase()
  if (/^[0-9a-f]+$/.test(value)) return "0x" + value
  return value
}

function toplevelAddress(toplevel) {
  if (!toplevel || typeof toplevel !== "object") return ""
  var object = toplevel.lastIpcObject
  if (!object || typeof object !== "object") return ""
  return normalizedAddress(object.address)
}

function matchingToplevels(toplevels, className) {
  var result = { windows: {}, count: 0 }
  if (!toplevels || (typeof toplevels !== "object"
      && typeof toplevels !== "function")) return result
  var length = Number(toplevels.length)
  if (!isFinite(length) || length < 0 || Math.floor(length) !== length) return result
  // Hyprland.toplevels.values is a QML list, not a JavaScript Array. Keep the
  // traversal bounded and fail closed if a malformed model exceeds the cap.
  if (length > 16384) {
    result.windows["model-overflow"] = true
    result.count = 1
    return result
  }
  var limit = length
  var target = String(className || "")
  for (var i = 0; i < limit; ++i) {
    var toplevel = toplevels[i]
    if (toplevelClass(toplevel) !== target) continue
    var address = toplevelAddress(toplevel) || "model-index-" + i
    if (result.windows[address]) continue
    result.windows[address] = true
    result.count += 1
  }
  return result
}

function matchingToplevelCount(toplevels, className) {
  return matchingToplevels(toplevels, className).count
}

function windowsAfter(windows, address, visible) {
  var key = normalizedAddress(address)
  var source = windows && typeof windows === "object" ? windows : {}
  var next = {}
  var count = 0
  for (var existing in source) {
    if (!source[existing] || existing === key) continue
    next[existing] = true
    count += 1
  }
  if (key !== "" && visible) {
    next[key] = true
    count += 1
  }
  return { windows: next, count: count }
}

function withoutConfirmedWindows(eventWindows, modelWindows) {
  var events = eventWindows && typeof eventWindows === "object" ? eventWindows : {}
  var model = modelWindows && typeof modelWindows === "object" ? modelWindows : {}
  var remaining = {}
  var count = 0
  var keys = Object.keys(events)
  for (var i = 0; i < keys.length; ++i) {
    var key = normalizedAddress(keys[i])
    if (key === "" || !events[keys[i]] || model[key]) continue
    remaining[key] = true
    count += 1
  }
  return { windows: remaining, count: count }
}

function eventParts(event, count) {
  try {
    if (event && event.parse) return event.parse(count)
  } catch (error) {
  }
  return String(event && event.data ? event.data : "").split(",")
}
