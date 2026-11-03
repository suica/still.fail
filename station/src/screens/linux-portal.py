#!/usr/bin/python3
"""The station's desktop portal client. Its only stdout is framed JSON and JPEG for linux-portal.ts.

The portal owns both the capture and the virtual input devices; closing this process closes their session. The
station starts it only after someone opens the desktop, and a system dialog asks the desktop user to grant access.
"""
import json
import os
import struct
import sys
import threading
import time
import uuid
from collections import deque

try:
    import gi
    gi.require_version("Gst", "1.0")
    from gi.repository import Gio, GLib, Gst
except (ImportError, ValueError) as error:
    sys.stderr.write("Desktop portal dependencies unavailable: %s\n" % error)
    sys.exit(2)

BUS = "org.freedesktop.portal.Desktop"
PATH = "/org/freedesktop/portal/desktop"
REMOTE = "org.freedesktop.portal.RemoteDesktop"
CAST = "org.freedesktop.portal.ScreenCast"
REQUEST = "org.freedesktop.portal.Request"
SESSION = "org.freedesktop.portal.Session"
MAX_FRAME = 16 * 1024 * 1024
KEYSYM_DELAY_MS = 100
output_lock = threading.Lock()


def emit(kind, data):
    if isinstance(data, dict):
        data = json.dumps(data, separators=(",", ":")).encode()
    if len(data) > MAX_FRAME:
        raise ValueError("desktop frame is too large")
    with output_lock:
        sys.stdout.buffer.write(struct.pack(">BI", kind, len(data)))
        sys.stdout.buffer.write(data)
        sys.stdout.buffer.flush()


def status(kind, **values):
    emit(1, dict(type=kind, **values))


def insert_focused_text(value, stopped):
    """Insert composed Unicode into the focused accessible field, without reading its contents or changing the clipboard."""
    try:
        gi.require_version("Atspi", "2.0")
        from gi.repository import Atspi
        Atspi.init()
        Atspi.set_timeout(1000, 1000)
        queue = deque([Atspi.get_desktop(0)])
        deadline = time.monotonic() + 3
        seen = 0
        while queue and seen < 1500 and time.monotonic() < deadline and not stopped.is_set():
            element = queue.popleft()
            seen += 1
            try:
                state = element.get_state_set()
                if state and state.contains(Atspi.StateType.FOCUSED):
                    try:
                        editable = element.get_editable_text_iface()
                        text = element.get_text_iface()
                        if editable and text:
                            # Replacing a selection needs an atomic edit; do not delete it with a separate call.
                            if text.get_n_selections() != 0:
                                return False
                            caret = text.get_caret_offset()
                            if caret < 0 or stopped.is_set() or not element.get_state_set().contains(Atspi.StateType.FOCUSED):
                                return False
                            if not editable.insert_text(caret, value, len(value.encode("utf-8"))):
                                return False
                            try:
                                text.set_caret_offset(caret + len(value))
                            except GLib.Error:
                                pass
                            return True
                    except (GLib.Error, AttributeError):
                        pass
                count = min(200, element.get_child_count())
                queue.extend(element.get_child_at_index(index) for index in range(count))
            except (GLib.Error, AttributeError):
                pass
    except (ImportError, ValueError, GLib.Error):
        pass
    return False


