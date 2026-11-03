#!/bin/bash
set -eu
cd linux-desktops
mkdir -p ../gnome-test/runtime ../gnome-test/home
chmod 700 ../gnome-test/runtime
export TEST_ROOT="$PWD/../gnome-test"
runtime_link="/tmp/sf-gnome-$$"
ln -s "$TEST_ROOT/runtime" "$runtime_link"
export DISPLAY=:251 HOME="$TEST_ROOT/home" XDG_RUNTIME_DIR="$runtime_link" XDG_CURRENT_DESKTOP=GNOME GSETTINGS_BACKEND=memory
export GST_DEBUG="pipewiresrc:5,*:2" SF_PORTAL_DEBUG=1
export TEST_MODE="${TEST_MODE:-wayland}" TEST_INPUT="${TEST_INPUT:-0}" TEST_TEXT="${TEST_TEXT:-0}" TEST_ATSPI="${TEST_ATSPI:-0}" TEST_SELECTION="${TEST_SELECTION:-0}"
export XDG_SESSION_TYPE="$TEST_MODE" WAYLAND_DISPLAY=sf-test-wayland
export TEST_GEOM=1024x768
if [ "$TEST_MODE" = x11 ]; then unset WAYLAND_DISPLAY; export TEST_GEOM=800x600; fi
Xvnc "$DISPLAY" -localhost -rfbport -1 -SecurityTypes None -geometry "$TEST_GEOM" -depth 24 >"$TEST_ROOT/xvnc.log" 2>&1 & xp=$!
trap 'kill "$xp" 2>/dev/null || true; rm -f "$runtime_link"' EXIT
sleep 2
kill -0 "$xp"
dbus-run-session -- bash -c '
set -e
pipewire >"$TEST_ROOT/pipewire.log" 2>&1 & pp=$!
pipewire-media-session >"$TEST_ROOT/media-session.log" 2>&1 & mp=$!
if [ "$TEST_MODE" = wayland ]; then
  gnome-shell --nested --wayland --wayland-display=sf-test-wayland --no-x11 >"$TEST_ROOT/shell.log" 2>&1 & gp=$!
else
  unset WAYLAND_DISPLAY
  gnome-shell --x11 --display="$DISPLAY" >"$TEST_ROOT/shell.log" 2>&1 & gp=$!
fi
hp= ap=
cleanup() { kill "$ap" "$hp" "$gp" "$mp" "$pp" 2>/dev/null || true; }
trap cleanup EXIT
sleep 10
mkfifo "$TEST_ROOT/input.$$"
exec 3<>"$TEST_ROOT/input.$$"
/usr/bin/python3 -u station/src/screens/linux-portal.py <"$TEST_ROOT/input.$$" >"$TEST_ROOT/framed.bin" 2>"$TEST_ROOT/helper.log" & hp=$!
sleep 8
ffmpeg -hide_banner -loglevel error -y -f x11grab -video_size "$TEST_GEOM" -i "$DISPLAY" -frames:v 1 -threads 1 "$TEST_ROOT/before.png"
if [ "$TEST_MODE" = x11 ]; then toggle_x=579; toggle_y=342; share_x=604; share_y=144; else toggle_x=593; toggle_y=388; share_x=612; share_y=188; fi
xdotool mousemove --sync "$toggle_x" "$toggle_y" click 1
sleep 1
xdotool click 1
sleep 2
ffmpeg -hide_banner -loglevel error -y -f x11grab -video_size "$TEST_GEOM" -i "$DISPLAY" -frames:v 1 -threads 1 "$TEST_ROOT/after-toggle.png"
xdotool mousemove --sync "$share_x" "$share_y" click 1
sleep 5
printf "%s\n" "{\"op\":\"start\",\"maxWidth\":800,\"maxHeight\":600,\"fps\":10}" >&3
if [ "$TEST_INPUT" = 1 ]; then
  GDK_BACKEND="$TEST_MODE" /usr/bin/python3 "$TEST_ROOT/../gnome-input-target.py" >"$TEST_ROOT/target.log" 2>&1 & ap=$!
  sleep 3
  for _ in $(seq 1 60); do
    [ "$(wc -c < "$TEST_ROOT/framed.bin")" -gt 1000 ] && break
    xdotool mousemove_relative -- 1 0 || true
    sleep 0.2
  done
  printf "%s\n" "{\"op\":\"input\",\"event\":{\"t\":\"pointer\",\"x\":0.5,\"y\":0.5,\"buttons\":1}}" >&3
  printf "%s\n" "{\"op\":\"input\",\"event\":{\"t\":\"pointer\",\"x\":0.5,\"y\":0.5,\"buttons\":0}}" >&3
  printf "%s\n" "{\"op\":\"input\",\"event\":{\"t\":\"key\",\"keycode\":30,\"kind\":\"down\"}}" >&3
  printf "%s\n" "{\"op\":\"input\",\"event\":{\"t\":\"key\",\"keycode\":30,\"kind\":\"up\"}}" >&3
  if [ "$TEST_SELECTION" = 1 ]; then
    printf "%s\n" "{\"op\":\"input\",\"event\":{\"t\":\"key\",\"keycode\":29,\"kind\":\"down\"}}" >&3
    printf "%s\n" "{\"op\":\"input\",\"event\":{\"t\":\"key\",\"keycode\":30,\"kind\":\"down\"}}" >&3
    printf "%s\n" "{\"op\":\"input\",\"event\":{\"t\":\"key\",\"keycode\":30,\"kind\":\"up\"}}" >&3
    printf "%s\n" "{\"op\":\"input\",\"event\":{\"t\":\"key\",\"keycode\":29,\"kind\":\"up\"}}" >&3
  fi
  if [ "$TEST_TEXT" = 1 ]; then printf "%s\n" "{\"op\":\"input\",\"event\":{\"t\":\"text\",\"text\":\"你好\"}}" >&3; fi
  if [ "$TEST_ATSPI" = 1 ]; then sleep 1; /usr/bin/python3 "$TEST_ROOT/../atspi-input-probe.py"; fi
  sleep 7
  ffmpeg -hide_banner -loglevel error -y -f x11grab -video_size "$TEST_GEOM" -i "$DISPLAY" -frames:v 1 -threads 1 "$TEST_ROOT/input-target.png"
  cat "$TEST_ROOT/input-events.log"
  grep -q "button:1" "$TEST_ROOT/input-events.log"
  grep -q "text:a" "$TEST_ROOT/input-events.log"
  if [ "$TEST_SELECTION" = 1 ]; then ! grep -q "text:a你好" "$TEST_ROOT/input-events.log"; elif [ "$TEST_TEXT" = 1 ] || [ "$TEST_ATSPI" = 1 ]; then grep -q "text:a你好" "$TEST_ROOT/input-events.log"; fi
else
  sleep 6
fi
/usr/bin/python3 - "$TEST_ROOT/framed.bin" <<"PY"
import json, os, struct, sys
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
if not any(f.get("jpeg") for f in frames): sys.exit(1)
if os.environ.get("TEST_SELECTION") == "1" and not any(f.get("type") == "input_error" and f.get("code") == "textUnsupported" for f in frames): sys.exit(1)
PY
cat "$TEST_ROOT/helper.log"
rm -f "$TEST_ROOT/input.$$"
' 2>"$TEST_ROOT/dbus.log"
