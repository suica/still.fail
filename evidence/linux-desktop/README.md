# Linux Wayland desktop verification

These scripts exercised product commit `93b806e1c` on Ubuntu 22.04 with GNOME Shell 42.9 in isolated nested Wayland sessions. They are test evidence, not production code; the dialog coordinates are specific to this GNOME version and the test display.

- `gnome-portal-wire-combined.sh` uses the station's real screen handler and in-memory mesh transport. It checks the normal consent timeout and reopening, an 800 × 600 JPEG, pointer and key events, mixed `Hi!你好` text, and release of a held key and button on disconnect. It does not test a network connection or the still.fail client UI.
- `gnome-portal-selection-ready.sh` checks that selected GTK text is left untouched and reports an input error.
- `gnome-portal-vte-caps.sh` types `Hi! 123` into a real VTE terminal after enabling Caps Lock.

To reproduce, use a disposable directory with two checkouts of the product commit named `wayland-integration` and `linux-desktops` beside these files. Install station dependencies in the first checkout with the repository's pinned pnpm. Install Xvnc, GNOME Shell, a desktop portal, PipeWire with a session manager, Python GI/GTK 3/VTE/AT-SPI, GStreamer and xdotool. Then run:

```sh
bash gnome-portal-wire-combined.sh
TEST_INPUT=1 TEST_TEXT=1 TEST_SELECTION=1 bash gnome-portal-selection-ready.sh
TEST_INPUT=1 TEST_TEXT=1 bash gnome-portal-vte-caps.sh
```

The scripts start disposable displays and isolated D-Bus sessions; the last two use display `:251`, which must be free. They automate the system consent dialog and must not be pointed at a person's existing desktop. The wire test is adapted from the validation developed for PR #3591.