class Portal:
    def __init__(self, session_bus=True):
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None) if session_bus else None
        self.session = None
        self.stream = None
        self.logical = None
        self.fd = None
        self.loop = GLib.MainLoop()
        self.pipeline = None
        self.buttons = set()
        self.keys = set()
        self.picture = None
        self.started = False
        self.last_sample = 0.0
        self.interval = 0.0
        self.inputs = deque()
        self.typing = False
        self.input_active = False
        self.stopped = threading.Event()

    def request(self, interface, method, signature, values):
        # Subscribe before the call: a fast backend is allowed to answer immediately.
        token = "sf_" + uuid.uuid4().hex
        values[-1]["handle_token"] = GLib.Variant("s", token)
        sender = self.bus.get_unique_name()[1:].replace(".", "_")
        path = "/org/freedesktop/portal/desktop/request/%s/%s" % (sender, token)
        loop = GLib.MainLoop()
        result = []

        def response(_bus, _sender, _path, _interface, _signal, parameters, _data):
            result.append(parameters.unpack())
            loop.quit()

        subscription = self.bus.signal_subscribe(BUS, REQUEST, "Response", path, None,
                                                  Gio.DBusSignalFlags.NONE, response, None)
        timer = None
        try:
            reply = self.bus.call_sync(BUS, PATH, interface, method, GLib.Variant(signature, tuple(values)),
                                       GLib.VariantType.new("(o)"), Gio.DBusCallFlags.NONE, 10000, None)
            if reply.unpack()[0] != path:
                raise RuntimeError("desktop portal returned an unexpected request")
            timer = GLib.timeout_add_seconds(120, lambda: (loop.quit(), False)[1])
            loop.run()
            if not result:
                self.bus.call(BUS, path, REQUEST, "Close", None, None, Gio.DBusCallFlags.NONE, -1, None, None, None)
                raise TimeoutError("desktop authorization timed out")
            code, data = result[0]
            if code:
                raise PermissionError("desktop authorization was cancelled" if code == 1 else "desktop authorization failed")
            return data
        finally:
            if timer is not None:
                GLib.source_remove(timer)
            self.bus.signal_unsubscribe(subscription)

    def prop(self, interface, name):
        reply = self.bus.call_sync(BUS, PATH, "org.freedesktop.DBus.Properties", "Get",
                                   GLib.Variant("(ss)", (interface, name)), GLib.VariantType.new("(v)"),
                                   Gio.DBusCallFlags.NONE, 5000, None)
        return reply.unpack()[0]

    def prepare(self):
        session_token = "sf_" + uuid.uuid4().hex
        created = self.request(REMOTE, "CreateSession", "(a{sv})", [
            {"session_handle_token": GLib.Variant("s", session_token)}])
        self.session = created["session_handle"]
        self.request(REMOTE, "SelectDevices", "(oa{sv})", [self.session, {"types": GLib.Variant("u", 3)}])
        options = {"types": GLib.Variant("u", 1), "multiple": GLib.Variant("b", False)}
        try:
            modes = self.prop(CAST, "AvailableCursorModes")
            if modes & 2:
                options["cursor_mode"] = GLib.Variant("u", 2)
        except GLib.Error:
            pass  # Older portals use their default cursor mode.
        self.request(CAST, "SelectSources", "(oa{sv})", [self.session, options])
        status("consent")
        started = self.request(REMOTE, "Start", "(osa{sv})", [self.session, "", {}])
        if started.get("devices", 0) & 3 != 3:
            raise PermissionError("desktop did not grant both keyboard and pointer (granted: %s)" % started.get("devices"))
        streams = started.get("streams", [])
        if len(streams) != 1:
            raise RuntimeError("desktop did not return a screen")
        self.stream, properties = streams[0]
        size = properties.get("size")
        if size and len(size) == 2 and size[0] > 0 and size[1] > 0:
            self.logical = tuple(size)
        reply, fds = self.bus.call_with_unix_fd_list_sync(
            BUS, PATH, CAST, "OpenPipeWireRemote", GLib.Variant("(oa{sv})", (self.session, {})),
            GLib.VariantType.new("(h)"), Gio.DBusCallFlags.NONE, 10000, None, None)
        self.fd = fds.get(reply.unpack()[0])
        self.bus.signal_subscribe(BUS, SESSION, "Closed", self.session, None, Gio.DBusSignalFlags.NONE,
                                  lambda *_args: self.stop(), None)
        status("ready", width=self.logical[0] if self.logical else 0, height=self.logical[1] if self.logical else 0)

    def start(self, command):
        if self.started:
            return
        self.started = True
        width = max(2, min(3840, int(command.get("maxWidth", 1920))))
        height = max(2, min(2160, int(command.get("maxHeight", 1080))))
        fps = max(1, min(15, int(command.get("fps", 15))))
        self.interval = 1.0 / fps
        if self.logical:
            scale = min(1, width / self.logical[0], height / self.logical[1])
            width = max(2, int(self.logical[0] * scale) // 2 * 2)
            height = max(2, int(self.logical[1] * scale) // 2 * 2)
            caps = "video/x-raw,width=%d,height=%d,pixel-aspect-ratio=1/1" % (width, height)
        else:
            caps = "video/x-raw,pixel-aspect-ratio=1/1"
        self.pipeline = Gst.parse_launch(self.capture_source() + " ! videoconvert ! videoscale ! "
                                         "%s ! jpegenc quality=75 ! "
                                         "appsink name=sink emit-signals=true sync=false max-buffers=1 drop=true" % caps)
        source = self.pipeline.get_by_name("source")
        self.configure_source(source)
        source.get_static_pad("src").add_probe(Gst.PadProbeType.BUFFER, self.pace)
        sink = self.pipeline.get_by_name("sink")
        sink.connect("new-sample", self.sample)
        bus = self.pipeline.get_bus()
        bus.add_signal_watch()
        bus.connect("message", self.message)
        if self.pipeline.set_state(Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE:
            raise RuntimeError("could not start the desktop stream")

    def capture_source(self):
        return "pipewiresrc name=source do-timestamp=true"

    def configure_source(self, source):
        source.set_property("fd", self.fd)
        source.set_property("path", str(self.stream))

    def pace(self, _pad, _info):
        # PipeWire screen streams may report 0/1 fps and buffers without a duration. In particular, old GStreamer
        # videorate versions cannot safely turn those into a fixed rate, so drop early without changing their caps.
        now = time.monotonic()
        if now - self.last_sample < self.interval:
            return Gst.PadProbeReturn.DROP
        self.last_sample = now
        return Gst.PadProbeReturn.OK

    def sample(self, sink):
        sample = sink.emit("pull-sample")
        if sample is None:
            return Gst.FlowReturn.EOS
        structure = sample.get_caps().get_structure(0)
        width, height = structure.get_value("width"), structure.get_value("height")
        if self.picture != (width, height):
            self.picture = (width, height)
            if not self.logical:
                self.logical = self.picture
            status("picture", width=width, height=height)
        buffer = sample.get_buffer()
        if buffer.get_size() > MAX_FRAME:
            GLib.idle_add(self.stop)
            return Gst.FlowReturn.ERROR
        try:
            emit(2, buffer.extract_dup(0, buffer.get_size()))
        except (BrokenPipeError, OSError):
            GLib.idle_add(self.stop)
            return Gst.FlowReturn.ERROR
        return Gst.FlowReturn.OK

    def message(self, _bus, message):
        if message.type == Gst.MessageType.ERROR:
            error, debug = message.parse_error()
            sys.stderr.write("desktop stream: %s (%s)\n" % (error, debug or "no details"))
            status("error", message=str(error))
            self.stop()
        elif message.type == Gst.MessageType.EOS:
            self.stop()

    def notify(self, method, signature, args, done=None):
        def completed(bus, result, _data):
            try:
                bus.call_finish(result)
                if done:
                    done()
            except GLib.Error as error:
                sys.stderr.write("desktop input: %s: %s\n" % (method, error))
                status("error", message="desktop input failed")
                self.stop()
        self.bus.call(BUS, PATH, REMOTE, method, GLib.Variant(signature, tuple([self.session, {}] + args)),
                      None, Gio.DBusCallFlags.NONE, -1, None, completed, None)

    def input(self, event):
        if (event.get("t") == "pointer" and event.get("kind") == "move" and self.inputs
                and self.inputs[-1].get("t") == "pointer" and self.inputs[-1].get("kind") == "move"
                and self.inputs[-1].get("buttons") == event.get("buttons")):
            self.inputs[-1] = event
        else:
            self.inputs.append(event)
        if not self.input_active:
            self.input_active = True
            self.drain_input()

    def drain_input(self):
        if self.typing:
            return False
        if not self.inputs:
            self.input_active = False
            return False
        event = self.inputs.popleft()
        if event.get("t") == "text" and event.get("text"):
            self.typing = True
            self.type_text(event["text"][:4096])
        else:
            self.deliver_input(event)
            # A compositor may otherwise see a queued press and release in the same dispatch and leave a key held.
            GLib.timeout_add(15, self.drain_input)
        return False

    def type_text(self, value):
        if all(ord(char) < 128 for char in value):
            self.type_character(value, 0)
            return

        def insert():
            try:
                inserted = insert_focused_text(value, self.stopped)
            except Exception as error:
                sys.stderr.write("desktop text input failed: %s\n" % type(error).__name__)
                inserted = False

            def finished():
                if self.stopped.is_set():
                    return False
                if not inserted:
                    status("input_error", code="textUnsupported")
                    self.stop()
                else:
                    self.typing = False
                    self.drain_input()
                return False

            GLib.idle_add(finished)

        threading.Thread(target=insert, daemon=True).start()

    def type_character(self, text, index, pressed=False):
        if not self.pipeline:
            self.typing = False
            return False
        if index >= len(text):
            self.typing = False
            self.drain_input()
            return False
        char = text[index]
        codepoint = ord(char)
        keysym = {"\n": 0xff0d, "\r": 0xff0d, "\t": 0xff09}.get(char, codepoint if codepoint < 256 else 0x01000000 | codepoint)
        # GNOME may temporarily remap one virtual key for keysyms outside the current layout. Let the target read
        # the press before releasing that mapping, then let it read the release before changing the mapping again.
        next_index = index + 1 if pressed else index
        self.notify("NotifyKeyboardKeysym", "(oa{sv}iu)", [keysym, 0 if pressed else 1],
                    lambda: GLib.timeout_add(KEYSYM_DELAY_MS, self.type_character, text, next_index, not pressed))
        return False

    def deliver_input(self, event):
        if not self.started or not self.logical:
            return
        kind = event.get("t")
        if kind in ("pointer", "wheel"):
            x = min(1.0, max(0.0, float(event.get("x", 0)))) * self.logical[0]
            y = min(1.0, max(0.0, float(event.get("y", 0)))) * self.logical[1]
            self.notify("NotifyPointerMotionAbsolute", "(oa{sv}udd)", [self.stream, x, y])
        if kind == "pointer":
            buttons = int(event.get("buttons", 0))
            for bit, code in ((1, 272), (2, 273), (4, 274)):
                down = bool(buttons & bit)
                if down != (code in self.buttons):
                    self.notify("NotifyPointerButton", "(oa{sv}iu)", [code, int(down)])
                    self.buttons.add(code) if down else self.buttons.discard(code)
        elif kind == "wheel":
            self.notify("NotifyPointerAxis", "(oa{sv}dd)", [float(event.get("dx", 0)), float(event.get("dy", 0))])
        elif kind == "key":
            keycode = event.get("keycode")
            if isinstance(keycode, int) and 0 < keycode < 768:
                down = event.get("kind") == "down"
                self.notify("NotifyKeyboardKeycode", "(oa{sv}iu)", [keycode, int(down)])
                self.keys.add(keycode) if down else self.keys.discard(keycode)

    def stop(self):
        self.stopped.set()
        if self.pipeline:
            self.pipeline.set_state(Gst.State.NULL)
            self.pipeline = None
        self.loop.quit()
        return False

    def close(self):
        self.stop()
        if self.session:
            self.bus.call(BUS, self.session, SESSION, "Close", None, None, Gio.DBusCallFlags.NONE, -1, None, None, None)
        if self.fd is not None:
            os.close(self.fd)

    def commands(self):
        def handle(command):
            try:
                if command.get("op") == "start":
                    self.start(command)
                elif command.get("op") == "input":
                    self.input(command.get("event", {}))
                elif command.get("op") == "close":
                    self.stop()
            except Exception as error:
                status("error", message=str(error))
                self.stop()
            return False

        for line in sys.stdin:
            try:
                GLib.idle_add(handle, json.loads(line))
            except ValueError:
                continue
        GLib.idle_add(self.stop)


def main():
    Gst.init(None)
    for element in ("pipewiresrc", "videoconvert", "videoscale", "jpegenc", "appsink"):
        if not Gst.ElementFactory.find(element):
            raise RuntimeError("missing GStreamer component: " + element)
    portal = Portal()
    try:
        portal.prepare()
        threading.Thread(target=portal.commands, daemon=True).start()
        portal.loop.run()
    finally:
        portal.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        status("error", message=str(error))
        sys.exit(1)
