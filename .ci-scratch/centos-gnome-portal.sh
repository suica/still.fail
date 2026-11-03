#!/bin/bash
set -eu
export TEST_ROOT=/test/run
mkdir -p "$TEST_ROOT/runtime" "$TEST_ROOT/config" "$TEST_ROOT/cache" "$TEST_ROOT/data"
chmod 700 "$TEST_ROOT/runtime"
export XDG_RUNTIME_DIR="$TEST_ROOT/runtime" XDG_CURRENT_DESKTOP=GNOME GSETTINGS_BACKEND=memory
export XDG_CONFIG_HOME="$TEST_ROOT/config" XDG_CACHE_HOME="$TEST_ROOT/cache" XDG_DATA_HOME="$TEST_ROOT/data"
export XDG_SESSION_TYPE=wayland WAYLAND_DISPLAY=sf-test-wayland LIBGL_ALWAYS_SOFTWARE=1
dbus-run-session -- bash -c '
set -eu
pipewire >"$TEST_ROOT/pipewire.log" 2>&1 & pp=$!
wireplumber >"$TEST_ROOT/media-session.log" 2>&1 & mp=$!
gnome-shell --nested --wayland --wayland-display=sf-test-wayland --no-x11 >"$TEST_ROOT/shell.log" 2>&1 & gp=$!
tp= hp=
cleanup() { kill "$tp" "$hp" "$gp" "$mp" "$pp" 2>/dev/null || true; }
trap cleanup EXIT
sleep 12
kill -0 "$gp"
GDK_BACKEND=wayland /usr/bin/python3 -u /test/wayland-input-target.py >"$TEST_ROOT/target.log" 2>&1 & tp=$!
for _ in $(seq 1 120); do grep -q "^ready$" "$TEST_ROOT/target.log" && break; kill -0 "$tp"; sleep 0.1; done
grep -q "^ready$" "$TEST_ROOT/target.log"
mkfifo "$TEST_ROOT/input"
exec 3<>"$TEST_ROOT/input"
/usr/bin/python3 -u /test/linux-portal.py <"$TEST_ROOT/input" >"$TEST_ROOT/framed.bin" 2>"$TEST_ROOT/helper.log" & hp=$!
touch /test/consent-requested
sleep 15
printf "%s\n" "{\"op\":\"start\",\"maxWidth\":800,\"maxHeight\":600,\"fps\":10}" >&3
for _ in $(seq 1 200); do
  [ "$(wc -c < "$TEST_ROOT/framed.bin")" -gt 100 ] && break
  kill -0 "$hp"
  sleep 0.1
done
[ "$(wc -c < "$TEST_ROOT/framed.bin")" -gt 100 ]
printf "%s\n" "{\"op\":\"input\",\"event\":{\"t\":\"pointer\",\"kind\":\"down\",\"x\":0.5,\"y\":0.25,\"buttons\":1}}" >&3
printf "%s\n" "{\"op\":\"input\",\"event\":{\"t\":\"pointer\",\"kind\":\"up\",\"x\":0.5,\"y\":0.25,\"buttons\":0}}" >&3
for _ in $(seq 1 100); do grep -q entry-pressed "$TEST_ROOT/target.log" && break; sleep 0.1; done
grep -q entry-pressed "$TEST_ROOT/target.log"
printf "%s\n" "{\"op\":\"input\",\"event\":{\"t\":\"key\",\"keycode\":30,\"kind\":\"down\"}}" >&3
printf "%s\n" "{\"op\":\"input\",\"event\":{\"t\":\"key\",\"keycode\":30,\"kind\":\"up\"}}" >&3
for _ in $(seq 1 100); do grep -q text:a "$TEST_ROOT/target.log" && break; sleep 0.1; done
grep -q text:a "$TEST_ROOT/target.log"
printf "%s\n" "{\"op\":\"input\",\"event\":{\"t\":\"pointer\",\"kind\":\"down\",\"x\":0.5,\"y\":0.75,\"buttons\":1}}" >&3
printf "%s\n" "{\"op\":\"input\",\"event\":{\"t\":\"pointer\",\"kind\":\"up\",\"x\":0.5,\"y\":0.75,\"buttons\":0}}" >&3
for _ in $(seq 1 100); do grep -q clicked "$TEST_ROOT/target.log" && break; sleep 0.1; done
grep -q clicked "$TEST_ROOT/target.log"
printf "%s\n" "{\"op\":\"close\"}" >&3
wait "$hp"
hp=
cat "$TEST_ROOT/target.log"
/usr/bin/python3 - "$TEST_ROOT/framed.bin" <<"PY"
import json, struct, sys
frames = []
with open(sys.argv[1], "rb") as f:
    while True:
        header = f.read(5)
        if len(header) != 5: break
        kind, size = struct.unpack(">BI", header)
        payload = f.read(size)
        if len(payload) != size: break
        frames.append(json.loads(payload) if kind == 1 else {"frame": len(payload), "jpeg": payload[:2] == b"\xff\xd8"})
print(frames[:8])
assert any(f.get("jpeg") for f in frames), "no JPEG frame"
PY
' 2>"$TEST_ROOT/dbus.log"
