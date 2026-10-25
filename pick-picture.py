#!/usr/bin/python3
"""Asks the desktop's file chooser for a picture and keeps a copy of it.

    pick-picture.py <destination> [title]

The chooser is the xdg-desktop-portal one, the way Omarchy's own apps open
files, so it follows the desktop's look. Closing it without a choice leaves the
destination as it was. The copy lands under a temporary name and is renamed
into place, so a reader never sees half a picture.
"""

import os
import shutil
import sys
import tempfile
from urllib.parse import unquote, urlparse

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

PORTAL = "org.freedesktop.portal.Desktop"
PORTAL_PATH = "/org/freedesktop/portal/desktop"


def choose(title):
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    token = "start_menu_%d" % os.getpid()
    sender = bus.get_unique_name()[1:].replace(".", "_")
    request = "%s/request/%s/%s" % (PORTAL_PATH, sender, token)
    loop = GLib.MainLoop()
    chosen = []

    def on_response(_bus, _sender, _path, _interface, _signal, params):
        code, results = params.unpack()
        if code == 0:
            chosen.extend(results.get("uris", []))
        loop.quit()

    # Subscribed before asking, so a quick answer is not missed.
    bus.signal_subscribe(PORTAL, "org.freedesktop.portal.Request", "Response", request, None,
                         Gio.DBusSignalFlags.NONE, on_response)

    options = {
        "handle_token": GLib.Variant("s", token),
        "filters": GLib.Variant("a(sa(us))", [("Images", [(1, "image/*")])]),
    }
    pictures = os.path.expanduser("~/Pictures")
    if os.path.isdir(pictures):
        options["current_folder"] = GLib.Variant("ay", (pictures + "\0").encode())

    bus.call_sync(PORTAL, PORTAL_PATH, "org.freedesktop.portal.FileChooser", "OpenFile",
                  GLib.Variant("(ssa{sv})", ("", title, options)), GLib.VariantType("(o)"),
                  Gio.DBusCallFlags.NONE, -1, None)
    loop.run()
    return chosen[0] if chosen else None


def main():
    if len(sys.argv) < 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    destination = os.path.expanduser(sys.argv[1])
    uri = choose(sys.argv[2] if len(sys.argv) > 2 else "Choose a picture")
    if not uri:
        return 1

    source = unquote(urlparse(uri).path)
    folder = os.path.dirname(destination) or "."
    handle, partial = tempfile.mkstemp(prefix=".face-", dir=folder)
    try:
        with os.fdopen(handle, "wb") as out, open(source, "rb") as picture:
            shutil.copyfileobj(picture, out)
        os.chmod(partial, 0o644)
        os.replace(partial, destination)
    except BaseException:
        os.unlink(partial)
        raise
    return 0


if __name__ == "__main__":
    sys.exit(main())
