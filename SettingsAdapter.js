.pragma library

function barConfig(config) {
  if (!config || typeof config !== "object") return null
  if (config.bar && typeof config.bar === "object") return config.bar
  return config
}

function mergedEntry(moduleName, settings, localPatch, patch) {
  var merged = { id: String(moduleName || "") }
  var sources = [settings, localPatch, patch]
  for (var i = 0; i < sources.length; ++i) {
    var source = sources[i]
    if (!source || typeof source !== "object") continue
    for (var key in source) {
      if (key !== "id" && key !== "__proto__" && key !== "constructor"
          && key !== "prototype") merged[key] = source[key]
    }
  }
  return merged
}

function journalValues(local, host, journalKeys, dirtyKeys, inFlightPatch) {
  var values = {}
  if (!journalKeys || typeof journalKeys !== "object") return values
  var localSettings = local && typeof local === "object" ? local : {}
  var hostSettings = host && typeof host === "object" ? host : null
  var dirty = dirtyKeys && typeof dirtyKeys === "object" ? dirtyKeys : {}
  var inFlight = inFlightPatch && typeof inFlightPatch === "object"
    ? inFlightPatch : {}
  var keys = Object.keys(journalKeys)
  for (var i = 0; i < keys.length; ++i) {
    var key = keys[i]
    if (!journalKeys[key] || key === "__proto__" || key === "constructor"
        || key === "prototype") continue
    var locallyOwned = dirty[key] === true
      || Object.prototype.hasOwnProperty.call(inFlight, key)
    values[key] = !locallyOwned && hostSettings
        && Object.prototype.hasOwnProperty.call(hostSettings, key)
      ? hostSettings[key] : localSettings[key]
  }
  return values
}

function mergeDirtySettings(latest, local, dirtyKeys) {
  var merged = {}
  var sources = [latest]
  for (var i = 0; i < sources.length; ++i) {
    var source = sources[i]
    if (!source || typeof source !== "object") continue
    for (var key in source) {
      if (key !== "__proto__" && key !== "constructor" && key !== "prototype")
        merged[key] = source[key]
    }
  }
  if (!local || typeof local !== "object"
      || !dirtyKeys || typeof dirtyKeys !== "object") return merged
  for (var dirtyKey in dirtyKeys) {
    if (dirtyKeys[dirtyKey] && dirtyKey !== "__proto__"
        && dirtyKey !== "constructor" && dirtyKey !== "prototype")
      merged[dirtyKey] = local[dirtyKey]
  }
  return merged
}

function patchMatches(settings, patch) {
  if (!settings || typeof settings !== "object"
      || !patch || typeof patch !== "object" || Array.isArray(patch)) return false
  var keys = Object.keys(patch)
  if (keys.length === 0) return false
  for (var i = 0; i < keys.length; ++i) {
    var key = keys[i]
    if (JSON.stringify(settings[key]) !== JSON.stringify(patch[key])) return false
  }
  return true
}

function journalIsDurable(journalInstanceId, currentInstanceId, settings, patch) {
  var writer = String(journalInstanceId || "")
  var current = String(currentInstanceId || "")
  return writer !== "" && current !== "" && writer !== current
    && patchMatches(settings, patch)
}

function settingsFor(config, moduleName) {
  var bar = barConfig(config)
  if (!bar || !bar.layout) return null

  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; ++s) {
    var entries = bar.layout[sections[s]]
    if (!Array.isArray(entries)) continue
    for (var i = 0; i < entries.length; ++i) {
      var entry = entries[i]
      var id = entry && typeof entry === "object" ? entry.id : entry
      if (String(id || "") !== String(moduleName || "")) continue
      return entry && typeof entry === "object" ? entry : { id: String(id) }
    }
  }

  // Older trusted hosts exposed the complete shell config. Keep that shape as
  // a compatibility fallback while Omarchy 4.0.3 uses the scoped barConfig.
  if (config !== bar && Array.isArray(config.plugins)) {
    for (var p = 0; p < config.plugins.length; ++p) {
      var plugin = config.plugins[p]
      if (plugin && String(plugin.id || "") === String(moduleName || ""))
        return plugin
    }
  }
  return null
}
