import QtQuick
import Quickshell
import Quickshell.Services.SystemTray

ShellRoot {
  id: root

  property string resultPath: Quickshell.env("OMARCHY_QML_TEST_RESULT")
  property string commandPath: Quickshell.env("OMARCHY_TRAY_MENU_COMMAND")
  property string rootPath: Quickshell.env("OMARCHY_PATH")
  property var trayItem: null
  property var trayWidget: null
  property string phase: "load"
  property int attempts: 0
  property var failures: []

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function fail(message) {
    failures.push(String(message))
  }

  function assertTrue(condition, message) {
    if (!condition) fail(message)
  }

  function writeResult() {
    var payload = JSON.stringify({
      ok: failures.length === 0,
      failures: failures,
      phase: phase
    })
    Quickshell.execDetached(["bash", "-lc", "printf '%s' " + shellQuote(payload) + " > " + shellQuote(resultPath)])
  }

  function writeCommand(command) {
    Quickshell.execDetached(["bash", "-lc", "printf '%s' " + shellQuote(command) + " > " + shellQuote(commandPath)])
  }

  function findTrayItem() {
    var values = SystemTray.items.values
    for (var i = 0; i < values.length; i++) {
      if (String(values[i].id || "") === "omarchy-test-tray") return values[i]
    }
    return null
  }

  function findRow(label) {
    if (!trayWidget) return null
    var rows = trayWidget.trayMenuRows()
    for (var i = 0; i < rows.length; i++) {
      if (String(rows[i].text || "") === label) return rows[i]
    }
    return null
  }

  function findSeparatorIndex() {
    if (!trayWidget) return -1
    var rows = trayWidget.trayMenuRows()
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].isSeparator) return i
    }
    return -1
  }

  function selectRow(label) {
    var target = findRow(label)
    var rows = trayWidget ? trayWidget.trayMenuRows() : []
    for (var i = 0; target && i <= rows.length; i++) {
      if (trayWidget.selectedTrayMenuEntry() === target) return true
      if (!trayWidget.moveTrayMenuSelection(1)) return false
    }
    return false
  }

  function openMenu() {
    trayWidget.managePopupOpen = true
    trayWidget.openTrayMenu(trayItem, trayWidget, { x: 0, y: 0 })
    assertTrue(!trayWidget.managePopupOpen, "opening a tray menu closes the manage popup")
  }

  function loadWidget() {
    var component = Qt.createComponent("file://" + rootPath + "/shell/plugins/bar/widgets/Tray.qml", Component.PreferSynchronous)
    if (component.status !== Component.Ready) {
      fail("Tray.qml failed to load: " + component.errorString())
      phase = "failed"
      writeResult()
      return
    }

    trayWidget = component.createObject(host, {
      bar: fakeBar,
      settings: {}
    })
    if (!trayWidget) {
      fail("Tray.qml failed to instantiate: " + component.errorString())
      phase = "failed"
      writeResult()
      return
    }
    phase = "wait-item"
  }

  Item {
    id: host
    width: 800
    height: 600
  }

  QtObject {
    id: fakeBar
    property bool vertical: false
    property int barSize: 26
    property string position: "top"
    property string fontFamily: "monospace"
    property color foreground: "white"
    property color background: "black"
    property color urgent: "red"
    property var activePopout: null
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) { if (activePopout === owner) activePopout = null }
    function moduleWidgets(id) { return root.trayWidget ? [root.trayWidget] : [] }
    function run(command) {}
    function showTooltip(target, text) {}
    function hideTooltip(target) {}
    function registerClickTarget(target) {}
    function unregisterClickTarget(target) {}
  }

  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      root.attempts++
      if (root.attempts > 240) {
        root.fail("timed out in phase " + root.phase)
        root.phase = "timed-out"
        stop()
        root.writeResult()
        return
      }

      if (root.phase === "load") {
        root.loadWidget()
      } else if (root.phase === "wait-item") {
        root.trayItem = root.findTrayItem()
        if (root.trayItem) {
          root.openMenu()
          root.phase = "flat"
        }
      } else if (root.phase === "flat") {
        var signIn = root.findRow("Sign in")
        if (signIn) {
          root.assertTrue(root.trayWidget.activateTrayMenuEntry(signIn, false), "flat root action activates")
          root.assertTrue(!root.trayWidget.trayMenuOpen, "flat action closes the tray menu")
          root.assertTrue(root.trayWidget.activeTrayItem === null, "closing releases the active tray item")
          root.openMenu()
          root.phase = "nested-root"
        }
      } else if (root.phase === "nested-root") {
        var drawing = root.findRow("Drawing Modes")
        if (drawing) {
          root.assertTrue(root.trayWidget.activateTrayMenuEntry(drawing, true), "pointer opens the first submenu")
          root.assertTrue(!root.trayWidget.activateTrayMenuEntry(drawing, true), "pointer guard rejects a second click")
          root.phase = "nested-level-one"
        }
      } else if (root.phase === "nested-level-one") {
        var shapes = root.findRow("Shapes")
        if (shapes && !root.trayWidget.trayMenuPointerGuarded) {
          var separatorIndex = root.findSeparatorIndex()
          root.assertTrue(separatorIndex >= 0, "submenu exposes its separator")
          root.assertTrue(!root.trayWidget.isTrayMenuRowHidden(root.trayWidget.trayMenuRows()[separatorIndex], separatorIndex), "submenu separator is not hidden by root heuristics")
          root.assertTrue(root.trayWidget.activateTrayMenuEntry(shapes, true), "pointer opens the second submenu")
          root.phase = "nested-level-two"
        }
      } else if (root.phase === "nested-level-two") {
        var arrow = root.findRow("Arrow")
        if (arrow && !root.trayWidget.trayMenuPointerGuarded) {
          root.assertTrue(root.trayWidget.trayMenuDepth === 2, "actual widget reaches submenu depth two")
          root.assertTrue(root.trayWidget.selectedTrayMenuEntry() === arrow, "nested leaf receives keyboard selection")
          root.assertTrue(root.trayWidget.activateSelectedTrayMenuEntry(), "Enter activates the selected nested leaf")
          root.assertTrue(root.trayWidget.trayMenuDepth === 0, "leaf action releases every submenu depth")
          root.openMenu()
          root.phase = "keyboard-root"
        }
      } else if (root.phase === "keyboard-root") {
        var keyboardDrawing = root.findRow("Drawing Modes")
        if (keyboardDrawing) {
          root.assertTrue(root.selectRow("Drawing Modes"), "keyboard selection reaches the first submenu")
          root.assertTrue(root.trayWidget.navigateTrayMenuHorizontally(1), "Right opens the selected submenu")
          root.phase = "keyboard-level-one"
        }
      } else if (root.phase === "keyboard-level-one") {
        var keyboardShapes = root.findRow("Shapes")
        if (keyboardShapes) {
          root.assertTrue(root.trayWidget.navigateTrayMenuHorizontally(-1), "Left returns to the parent menu")
          root.assertTrue(root.trayWidget.trayMenuDepth === 0, "Left releases only the active submenu")
          root.phase = "keyboard-reopen-root"
        }
      } else if (root.phase === "keyboard-reopen-root") {
        var reopenDrawing = root.findRow("Drawing Modes")
        if (reopenDrawing) {
          root.assertTrue(root.selectRow("Drawing Modes"), "keyboard selection reaches the reopened submenu")
          root.assertTrue(root.trayWidget.navigateTrayMenuHorizontally(1), "Right reopens the first submenu")
          root.phase = "keyboard-reopen-level-one"
        }
      } else if (root.phase === "keyboard-reopen-level-one") {
        var reopenShapes = root.findRow("Shapes")
        if (reopenShapes) {
          root.assertTrue(root.selectRow("Shapes"), "keyboard selection reaches the depth-two submenu")
          root.assertTrue(root.trayWidget.navigateTrayMenuHorizontally(1), "Right opens a depth-two submenu")
          root.phase = "invalidate"
        }
      } else if (root.phase === "invalidate") {
        if (root.findRow("Arrow")) {
          root.writeCommand("remove-shapes")
          root.phase = "wait-invalidation"
        }
      } else if (root.phase === "wait-invalidation") {
        if (root.trayWidget.trayMenuDepth === 0) {
          root.assertTrue(root.trayWidget.trayMenuOpen, "layout invalidation returns to the root menu")
          root.trayWidget.close()
          root.assertTrue(root.trayWidget.activeTrayItem === null, "explicit close releases the root menu handle")
          root.phase = "complete"
          stop()
          root.writeResult()
        }
      }
    }
  }
}
