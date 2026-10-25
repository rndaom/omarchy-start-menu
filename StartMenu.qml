import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "StartMenuModel.js" as Model

// A start menu in the Windows manner, in the Omarchy theme. It hangs from the
// dock's apps button once `omarchy dock launcher rndaom.start-menu` hands the
// button over, and a tap of Super opens it on a floating workspace. Search sits
// on top, pinned apps and the ones opened lately below it, every app one click
// away, and the session's power actions at the foot.
//
// Like the other launchers it opens and closes at once, with no motion: it is
// summoned many times a day by one key.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property string omarchyPath: ""

  readonly property var appLibrary: shell ? shell.appLibrary : null
  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "rndaom.start-menu"

  property bool opened: false
  // Where the dock and its apps button are, from the dock's launcher payload.
  property var payload: ({})
  // "home" shows the pinned and recent apps, "all" every app by letter. Typing
  // searches from either.
  property string view: "home"
  property string filterText: ""
  readonly property bool searching: filterText !== ""

  // The keyboard's place: a section ("pinned", "recent", "all", "results") and
  // an index in it. The pointer moves it too, so only one thing is lit.
  property string section: "pinned"
  property int index: 0

  property var pins: []
  // Until the user changes them, the pins follow the dock's.
  property bool pinsSaved: false
  property var recent: []
  property var dockPins: []
  property var results: []
  property bool appsStale: true
  property real now: Date.now()

  property var menuEntry: null
  property point menuPoint
  property var uninstallEntry: null
  property bool powerOpen: false
  property bool lettersOpen: false
  property bool profileOpen: false
  property bool canSleep: true
  // Only for the letter on the profile disc when there is no picture.
  property string userName: Quickshell.env("USER") || ""
  // The usual place for a Linux user's picture, which login screens read too.
  readonly property string facePath: Quickshell.env("HOME") + "/.face"
  property bool hasFace: false
  property int faceStamp: 0
  readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")).replace(/\/$/, "")

  // A pinned app being dragged to another slot, where the pointer is, and the
  // slot it would take.
  property string dragId: ""
  property point dragPoint
  property int dropIndex: -1

  readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omarchy"
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/start-menu"

  function tr(key, fallback) {
    return Commons.I18n.t(key, fallback)
  }

  function s(value) {
    return Math.round(value * Style.fontScale)
  }

  // ------------------------------------------------------------- Sizes

  readonly property int padding: s(24)
  readonly property int sectionGap: s(18)
  readonly property int headerHeight: s(28)
  readonly property int searchHeight: s(38)
  readonly property int footerHeight: s(60)
  readonly property int pinnedColumns: 6
  readonly property int pinnedRows: 3
  readonly property int tileIcon: s(32)
  readonly property int tileHeight: s(10) + tileIcon + s(8) + Math.ceil(labelMetrics.height) + s(10)
  readonly property int recentColumns: 2
  readonly property int recentRows: 3
  readonly property int rowIcon: s(28)
  readonly property int rowHeight: s(48)
  readonly property int listRowHeight: s(40)
  readonly property int screenMargin: s(12)
  readonly property int dockGap: s(6)

  readonly property int idealWidth: s(640)
  readonly property int idealHeight: padding * 2 + searchHeight + sectionGap
    + headerHeight + pinnedRows * tileHeight + sectionGap
    + headerHeight + recentRows * rowHeight + footerHeight
  // The edges the bar and other panels keep for themselves, which Hyprland
  // lists as left, top, right, bottom.
  readonly property var reserved: {
    var monitor = panel.targetMonitor
    var ipc = monitor ? monitor.lastIpcObject : null
    return ipc && ipc.reserved ? ipc.reserved : [0, 0, 0, 0]
  }
  // How far the dock reaches in from its edge, for when only its edge is known.
  readonly property int dockReach: Style.spacing.xs + s(36) + Style.spacing.md * 2
  readonly property int cardWidth: Math.min(idealWidth, panel.width - (reserved[0] || 0) - (reserved[2] || 0) - screenMargin * 2)
  readonly property int cardHeight: Math.min(idealHeight, panel.height - (reserved[1] || 0) - (reserved[3] || 0) - screenMargin * 2)
  readonly property int innerWidth: cardWidth - padding * 2
  readonly property real tileWidth: innerWidth / pinnedColumns
  readonly property var cardPosition: Model.placement(root.payload, { width: panel.width, height: panel.height, reserved: root.reserved },
    cardWidth, cardHeight, dockGap, screenMargin, dockReach)

  FontMetrics {
    id: labelMetrics
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.body
  }

  // ------------------------------------------------------------- Apps

  function entry(id) {
    var found = DesktopEntries.byId(id)
    return found && !found.noDisplay ? found : null
  }

  function nameOf(entry) {
    return entry && root.appLibrary ? root.appLibrary.entryName(entry) : ""
  }

  function iconOf(entry) {
    return entry && root.appLibrary ? root.appLibrary.iconSource(entry.icon) : ""
  }

  // Pinned apps that are installed, in pin order.
  readonly property var pinnedEntries: {
    var appsRevision = DesktopEntries.applications.values.length
    var out = []
    for (var i = 0; i < root.pins.length; i++) {
      var found = root.entry(root.pins[i])
      if (found) out.push(found)
    }
    return out
  }

  readonly property var recentEntries: {
    var appsRevision = DesktopEntries.applications.values.length
    var out = []
    for (var i = 0; i < root.recent.length && out.length < root.recentColumns * root.recentRows; i++) {
      var found = root.entry(root.recent[i].id)
      if (found) out.push({ entry: found, at: root.recent[i].at })
    }
    return out
  }

  ListModel { id: allApps }

  function rebuildApps() {
    root.appsStale = false
    var rows = root.appLibrary ? root.appLibrary.sortedEntries("") : []
    var sorted = rows.map(function(row) { return row.entry })
    sorted.sort(function(a, b) {
      var left = root.nameOf(a).toLowerCase(), right = root.nameOf(b).toLowerCase()
      var leftLetter = Model.letterFor(left), rightLetter = Model.letterFor(right)
      if ((leftLetter === "#") !== (rightLetter === "#")) return leftLetter === "#" ? -1 : 1
      return left.localeCompare(right)
    })
    allApps.clear()
    for (var i = 0; i < sorted.length; i++) {
      var name = root.nameOf(sorted[i])
      allApps.append({ appId: String(sorted[i].id), name: name, icon: String(sorted[i].icon || ""), letter: Model.letterFor(name) })
    }
  }

  function rebuildResults() {
    var rows = root.appLibrary && root.searching ? root.appLibrary.sortedEntries(root.filterText) : []
    root.results = rows.map(function(row) { return row.entry })
  }

  readonly property var allLetters: {
    var count = allApps.count
    var names = []
    for (var i = 0; i < count; i++) names.push(allApps.get(i).name)
    return Model.letters(names)
  }

  Connections {
    target: root.appLibrary
    function onAppsChanged() {
      if (!root.opened) {
        root.appsStale = true
        return
      }
      root.rebuildApps()
      if (root.searching) root.rebuildResults()
    }
  }

  // ------------------------------------------------------------- Lifecycle

  function open(payloadJson) {
    var parsed = {}
    try { parsed = payloadJson ? JSON.parse(payloadJson) : {} } catch (e) {}
    root.payload = parsed && typeof parsed === "object" ? parsed : {}
    root.now = Date.now()
    faceProc.running = true
    root.view = "home"
    root.filterText = ""
    root.results = []
    root.menuEntry = null
    root.uninstallEntry = null
    root.powerOpen = false
    root.profileOpen = false
    root.lettersOpen = false
    root.endDrag()
    if (root.appLibrary) root.appLibrary.refreshIcons()
    if (root.appsStale) root.rebuildApps()
    root.home()
    dockPinsProc.running = true
    sleepProc.running = true
    root.opened = true
    // The overlay maps on the focused screen; the dock may have been clicked
    // on another.
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      if (screens[i].name === root.payload.screen) panel.targetScreen = screens[i]
    }
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.menuEntry = null
    root.uninstallEntry = null
    root.powerOpen = false
    root.profileOpen = false
    root.lettersOpen = false
    root.endDrag()
  }

  // Closing from inside tells the host too, so the dock's button and Super
  // open it again rather than closing it.
  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  function home() {
    root.view = "home"
    root.select(root.pinnedEntries.length > 0 ? "pinned" : "recent", 0)
    pinnedGrid.positionViewAtBeginning()
  }

  function showAll() {
    root.view = "all"
    root.lettersOpen = false
    root.select("all", 0)
    allList.positionViewAtBeginning()
  }

  function setFilter(text) {
    root.filterText = text
    root.lettersOpen = false
    root.rebuildResults()
    if (root.searching) root.select("results", 0)
    else if (root.view === "all") root.select("all", 0)
    else root.home()
    resultsList.positionViewAtBeginning()
  }

  // ------------------------------------------------------------- Selection

  function countOf(section) {
    if (section === "pinned") return root.pinnedEntries.length
    if (section === "recent") return root.recentEntries.length
    if (section === "all") return allApps.count
    if (section === "results") return root.results.length
    return 0
  }

  function entryAt(section, index) {
    if (section === "pinned") return root.pinnedEntries[index] || null
    if (section === "recent") return root.recentEntries[index] ? root.recentEntries[index].entry : null
    if (section === "all") return index >= 0 && index < allApps.count ? root.entry(allApps.get(index).appId) : null
    if (section === "results") return root.results[index] || null
    return null
  }

  // The pointer selects what it is over without scrolling; keys bring the
  // selection into view.
  function select(section, index, keepView) {
    root.section = section
    root.index = Math.max(0, Math.min(root.countOf(section) - 1, index))
    if (keepView) return
    if (section === "pinned") pinnedGrid.positionViewAtIndex(root.index, GridView.Contain)
    else if (section === "all") allList.positionViewAtIndex(root.index, ListView.Contain)
    else if (section === "results") resultsList.positionViewAtIndex(root.index, ListView.Contain)
  }

  function isSelected(section, index) {
    return root.section === section && root.index === index
  }

  // Arrows walk the pinned grid and then the recent apps below it, keeping to
  // the side they came from.
  function step(key) {
    if (root.searching || root.view === "all") {
      if (key === "up") root.select(root.section, root.index - 1)
      else if (key === "down") root.select(root.section, root.index + 1)
      return
    }
    var columns = root.section === "pinned" ? root.pinnedColumns : root.recentColumns
    var next = Model.gridStep(root.index, root.countOf(root.section), columns, key)
    if (next.leave > 0 && root.section === "pinned" && root.recentEntries.length > 0) {
      root.select("recent", (root.index % root.pinnedColumns) < root.pinnedColumns / 2 ? 0 : Math.min(1, root.recentEntries.length - 1))
    } else if (next.leave < 0 && root.section === "recent" && root.pinnedEntries.length > 0) {
      var count = root.pinnedEntries.length
      var lastRow = Math.floor((count - 1) / root.pinnedColumns) * root.pinnedColumns
      var column = root.index % root.recentColumns === 0 ? 0 : root.pinnedColumns / 2
      root.select("pinned", Math.min(count - 1, lastRow + column))
    } else if (next.index >= 0) {
      root.select(root.section, next.index)
    }
  }

  // ------------------------------------------------------------- Actions

  function launch(entry) {
    if (!entry || !root.appLibrary) return
    var id = String(entry.id)
    root.recent = Model.addRecent(root.recent, id, Date.now())
    root.saveRecent()
    root.dismiss()
    root.appLibrary.launch(id, root.nameOf(entry))
  }

  function run(command) {
    root.dismiss()
    Util.execDetached(command)
  }

  // The chooser is a window of its own, so the menu makes way for it.
  function choosePicture() {
    root.run("python3 " + Util.shellQuote(root.pluginDir + "/pick-picture.py") + " " + Util.shellQuote(root.facePath)
      + " " + Util.shellQuote(root.tr("startMenu.choosePicture", "Choose a picture")))
  }

  function removePicture() {
    root.profileOpen = false
    removePictureProc.running = true
  }

  function isPinned(entry) {
    return !!entry && root.pins.indexOf(String(entry.id)) >= 0
  }

  function setPins(pins) {
    root.pins = pins
    root.pinsSaved = true
    pinsFile.setText(Model.serializePins(pins))
  }

  function togglePin(entry) {
    if (!entry) return
    var id = String(entry.id)
    root.setPins(root.isPinned(entry) ? Model.unpin(root.pins, id) : Model.pin(root.pins, id))
  }

  function pinToFront(entry) {
    if (entry) root.setPins(Model.movePin(root.pins, String(entry.id), 0))
  }

  function isInDock(entry) {
    return !!entry && root.dockPins.indexOf(String(entry.id)) >= 0
  }

  function toggleDock(entry) {
    if (!entry) return
    var id = String(entry.id)
    if (root.isInDock(entry)) {
      root.dockPins = root.dockPins.filter(function(other) { return other !== id })
      Util.execDetached("omarchy-dock unpin " + Util.shellQuote(id))
    } else {
      root.dockPins = root.dockPins.concat([id])
      Util.execDetached("omarchy-dock pin " + Util.shellQuote(id))
    }
  }

  function forgetRecent(entry) {
    if (!entry) return
    root.recent = Model.forgetRecent(root.recent, String(entry.id))
    root.saveRecent()
  }

  function openMenu(entry, point) {
    root.powerOpen = false
    root.profileOpen = false
    root.menuEntry = entry
    root.menuPoint = point
  }

  // The menu key opens the selected app's menu beside it.
  function openMenuForSelection() {
    var entry = root.entryAt(root.section, root.index)
    if (!entry) return
    var item = root.selectedItem()
    var point = item ? item.mapToItem(panel.contentItem, item.width / 2, item.height / 2) : Qt.point(root.cardPosition.x + root.padding, root.cardPosition.y + root.padding)
    root.openMenu(entry, point)
  }

  function selectedItem() {
    var view = root.section === "pinned" ? pinnedGrid
      : root.section === "recent" ? recentGrid
      : root.section === "all" ? allList
      : resultsList
    return view && view.itemAtIndex ? view.itemAtIndex(root.index) : null
  }

  function requestUninstall(entry) {
    if (!entry) return
    root.menuEntry = null
    uninstallConfirm.selectedIndex = 1
    root.uninstallEntry = entry
  }

  function confirmUninstall() {
    var entry = root.uninstallEntry
    root.uninstallEntry = null
    if (!entry || !root.appLibrary) return
    var id = String(entry.id)
    if (root.isPinned(entry)) root.setPins(Model.unpin(root.pins, id))
    root.forgetRecent(entry)
    root.dismiss()
    root.appLibrary.remove(id, root.nameOf(entry))
  }

  function jumpTo(letter) {
    root.lettersOpen = false
    for (var i = 0; i < allApps.count; i++) {
      if (allApps.get(i).letter === letter) {
        root.select("all", i)
        allList.positionViewAtIndex(i, ListView.Beginning)
        return
      }
    }
  }

  // ------------------------------------------------------------- Dragging pins

  function dragPin(entry, point) {
    if (root.dragId === "") {
      root.menuEntry = null
      root.dragId = String(entry.id)
    }
    root.dragPoint = point
    var inGrid = pinnedGrid.mapFromItem(panel.contentItem, point.x, point.y)
    var column = Math.floor(inGrid.x / root.tileWidth)
    var row = Math.floor((inGrid.y + pinnedGrid.contentY) / root.tileHeight)
    var inside = inGrid.x >= 0 && inGrid.x < pinnedGrid.width && inGrid.y >= 0 && inGrid.y < pinnedGrid.height
    root.dropIndex = inside ? Math.max(0, Math.min(root.pinnedEntries.length - 1, row * root.pinnedColumns + column)) : -1
  }

  // A pin dropped on another takes its slot.
  function dropPin() {
    if (root.dragId !== "" && root.dropIndex >= 0) {
      var target = root.pinnedEntries[root.dropIndex]
      var at = target ? root.pins.indexOf(String(target.id)) : -1
      if (at >= 0 && String(target.id) !== root.dragId) root.setPins(Model.movePin(root.pins, root.dragId, at))
      root.select("pinned", root.dropIndex)
    }
    root.endDrag()
  }

  function endDrag() {
    root.dragId = ""
    root.dropIndex = -1
  }

  // ------------------------------------------------------------- Saved state

  function loadPins(raw) {
    var saved = Model.parsePins(raw)
    root.pinsSaved = saved !== null
    if (saved !== null) root.pins = saved
    else root.pins = root.dockPins.slice()
  }

  function saveRecent() {
    recentFile.setText(JSON.stringify(root.recent) + "\n")
  }

  FileView {
    id: pinsFile
    path: root.configDir + "/start-menu.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadPins(text())
    onLoadFailed: root.loadPins("")
    onFileChanged: reload()
  }

  FileView {
    id: recentFile
    path: root.stateDir + "/recent.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.recent = Model.parseRecent(text())
    onLoadFailed: root.recent = []
    onFileChanged: reload()
  }

  Process {
    running: true
    command: ["mkdir", "-p", root.stateDir]
  }

  // The dock's pins, for the menus' Keep in Dock, and for the start menu's own
  // until the user pins something here.
  Process {
    id: dockPinsProc
    command: ["omarchy-dock", "pinned"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.dockPins = Model.uniqueIds(text.split("\n"))
        if (!root.pinsSaved) root.pins = root.dockPins.slice()
      }
    }
  }

  // Sleep is offered only where the system menu would offer it.
  Process {
    id: sleepProc
    command: ["bash", "-c", "omarchy-toggle-enabled suspend-off || omarchy-sleep-disabled"]
    onExited: function(exitCode) { root.canSleep = exitCode !== 0 }
  }

  Process {
    running: true
    command: ["getent", "passwd", Quickshell.env("USER") || ""]
    stdout: StdioCollector {
      onStreamFinished: {
        var fullName = String(text.split(":")[4] || "").split(",")[0].trim()
        if (fullName) root.userName = fullName
      }
    }
  }

  // Into the trash rather than gone, should it be wanted back.
  Process {
    id: removePictureProc
    command: ["gio", "trash", root.facePath]
    onExited: faceProc.running = true
  }

  // Asked again each time the menu opens, since the picture may have been
  // changed while it was closed.
  Process {
    id: faceProc
    command: ["test", "-f", root.facePath]
    onExited: function(exitCode) {
      root.hasFace = exitCode === 0
      root.faceStamp++
    }
  }

  Component.onCompleted: dockPinsProc.running = true

  // ------------------------------------------------------------- Window

  OverlayWindow {
    id: panel
    shown: root.opened
    WlrLayershell.namespace: "rndaom-start-menu"

    // The dock stays in reach under the menu: its apps button closes it, and
    // its other apps can still be clicked.
    mask: Region {
      item: catcher

      Region {
        intersection: Intersection.Subtract
        x: root.payload.dock ? root.payload.dock.x : 0
        y: root.payload.dock ? root.payload.dock.y : 0
        width: root.payload.dock ? root.payload.dock.width : 0
        height: root.payload.dock ? root.payload.dock.height : 0
      }
    }

    MouseArea {
      id: catcher
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onClicked: {
        if (root.menuEntry || root.powerOpen || root.profileOpen) {
          root.menuEntry = null
          root.powerOpen = false
          root.profileOpen = false
        } else {
          root.dismiss()
        }
      }
    }

    BorderSurface {
      id: card

      x: root.cardPosition.x
      y: root.cardPosition.y
      width: root.cardWidth
      height: root.cardHeight
      radius: Style.cornerRadius
      color: Commons.Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Commons.Color.menu.border, Math.max(1, Style.space(2)))
      clip: true

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: {
          root.menuEntry = null
          root.powerOpen = false
          root.profileOpen = false
          root.lettersOpen = false
        }
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.uninstallEntry) {
            if (uninstallConfirm.handleKey(event)) event.accepted = true
            else if (event.key === Qt.Key_Escape) {
              root.uninstallEntry = null
              event.accepted = true
            }
            return
          }
          var key = Util.readingKey(event)
          if (event.key === Qt.Key_Escape) {
            if (root.menuEntry || root.powerOpen || root.profileOpen || root.lettersOpen) {
              root.menuEntry = null
              root.powerOpen = false
              root.profileOpen = false
              root.lettersOpen = false
            } else if (root.searching) {
              root.setFilter("")
            } else if (root.view === "all") {
              root.home()
            } else {
              root.dismiss()
            }
          } else if (root.menuEntry || root.powerOpen || root.profileOpen) {
            // A popup is up: any other key puts it away and goes on.
            root.menuEntry = null
            root.powerOpen = false
            root.profileOpen = false
            return
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
          } else if (root.lettersOpen && event.text && /^[a-z#]$/i.test(event.text)) {
            root.jumpTo(event.text === "#" ? "#" : event.text.toUpperCase())
          } else if (key === Qt.Key_Left) {
            root.step("left")
          } else if (key === Qt.Key_Right) {
            root.step("right")
          } else if (event.key === Qt.Key_Up) {
            root.step("up")
          } else if (event.key === Qt.Key_Down) {
            root.step("down")
          } else if (event.key === Qt.Key_PageUp && root.section === "all") {
            root.select("all", root.index - 10)
          } else if (event.key === Qt.Key_PageDown && root.section === "all") {
            root.select("all", root.index + 10)
          } else if (event.key === Qt.Key_Home && root.section === "all" && !root.searching) {
            root.select("all", 0)
          } else if (event.key === Qt.Key_End && root.section === "all" && !root.searching) {
            root.select("all", allApps.count - 1)
          } else if (event.key === Qt.Key_Tab && !root.searching) {
            if (root.view === "all") root.home()
            else root.showAll()
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.launch(root.entryAt(root.section, root.index))
          } else if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
            root.openMenuForSelection()
          } else if (event.key === Qt.Key_Delete) {
            root.requestUninstall(root.entryAt(root.section, root.index))
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) > 32 && event.text.charCodeAt(0) !== 127
              && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            root.setFilter(root.filterText + event.text)
          } else if (event.key === Qt.Key_Space && root.searching) {
            root.setFilter(root.filterText + " ")
          } else {
            return
          }
          event.accepted = true
        }
      }

      // ----------------------------------------------------------- Search

      Rectangle {
        id: search
        x: root.padding
        y: root.padding
        width: root.innerWidth
        height: root.searchHeight
        radius: Math.min(height / 2, Math.max(Style.cornerRadius, root.s(6)))
        color: Util.alpha(Commons.Color.menu.text, 0.06)
        border.width: Style.normalBorderWidth
        border.color: root.searching ? Commons.Color.accent : Util.alpha(Commons.Color.menu.text, 0.12)

        Text {
          id: searchGlyph
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.controlPaddingX + Style.spacing.xs
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: ""
          color: Commons.Color.menu.text
          opacity: 0.6
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        Text {
          id: searchText
          anchors.left: searchGlyph.right
          anchors.leftMargin: Style.spacing.lg
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, parent.width - x - Style.spacing.controlPaddingX)
          textFormat: Text.PlainText
          text: root.filterText || root.tr("dock.searchApps", "Search apps…")
          color: Commons.Color.menu.text
          opacity: root.searching ? 1 : 0.55
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.subtitle
          elide: Text.ElideLeft
        }

        // Where typing goes.
        Rectangle {
          visible: root.opened && !root.uninstallEntry
          // Ahead of the hint while nothing is typed, after the text once it is.
          x: root.searching ? searchText.x + searchText.width + 1 : searchText.x - width - Style.spacing.xxs
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(1, Style.space(2))
          height: Math.round(Style.font.subtitle * 1.2)
          color: Commons.Color.accent
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.IBeamCursor
          onClicked: {
            root.menuEntry = null
            root.powerOpen = false
            root.profileOpen = false
            keyCatcher.forceActiveFocus()
          }
        }
      }

      // ----------------------------------------------------------- Body

      Item {
        id: body
        x: root.padding
        y: search.y + search.height + root.sectionGap
        width: root.innerWidth
        height: footer.y - y - root.padding / 2

        // Home: pinned apps and the ones opened lately.
        Item {
          anchors.fill: parent
          visible: !root.searching && root.view === "home"

          SectionHeader {
            id: pinnedHeader
            width: parent.width
            text: root.tr("startMenu.pinned", "Pinned")
            actionText: root.tr("startMenu.allApps", "All apps")
            actionGlyph: ""
            onAction: root.showAll()
          }

          GridView {
            id: pinnedGrid
            y: pinnedHeader.height
            width: parent.width
            height: Math.min(root.pinnedRows * root.tileHeight, parent.height - y - (root.recentEntries.length > 0 ? root.headerHeight + root.rowHeight + root.sectionGap : 0))
            cellWidth: root.tileWidth
            cellHeight: root.tileHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: root.dragId === ""
            model: root.pinnedEntries

            delegate: PinnedTile {}

            Text {
              anchors.centerIn: parent
              visible: root.pinnedEntries.length === 0
              width: parent.width - root.padding * 2
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.Wrap
              textFormat: Text.PlainText
              text: root.tr("startMenu.noPins", "Right-click an app in All apps to pin it here.")
              color: Commons.Color.menu.text
              opacity: 0.6
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
            }
          }

          SectionHeader {
            id: recentHeader
            y: pinnedGrid.y + pinnedGrid.height + root.sectionGap
            width: parent.width
            visible: y + height < parent.height
            text: root.tr("startMenu.recent", "Recent")
          }

          GridView {
            id: recentGrid
            y: recentHeader.y + recentHeader.height
            width: parent.width
            height: Math.max(0, parent.height - y)
            cellWidth: width / root.recentColumns
            cellHeight: root.rowHeight
            clip: true
            interactive: false
            model: root.recentEntries

            delegate: AppRow {
              required property int index
              required property var modelData

              width: recentGrid.cellWidth
              height: root.rowHeight
              section: "recent"
              rowIndex: index
              entry: modelData.entry
              iconSize: root.rowIcon
              subtext: Model.ago(modelData.at, root.now)
            }

            Text {
              anchors.top: parent.top
              anchors.topMargin: Style.spacing.lg
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.lg
              visible: root.recentEntries.length === 0
              textFormat: Text.PlainText
              text: root.tr("startMenu.noRecent", "Apps you open from here show up here.")
              color: Commons.Color.menu.text
              opacity: 0.6
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
            }
          }
        }

        // Every app, filed by letter.
        Item {
          anchors.fill: parent
          visible: !root.searching && root.view === "all"

          SectionHeader {
            id: allHeader
            width: parent.width
            text: root.tr("startMenu.allApps", "All apps")
            actionText: root.tr("startMenu.back", "Back")
            actionGlyph: ""
            actionLeading: true
            onAction: root.home()
          }

          ListView {
            id: allList
            y: allHeader.height
            width: parent.width
            height: parent.height - y
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: allApps
            section.property: "letter"
            section.criteria: ViewSection.FullString
            section.delegate: Item {
              id: letterHeader

              required property string section

              width: allList.width
              height: root.listRowHeight

              Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(height, letterText.implicitWidth + Style.spacing.lg * 2)
                height: Math.round(root.listRowHeight * 0.75)
                radius: Style.cornerRadius
                color: letterMouse.containsMouse ? Style.hoverFill : "transparent"

                Text {
                  id: letterText
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: letterHeader.section
                  color: Commons.Color.accent
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.subtitle
                  font.weight: Font.DemiBold
                }

                MouseArea {
                  id: letterMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.lettersOpen = true
                }
              }
            }

            delegate: AppRow {
              required property int index
              required property string appId

              width: allList.width
              height: root.listRowHeight
              section: "all"
              rowIndex: index
              entry: root.entry(appId)
              iconSize: Math.round(root.rowIcon * 0.9)
            }
          }

          // Jump to a letter, as the start menu does when a letter is clicked.
          Rectangle {
            anchors.fill: allList
            visible: root.lettersOpen
            color: Commons.Color.menu.background
            z: 5

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onClicked: root.lettersOpen = false
            }

            Grid {
              id: letterGrid

              readonly property int cell: Math.min(root.s(52), Math.floor(parent.width / 7))

              anchors.centerIn: parent
              columns: 7

              Repeater {
                model: Model.alphabet()

                delegate: Rectangle {
                  required property string modelData
                  readonly property bool present: root.allLetters.indexOf(modelData) >= 0

                  width: letterGrid.cell
                  height: letterGrid.cell
                  radius: Style.cornerRadius
                  color: present && jumpMouse.containsMouse ? Style.hoverFill : "transparent"

                  Text {
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: parent.modelData
                    color: Commons.Color.menu.text
                    opacity: parent.present ? 1 : 0.3
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.heading
                  }

                  MouseArea {
                    id: jumpMouse
                    anchors.fill: parent
                    enabled: parent.present
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.jumpTo(parent.modelData)
                  }
                }
              }
            }
          }
        }

        // Search results: the best match first, the rest after it.
        ListView {
          id: resultsList
          anchors.fill: parent
          visible: root.searching
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: root.results

          delegate: Column {
            id: result

            required property int index
            required property var modelData

            width: resultsList.width

            SectionHeader {
              visible: result.index === 0 || result.index === 1
              height: visible ? root.headerHeight : 0
              width: parent.width
              text: result.index === 0 ? root.tr("startMenu.bestMatch", "Best match") : root.tr("startMenu.apps", "Apps")
            }

            AppRow {
              width: parent.width
              height: result.index === 0 ? root.s(64) : root.listRowHeight
              section: "results"
              rowIndex: result.index
              entry: result.modelData
              iconSize: result.index === 0 ? root.s(40) : Math.round(root.rowIcon * 0.9)
              subtext: result.index === 0 && root.appLibrary ? (root.appLibrary.entrySubtext(result.modelData) || root.tr("startMenu.app", "App")) : ""
            }
          }

          Text {
            anchors.centerIn: parent
            visible: root.searching && root.results.length === 0
            textFormat: Text.PlainText
            text: root.tr("dock.noAppsMatch", "No apps match “%1”").arg(root.filterText)
            color: Commons.Color.menu.text
            opacity: 0.7
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.title
          }
        }
      }

      // ----------------------------------------------------------- Footer

      Item {
        id: footer
        x: card.borderLeft
        width: card.width - card.borderLeft - card.borderRight
        height: root.footerHeight
        y: card.height - card.borderBottom - height
        clip: true

        // Rounded along the card's lower corners and square under the body.
        Rectangle {
          readonly property real corner: Math.max(0, Style.cornerRadius - card.borderBottom)

          y: -corner
          width: parent.width
          height: parent.height + corner
          radius: corner
          color: Util.alpha(Commons.Color.menu.text, 0.04)
        }

        Rectangle {
          width: parent.width
          height: Math.max(1, Style.space(1))
          color: Util.alpha(Commons.Color.menu.text, 0.1)
        }

        ProfilePicture {
          id: profileButton
          anchors.left: parent.left
          anchors.leftMargin: root.padding - Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          source: root.hasFace ? root.facePath : ""
          stamp: root.faceStamp
          name: root.userName
          active: root.profileOpen
          onClicked: {
            root.menuEntry = null
            root.powerOpen = false
            root.profileOpen = !root.profileOpen
          }
        }

        Row {
          id: footerButtons
          anchors.right: parent.right
          anchors.rightMargin: root.padding - Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xs

          IconButton {
            id: filesButton
            glyph: ""
            label: root.tr("startMenu.files", "Files")
            onClicked: root.run("omarchy-launch-nautilus")
          }

          IconButton {
            id: omarchyMenuButton
            glyph: ""
            label: root.tr("startMenu.settings", "Omarchy menu")
            onClicked: root.run("omarchy-menu toggle root")
          }

          IconButton {
            id: powerButton
            glyph: ""
            label: root.tr("startMenu.power", "Power")
            active: root.powerOpen
            onClicked: {
              root.menuEntry = null
              root.profileOpen = false
              root.powerOpen = !root.powerOpen
            }
          }
        }
      }

      ConfirmDialog {
        id: uninstallConfirm

        anchors.fill: parent
        opened: !!root.uninstallEntry
        z: 10
        message: root.tr("common.uninstallConfirm", "Do you want to uninstall %1?").arg(root.nameOf(root.uninstallEntry))
        confirmText: root.tr("common.uninstall", "Uninstall")
        background: Commons.Color.menu.background
        foreground: Commons.Color.menu.text
        scrim: Commons.Color.menu.scrim
        selectedBackground: Commons.Color.menu.selectedBackground
        selectedText: Commons.Color.menu.selectedText
        fontFamily: Style.font.menuFamily
        cornerRadius: Style.cornerRadius
        onCanceled: root.uninstallEntry = null
        onConfirmed: root.confirmUninstall()
      }
    }

    // The pinned app being dragged, under the pointer.
    Image {
      visible: root.dragId !== ""
      x: root.dragPoint.x - width / 2
      y: root.dragPoint.y - height / 2
      width: root.tileIcon
      height: root.tileIcon
      sourceSize: Qt.size(root.tileIcon * 2, root.tileIcon * 2)
      source: root.dragId !== "" ? root.iconOf(root.entry(root.dragId)) : ""
      fillMode: Image.PreserveAspectFit
      smooth: true
      mipmap: true
    }

    // Right-click on an app.
    BorderSurface {
      id: appMenu

      readonly property var entry: root.menuEntry
      readonly property bool pinned: root.isPinned(entry)

      visible: !!entry && root.dragId === ""
      width: Math.max(root.s(180), appMenuColumn.implicitWidth) + padding * 2
      height: appMenuColumn.implicitHeight + padding * 2
      x: LayoutMirroring.enabled
        ? Math.max(Style.gapsOut, root.menuPoint.x - width)
        : Math.min(root.menuPoint.x, panel.width - width - Style.gapsOut)
      y: Math.min(root.menuPoint.y, panel.height - height - Style.gapsOut)
      radius: Style.cornerRadius
      color: Commons.Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Style.normalBorderWidth)
      padding: Style.spacing.sm
      z: 15

      Column {
        id: appMenuColumn
        x: appMenu.contentLeftInset
        y: appMenu.contentTopInset
        width: appMenu.width - appMenu.contentLeftInset - appMenu.contentRightInset

        MenuRow {
          text: root.tr("dock.open", "Open")
          onTriggered: root.launch(appMenu.entry)
        }

        MenuRow {
          text: appMenu.pinned ? root.tr("startMenu.unpin", "Unpin from Start") : root.tr("startMenu.pin", "Pin to Start")
          onTriggered: {
            root.togglePin(appMenu.entry)
            root.menuEntry = null
          }
        }

        MenuRow {
          visible: appMenu.pinned && root.pins.indexOf(String(appMenu.entry.id)) > 0
          text: root.tr("startMenu.moveToFront", "Move to front")
          onTriggered: {
            root.pinToFront(appMenu.entry)
            root.menuEntry = null
          }
        }

        MenuRow {
          text: root.isInDock(appMenu.entry) ? root.tr("dock.removeFromDock", "Remove from Dock") : root.tr("dock.keepInDock", "Keep in Dock")
          onTriggered: {
            root.toggleDock(appMenu.entry)
            root.menuEntry = null
          }
        }

        MenuRow {
          visible: root.section === "recent" && root.recentEntries.some(function(item) { return item.entry === appMenu.entry })
          text: root.tr("startMenu.removeFromRecent", "Remove from Recent")
          onTriggered: {
            root.forgetRecent(appMenu.entry)
            root.menuEntry = null
          }
        }

        MenuRow {
          text: root.tr("dock.uninstall", "Uninstall")
          onTriggered: root.requestUninstall(appMenu.entry)
        }
      }
    }

    // The power button's choices, above it.
    BorderSurface {
      id: powerMenu

      visible: root.powerOpen
      width: Math.max(root.s(170), powerColumn.implicitWidth) + padding * 2
      height: powerColumn.implicitHeight + padding * 2
      readonly property point anchorPoint: powerButton.mapToItem(panel.contentItem, powerButton.width, 0)
      x: Math.max(Style.gapsOut, Math.min(panel.width - width - Style.gapsOut, anchorPoint.x - width))
      y: Math.max(Style.gapsOut, anchorPoint.y - height - Style.spacing.sm)
      radius: Style.cornerRadius
      color: Commons.Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Style.normalBorderWidth)
      padding: Style.spacing.sm
      z: 15

      Column {
        id: powerColumn
        x: powerMenu.contentLeftInset
        y: powerMenu.contentTopInset
        width: powerMenu.width - powerMenu.contentLeftInset - powerMenu.contentRightInset

        MenuRow { glyph: ""; text: root.tr("startMenu.lock", "Lock"); onTriggered: root.run("omarchy-system-lock") }
        MenuRow { glyph: ""; visible: root.canSleep; text: root.tr("startMenu.sleep", "Sleep"); onTriggered: root.run("systemctl suspend") }
        MenuRow { glyph: ""; text: root.tr("startMenu.logout", "Log out"); onTriggered: root.run("omarchy-system logout") }
        MenuRow { glyph: ""; text: root.tr("startMenu.restart", "Restart"); onTriggered: root.run("omarchy-system reboot") }
        MenuRow { glyph: ""; text: root.tr("startMenu.shutdown", "Shut down"); onTriggered: root.run("omarchy-system shutdown") }
      }
    }

    // The profile picture's choices, above it.
    BorderSurface {
      id: profileMenu

      visible: root.profileOpen
      width: Math.max(root.s(170), profileColumn.implicitWidth) + padding * 2
      height: profileColumn.implicitHeight + padding * 2
      readonly property point anchorPoint: profileButton.mapToItem(panel.contentItem, 0, 0)
      x: Math.max(Style.gapsOut, Math.min(panel.width - width - Style.gapsOut, anchorPoint.x))
      y: Math.max(Style.gapsOut, anchorPoint.y - height - Style.spacing.sm)
      radius: Style.cornerRadius
      color: Commons.Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Style.normalBorderWidth)
      padding: Style.spacing.sm
      z: 15

      Column {
        id: profileColumn
        x: profileMenu.contentLeftInset
        y: profileMenu.contentTopInset
        width: profileMenu.width - profileMenu.contentLeftInset - profileMenu.contentRightInset

        MenuRow {
          glyph: ""
          text: profileButton.pictured ? root.tr("startMenu.changePicture", "Change picture") : root.tr("startMenu.addPicture", "Add a picture")
          onTriggered: root.choosePicture()
        }
        MenuRow {
          glyph: ""
          visible: profileButton.pictured
          text: root.tr("startMenu.removePicture", "Remove picture")
          onTriggered: root.removePicture()
        }
      }
    }

    // The footer buttons' labels. Drawn here rather than in the buttons, where
    // the footer and the card would cut them off, and kept on the screen.
    ToolTipText {
      readonly property Item target: filesButton.hovered ? filesButton
        : omarchyMenuButton.hovered ? omarchyMenuButton
        : powerButton.hovered && !root.powerOpen ? powerButton
        : profileButton.hovered && !root.profileOpen ? profileButton
        : null
      // Read again when the card moves or resizes, which mapToItem alone would
      // not notice.
      readonly property point anchorPoint: target && card.x + card.y + card.width + card.height + panel.width > -1 ? target.mapToItem(panel.contentItem, target.width / 2, 0) : Qt.point(0, 0)

      shown: target !== null
      text: target === profileButton ? root.tr("startMenu.profile", "Your picture") : target ? target.label : ""
      x: Math.round(Math.max(Style.gapsOut, Math.min(panel.width - width - Style.gapsOut, anchorPoint.x - width / 2)))
      y: Math.round(Math.max(Style.gapsOut, anchorPoint.y - height - Style.spacing.sm))
    }
  }

  // ------------------------------------------------------------- Pieces

  component SectionHeader: Item {
    id: header

    property string text: ""
    property string actionText: ""
    property string actionGlyph: ""
    property bool actionLeading: false
    signal action()

    height: root.headerHeight

    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.md
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: header.text
      color: Commons.Color.menu.text
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.subtitle
      font.weight: Font.DemiBold
    }

    Rectangle {
      visible: header.actionText !== ""
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: actionRow.implicitWidth + Style.spacing.controlPaddingX * 2
      height: Math.round(root.headerHeight * 0.9)
      radius: Style.cornerRadius
      color: actionMouse.containsMouse ? Style.hoverFill : Util.alpha(Commons.Color.menu.text, 0.06)

      Row {
        id: actionRow
        anchors.centerIn: parent
        spacing: Style.spacing.md
        layoutDirection: header.actionLeading ? Qt.RightToLeft : Qt.LeftToRight

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: header.actionText
          color: Commons.Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: header.actionGlyph
          color: Commons.Color.menu.text
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      MouseArea {
        id: actionMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: header.action()
      }
    }
  }

  // A pinned app: its icon over its name.
  component PinnedTile: Item {
    id: tile

    required property int index
    required property var modelData
    readonly property bool selected: root.isSelected("pinned", index)
    readonly property bool dragged: root.dragId === String(modelData.id)
    readonly property bool dropTarget: root.dropIndex === index && !dragged
    property point pressPoint
    property bool moved: false

    width: root.tileWidth
    height: root.tileHeight

    Rectangle {
      anchors.fill: parent
      anchors.margins: Style.spacing.xxs
      radius: Style.cornerRadius
      color: tile.selected && root.dragId === "" ? Commons.Color.menu.selectedBackground : "transparent"
      border.width: tile.dropTarget ? Style.normalBorderWidth : 0
      border.color: Commons.Color.accent
    }

    Image {
      id: tileIcon
      anchors.horizontalCenter: parent.horizontalCenter
      y: root.s(10)
      width: root.tileIcon
      height: root.tileIcon
      sourceSize: Qt.size(root.tileIcon * 2, root.tileIcon * 2)
      source: root.iconOf(tile.modelData)
      fillMode: Image.PreserveAspectFit
      asynchronous: false
      smooth: true
      mipmap: true
      opacity: tile.dragged ? 0.35 : 1
    }

    Text {
      anchors.top: tileIcon.bottom
      anchors.topMargin: root.s(8)
      anchors.horizontalCenter: parent.horizontalCenter
      width: parent.width - Style.spacing.md * 2
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: root.nameOf(tile.modelData)
      color: tile.selected && root.dragId === "" ? Commons.Color.menu.selectedText : Commons.Color.menu.text
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
      opacity: tile.dragged ? 0.35 : 1
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      preventStealing: true
      onContainsMouseChanged: if (containsMouse && root.dragId === "" && !root.menuEntry) root.select("pinned", tile.index, true)
      onPressed: function(event) {
        tile.moved = false
        tile.pressPoint = Qt.point(event.x, event.y)
      }
      onPositionChanged: function(event) {
        if (!(pressedButtons & Qt.LeftButton)) return
        if (!tile.moved && Math.hypot(event.x - tile.pressPoint.x, event.y - tile.pressPoint.y) > Style.space(6)) tile.moved = true
        if (tile.moved) root.dragPin(tile.modelData, tile.mapToItem(panel.contentItem, event.x, event.y))
      }
      onReleased: function(event) {
        if (root.dragId !== "" && event.button === Qt.LeftButton) root.dropPin()
      }
      onCanceled: root.endDrag()
      onClicked: function(event) {
        if (tile.moved) return
        if (event.button === Qt.RightButton) {
          root.select("pinned", tile.index, true)
          root.openMenu(tile.modelData, tile.mapToItem(panel.contentItem, event.x, event.y))
          return
        }
        root.launch(tile.modelData)
      }
    }
  }

  // An app on a row: its icon, its name, and a line under it.
  component AppRow: Item {
    id: row

    property string section: ""
    property int rowIndex: 0
    property var entry: null
    property int iconSize: root.rowIcon
    property string subtext: ""
    readonly property bool selected: root.isSelected(section, rowIndex)

    Rectangle {
      anchors.fill: parent
      anchors.margins: Style.spacing.xxs
      radius: Style.cornerRadius
      color: row.selected ? Commons.Color.menu.selectedBackground : "transparent"
    }

    Image {
      id: rowIcon
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.lg
      anchors.verticalCenter: parent.verticalCenter
      width: row.iconSize
      height: row.iconSize
      sourceSize: Qt.size(row.iconSize * 2, row.iconSize * 2)
      source: root.iconOf(row.entry)
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true
      mipmap: true
    }

    Column {
      anchors.left: rowIcon.right
      anchors.leftMargin: Style.spacing.xl
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.lg
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.xxs

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.nameOf(row.entry)
        color: row.selected ? Commons.Color.menu.selectedText : Commons.Color.menu.text
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        visible: row.subtext !== ""
        width: parent.width
        textFormat: Text.PlainText
        text: row.subtext
        color: Commons.Color.menu.text
        opacity: 0.6
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onContainsMouseChanged: if (containsMouse && !root.menuEntry) root.select(row.section, row.rowIndex, true)
      onClicked: function(event) {
        if (event.button === Qt.RightButton) {
          root.select(row.section, row.rowIndex, true)
          root.openMenu(row.entry, row.mapToItem(panel.contentItem, event.x, event.y))
          return
        }
        root.launch(row.entry)
      }
    }
  }
}
