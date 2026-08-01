#!/usr/bin/env python

import os
import sys
import time
import traceback

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib


ITEM_PATH = "/StatusNotifierItem"
MENU_PATH = "/StatusNotifierItem/Menu"


def variant(value):
  return dbus.Variant(value)


class StatusNotifierItem(dbus.service.Object):
  def __init__(self, bus):
    super().__init__(bus, ITEM_PATH)

  @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ss", out_signature="v")
  def Get(self, interface, prop):
    return variant(self.GetAll(interface)[prop])

  @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="s", out_signature="a{sv}")
  def GetAll(self, interface):
    if interface != "org.kde.StatusNotifierItem":
      return {}

    return dbus.Dictionary({
      "Category": "ApplicationStatus",
      "Id": "omarchy-test-tray",
      "Title": "omarchy-test-tray",
      "Status": "Active",
      "WindowId": dbus.Int32(0),
      "IconName": "dialog-information",
      "IconThemePath": "",
      "Menu": dbus.ObjectPath(MENU_PATH),
      "ItemIsMenu": dbus.Boolean(False),
      "ToolTip": dbus.Struct((
        "",
        dbus.Array([], signature="(iiay)"),
        "omarchy-test-tray",
        "",
      ), signature=None),
    }, signature="sv")

  @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ssv")
  def Set(self, interface, prop, value):
    return

  @dbus.service.method("org.kde.StatusNotifierItem", in_signature="ii")
  def ContextMenu(self, x, y):
    return

  @dbus.service.method("org.kde.StatusNotifierItem", in_signature="ii")
  def Activate(self, x, y):
    return

  @dbus.service.method("org.kde.StatusNotifierItem", in_signature="ii")
  def SecondaryActivate(self, x, y):
    return

  @dbus.service.method("org.kde.StatusNotifierItem", in_signature="is")
  def Scroll(self, delta, orientation):
    return


class DBusMenu(dbus.service.Object):
  def __init__(self, bus, event_path, query_path, command_path):
    super().__init__(bus, MENU_PATH)
    self.event_path = event_path
    self.query_path = query_path
    self.command_path = command_path
    self.revision = 1
    self.shapes_visible = True

  def nodes(self):
    drawing_children = [4, 5, 6] if self.shapes_visible else [5, 6]
    return {
      0: ({"children-display": "submenu"}, [1, 2, 3]),
      1: ({"label": "Sign in", "enabled": True}, []),
      2: ({"type": "separator"}, []),
      3: ({"label": "Drawing Modes", "enabled": True, "children-display": "submenu"}, drawing_children),
      4: ({"label": "Shapes", "enabled": True, "children-display": "submenu"}, [7]),
      5: ({"type": "separator"}, []),
      6: ({"label": "Brush", "enabled": True}, []),
      7: ({"label": "Arrow", "enabled": True}, []),
    }

  def layout(self, item_id, depth, variant_level=0):
    properties, child_ids = self.nodes()[item_id]
    children = []
    if depth != 0:
      child_depth = depth - 1 if depth > 0 else depth
      children = [self.layout(child_id, child_depth, 1) for child_id in child_ids]
    return dbus.Struct((
      dbus.Int32(item_id),
      dbus.Dictionary(properties, signature="sv"),
      dbus.Array(children, signature="v"),
    ), signature=None, variant_level=variant_level)

  def append(self, path, line):
    with open(path, "a", encoding="utf-8") as handle:
      handle.write(line + "\n")

  def poll_command(self):
    try:
      with open(self.command_path, "r", encoding="utf-8") as handle:
        command = handle.read().strip()
    except FileNotFoundError:
      return True

    os.remove(self.command_path)
    if command == "remove-shapes" and self.shapes_visible:
      self.shapes_visible = False
      self.revision += 1
      self.LayoutUpdated(dbus.UInt32(self.revision), dbus.Int32(3))
    return True

  @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ss", out_signature="v")
  def Get(self, interface, prop):
    return variant(self.GetAll(interface)[prop])

  @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="s", out_signature="a{sv}")
  def GetAll(self, interface):
    if interface != "com.canonical.dbusmenu":
      return {}
    return dbus.Dictionary({
      "Version": dbus.UInt32(3),
      "TextDirection": "ltr",
      "Status": "normal",
      "IconThemePath": dbus.Array([], signature="s"),
    }, signature="sv")

  @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ssv")
  def Set(self, interface, prop, value):
    return

  @dbus.service.method("com.canonical.dbusmenu", in_signature="i", out_signature="b")
  def AboutToShow(self, item_id):
    return False

  @dbus.service.method("com.canonical.dbusmenu", in_signature="ai", out_signature="aiai")
  def AboutToShowGroup(self, item_ids):
    return ([], [])

  @dbus.service.method("com.canonical.dbusmenu", in_signature="iias", out_signature="u(ia{sv}av)")
  def GetLayout(self, parent_id, recursion_depth, property_names):
    parent_id = int(parent_id)
    recursion_depth = int(recursion_depth)
    self.append(self.query_path, f"{parent_id} {recursion_depth}")
    return (dbus.UInt32(self.revision), self.layout(parent_id, recursion_depth))

  @dbus.service.method("com.canonical.dbusmenu", in_signature="aias", out_signature="a(ia{sv})")
  def GetGroupProperties(self, item_ids, property_names):
    return []

  @dbus.service.method("com.canonical.dbusmenu", in_signature="is", out_signature="v")
  def GetProperty(self, item_id, name):
    return variant("")

  @dbus.service.method("com.canonical.dbusmenu", in_signature="isvu")
  def Event(self, item_id, event_id, data, timestamp):
    self.append(self.event_path, f"{str(event_id)} {int(item_id)}")

  @dbus.service.method("com.canonical.dbusmenu", in_signature="a(isvu)", out_signature="ai")
  def EventGroup(self, events):
    for item_id, event_id, data, timestamp in events:
      self.Event(item_id, event_id, data, timestamp)
    return []

  @dbus.service.signal("com.canonical.dbusmenu", signature="ui")
  def LayoutUpdated(self, revision, parent):
    return


def register_with_watcher(bus):
  watcher = dbus.Interface(
    bus.get_object("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher"),
    "org.kde.StatusNotifierWatcher",
  )
  watcher.RegisterStatusNotifierItem(ITEM_PATH)


def main():
  try:
    return run()
  except Exception:
    traceback.print_exc()
    return 1


def run():
  event_path = os.environ["OMARCHY_TRAY_MENU_EVENT_LOG"]
  query_path = os.environ["OMARCHY_TRAY_MENU_QUERY_LOG"]
  command_path = os.environ["OMARCHY_TRAY_MENU_COMMAND"]
  ready_path = os.environ["OMARCHY_TRAY_MENU_READY"]

  DBusGMainLoop(set_as_default=True)
  bus = dbus.SessionBus()
  dbus.service.BusName("org.omarchy.TestStatusNotifier", bus)

  StatusNotifierItem(bus)
  menu = DBusMenu(bus, event_path, query_path, command_path)
  GLib.timeout_add(50, menu.poll_command)

  for _ in range(50):
    try:
      register_with_watcher(bus)
      with open(ready_path, "w", encoding="utf-8") as handle:
        handle.write("ready\n")
      break
    except dbus.DBusException:
      time.sleep(0.1)
  else:
    print("timed out registering StatusNotifierItem", file=sys.stderr)
    return 1

  GLib.MainLoop().run()
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
