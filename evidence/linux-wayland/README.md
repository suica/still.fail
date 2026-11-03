# Wayland screen-wire verification

The check was run against feature commit `a882f242c0a1c9fce793a99efef449bdb57384dc` on Ubuntu 22.04, with GNOME Shell 42.9 in an isolated nested Wayland session. It uses the station's in-memory mesh transport and real screen handler, portal helper, PipeWire stream, and a GTK target. It does not test the network transport or a still.fail client UI.

The test opens a view and waits through the normal four-second consent timeout. After the desktop dialog is accepted it reopens the view, checks an 800 × 600 JPEG screen-wire frame, sends pointer and keyboard events, and verifies the GTK target received them. It then disconnects while a key and button are down and verifies both releases.

To repeat it, make an isolated test directory containing a checkout of the feature branch named `wayland-integration`, install the station dependencies with its pinned pnpm version, and put the three accompanying files in the parent directory. Install the GNOME, Xvnc, PipeWire, GStreamer, Python GObject/GTK 3, `xdotool`, and D-Bus tools required by the script, then run `bash gnome-portal-wire.sh`. The script starts a nested desktop on a new virtual display; its portal-dialog coordinates match the 1024 × 768 test display and this GNOME version.

Result: the screen handler reported pending consent, returned a JPEG after authorization, delivered the pointer click and `a` key to the GTK target, and released a held `b` key and mouse button on disconnect.
