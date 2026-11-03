#!/bin/bash
set -eu
cd wayland-integration
export TEST_ROOT="$PWD/../gnome-wire-$$"
mkdir -p "$TEST_ROOT/runtime" "$TEST_ROOT/config" "$TEST_ROOT/cache" "$TEST_ROOT/data"
chmod 700 "$TEST_ROOT/runtime"
printf '%s\n' "$TEST_ROOT" > ../gnome-wire-path
runtime_link="/tmp/sf-gnome-wire-$$"
ln -s "$TEST_ROOT/runtime" "$runtime_link"
export XDG_RUNTIME_DIR="$runtime_link" XDG_CURRENT_DESKTOP=GNOME GSETTINGS_BACKEND=memory
export XDG_CONFIG_HOME="$TEST_ROOT/config" XDG_CACHE_HOME="$TEST_ROOT/cache" XDG_DATA_HOME="$TEST_ROOT/data"
export XDG_SESSION_TYPE=wayland WAYLAND_DISPLAY=sf-test-wayland
Xvnc -displayfd 3 -localhost -rfbport -1 -SecurityTypes None -geometry 1024x768 -depth 24 3>"$TEST_ROOT/display" >"$TEST_ROOT/xvnc.log" 2>&1 & xp=$!
trap 'kill "$xp" 2>/dev/null || true; rm -f "$runtime_link"' EXIT
for _ in $(seq 1 50); do [ -s "$TEST_ROOT/display" ] && break; kill -0 "$xp"; sleep 0.1; done
kill -0 "$xp"
[ -s "$TEST_ROOT/display" ]
export DISPLAY=":$(cat "$TEST_ROOT/display")"
dbus-run-session -- bash -c '
set -eu
pipewire >"$TEST_ROOT/pipewire.log" 2>&1 & pp=$!
pipewire-media-session >"$TEST_ROOT/media-session.log" 2>&1 & mp=$!
gnome-shell --nested --wayland --wayland-display=sf-test-wayland --no-x11 >"$TEST_ROOT/shell.log" 2>&1 & gp=$!
tp= np=
cleanup() { kill "$tp" "$np" "$gp" "$mp" "$pp" 2>/dev/null || true; }
trap cleanup EXIT
sleep 10
GDK_BACKEND=wayland /usr/bin/python3 -u ../wayland-input-target.py >"$TEST_ROOT/target.log" 2>&1 & tp=$!
for _ in $(seq 1 100); do grep -q "^ready$" "$TEST_ROOT/target.log" && break; kill -0 "$tp"; sleep 0.1; done
grep -q "^ready$" "$TEST_ROOT/target.log"
cp ../wayland-wire-combined.test.ts station/test/wayland-wire-combined.test.ts
(cd station && node --import ./test/setup-env.mjs --test test/wayland-wire-combined.test.ts) >"$TEST_ROOT/node.log" 2>&1 & np=$!
sleep 8
xdotool mousemove --sync 593 388 click 1
sleep 1
xdotool click 1
sleep 2
xdotool mousemove --sync 612 188 click 1
while kill -0 "$np" 2>/dev/null; do xdotool mousemove_relative -- 1 0 || true; sleep 0.3; done
result=0
wait "$np" || result=$?
np=
cat "$TEST_ROOT/node.log"
cat "$TEST_ROOT/target.log"
exit "$result"
' 2>"$TEST_ROOT/dbus.log"
