import os
import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk

events = open(os.path.join(os.environ["TEST_ROOT"], "input-events.log"), "w", buffering=1)
window = Gtk.Window(title="still.fail isolated input test")
window.set_default_size(800, 600)
box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
box.set_halign(Gtk.Align.CENTER)
box.set_valign(Gtk.Align.CENTER)
entry = Gtk.Entry()
entry.set_size_request(400, 80)
entry.set_placeholder_text("Remote input test")
entry.connect("button-press-event", lambda _entry, event: events.write("button:%d\n" % event.button) and False)
entry.connect("key-press-event", lambda _entry, event: events.write("key:%s\n" % event.string) and False)
entry.connect("changed", lambda field: events.write("text:%s\n" % field.get_text()))
box.pack_start(entry, False, False, 0)
window.add(box)
window.connect("destroy", Gtk.main_quit)
window.fullscreen()
window.show_all()
entry.grab_focus()
Gtk.main()
