import os
import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Vte", "2.91")
from gi.repository import Gtk, GLib, Vte

root = os.environ["TEST_ROOT"]
events = open(os.path.join(root, "input-events.log"), "w", buffering=1)
window = Gtk.Window(title="still.fail isolated terminal test")
window.set_default_size(800, 600)
terminal = Vte.Terminal()
window.add(terminal)
window.connect("destroy", Gtk.main_quit)
terminal.connect("button-press-event", lambda _terminal, event: events.write("button:%d\n" % event.button) and False)
terminal.connect("key-press-event", lambda _terminal, event: events.write("key:%s\n" % event.string) and False)
terminal.spawn_sync(Vte.PtyFlags.DEFAULT, None, ["/bin/sh", "-c", 'stty raw -echo; exec cat > "$TEST_ROOT/vte-input.log"'], None, GLib.SpawnFlags.DEFAULT, None, None, None)
window.fullscreen()
window.show_all()
terminal.grab_focus()
previous = [""]
def changed():
    try:
        with open(os.path.join(root, "vte-input.log")) as f:
            text = f.read()
        if text != previous[0]:
            previous[0] = text
            events.write("text:%s\n" % text)
    except FileNotFoundError:
        pass
    return True
GLib.timeout_add(50, changed)
Gtk.main()
