.pragma library

// The start menu's state that does not need Quickshell: its pins, the apps
// opened lately, the letters of the app list, and where the menu goes.

var RECENT_LIMIT = 12

function desktopId(value) {
  return String(value || "").trim().replace(/\.desktop$/, "")
}

// Each desktop id once, in the order given, without its .desktop suffix.
function uniqueIds(values) {
  var out = []
  var list = Array.isArray(values) ? values : []
  for (var i = 0; i < list.length; i++) {
    var id = desktopId(list[i])
    if (id && out.indexOf(id) === -1) out.push(id)
  }
  return out
}

// The saved pins, or null when there are none saved yet, so the menu can
// start from the dock's.
function parsePins(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    if (data && Array.isArray(data.pinned)) return uniqueIds(data.pinned)
  } catch (e) {
  }
  return null
}

function serializePins(pins) {
  return JSON.stringify({ pinned: uniqueIds(pins) }, null, 2) + "\n"
}

function pin(pins, id) {
  id = desktopId(id)
  var out = uniqueIds(pins)
  if (id && out.indexOf(id) === -1) out.push(id)
  return out
}

function unpin(pins, id) {
  id = desktopId(id)
  return uniqueIds(pins).filter(function(other) { return other !== id })
}

// Moves a pin to a slot, counted once it has left its own.
function movePin(pins, id, index) {
  id = desktopId(id)
  var out = unpin(pins, id)
  if (!id) return out
  var at = Math.max(0, Math.min(out.length, Math.round(index)))
  out.splice(at, 0, id)
  return out
}

function parseRecent(raw) {
  var out = []
  try {
    var data = JSON.parse(String(raw || ""))
    var list = Array.isArray(data) ? data : []
    var seen = {}
    for (var i = 0; i < list.length && out.length < RECENT_LIMIT; i++) {
      var id = desktopId(list[i] && list[i].id)
      var at = Number(list[i] && list[i].at)
      if (!id || seen[id] || !isFinite(at)) continue
      seen[id] = true
      out.push({ id: id, at: at })
    }
  } catch (e) {
  }
  return out
}

// The app opened now goes first; one opened before moves up rather than
// showing twice.
function addRecent(recent, id, at) {
  id = desktopId(id)
  var out = (Array.isArray(recent) ? recent : []).filter(function(item) { return item.id !== id })
  if (id) out.unshift({ id: id, at: at })
  return out.slice(0, RECENT_LIMIT)
}

function forgetRecent(recent, id) {
  id = desktopId(id)
  return (Array.isArray(recent) ? recent : []).filter(function(item) { return item.id !== id })
}

// How long ago an app was opened, the way the start menu says it.
function ago(at, now) {
  var seconds = Math.max(0, Math.floor((now - at) / 1000))
  if (seconds < 60) return "Just now"
  var minutes = Math.floor(seconds / 60)
  if (minutes < 60) return minutes + " min ago"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours === 1 ? "1 hour ago" : hours + " hours ago"
  var days = Math.floor(hours / 24)
  if (days === 1) return "Yesterday"
  if (days < 7) return days + " days ago"
  var weeks = Math.floor(days / 7)
  return weeks === 1 ? "Last week" : weeks + " weeks ago"
}

// The letter an app is filed under in the full list: its first letter, and
// "#" for anything that starts with a digit or a symbol.
function letterFor(name) {
  var first = String(name || "").trim().charAt(0).toUpperCase()
  return first && first.toLowerCase() !== first ? first : "#"
}

function letters(names) {
  var out = []
  for (var i = 0; i < names.length; i++) {
    var letter = letterFor(names[i])
    if (out.indexOf(letter) === -1) out.push(letter)
  }
  return out
}

// Every letter the jump grid offers, with "#" first as the list has it.
function alphabet() {
  var out = ["#"]
  for (var c = 65; c <= 90; c++) out.push(String.fromCharCode(c))
  return out
}

// Where the menu's card goes on its screen, kept inside the part of it the
// bar and other panels leave free (reserved: left, top, right, bottom). It
// hangs from the dock's apps button, inward of the dock, the way a start menu
// sits on its taskbar. Told only which edge the dock is on, it sits centered
// along that edge, clear of a dock dockReach deep. Told nothing, it sits at the
// bottom of the screen, in the middle.
function placement(payload, screen, width, height, gap, margin, dockReach) {
  var reserved = screen.reserved || [0, 0, 0, 0]
  var left = (reserved[0] || 0) + margin, top = (reserved[1] || 0) + margin
  var right = screen.width - (reserved[2] || 0) - margin, bottom = screen.height - (reserved[3] || 0) - margin
  var clampX = function(x) { return Math.round(Math.max(left, Math.min(right - width, x))) }
  var clampY = function(y) { return Math.round(Math.max(top, Math.min(bottom - height, y))) }
  var position = payload && payload.position
  var dock = payload && payload.dock
  var button = payload && payload.button
  if (!dock || !button) {
    var reach = position ? dockReach + gap - margin : 0
    var centerX = (left + right - width) / 2, centerY = (top + bottom - height) / 2
    if (position === "top") return { x: clampX(centerX), y: clampY(top + reach) }
    if (position === "left") return { x: clampX(left + reach), y: clampY(centerY) }
    if (position === "right") return { x: clampX(right - reach - width), y: clampY(centerY) }
    return { x: clampX(centerX), y: clampY(bottom - reach - height) }
  }
  switch (position) {
  case "top":
    return { x: clampX(button.x), y: clampY(dock.y + dock.height + gap) }
  case "left":
    return { x: clampX(dock.x + dock.width + gap), y: clampY(button.y) }
  case "right":
    return { x: clampX(dock.x - gap - width), y: clampY(button.y) }
  default:
    return { x: clampX(button.x), y: clampY(dock.y - gap - height) }
  }
}

// The selection after an arrow key in a grid of count cells, columns wide.
// Up from the first row or down from the last leaves the grid, which the
// caller hands on to the section before or after it.
function gridStep(index, count, columns, key) {
  if (count <= 0) return { index: -1, leave: 0 }
  if (key === "left") return { index: Math.max(0, index - 1), leave: 0 }
  if (key === "right") return { index: Math.min(count - 1, index + 1), leave: 0 }
  if (key === "up") return index - columns < 0 ? { index: index, leave: -1 } : { index: index - columns, leave: 0 }
  if (key === "down") {
    if (index + columns < count) return { index: index + columns, leave: 0 }
    // A short last row: down from above its end lands on its last cell.
    var lastRowStart = count - ((count - 1) % columns) - 1
    return index < lastRowStart ? { index: count - 1, leave: 0 } : { index: index, leave: 1 }
  }
  return { index: index, leave: 0 }
}
