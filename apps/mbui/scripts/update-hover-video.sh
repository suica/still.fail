#!/bin/bash
set -euo pipefail

# Run under Xvfb on CI. This is the native app's fixture over made-up data; no user's account or messages are used.
app="apps/mbui/mbui/out/linux/app/_build/native/release/build/stillfail/sffix/sffix.exe"
out="${RUNNER_TEMP:?}/hover-evidence"
mkdir -p "$out"
export GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1
MBUI_BENCH=-1 MBUI_WIN=1280x820 MBUI_FIXTURE=chat MBUI_UPDATE=0.1.9999 MBUI_UPDATE_READY=1 "$app" > "$out/app.log" 2>&1 &
app_pid=$!
cleanup() { kill "$app_pid" 2>/dev/null || true; }
trap cleanup EXIT
window_id=$(timeout 60 xdotool search --sync --onlyvisible --name 'still.fail' | head -1)
xdotool windowmove "$window_id" 0 0
xdotool getwindowgeometry --shell "$window_id" > "$out/window.txt"
xdotool mousemove --window "$window_id" 600 180

# The first part enters update from blank space; the second moves from new chat to update; the third selects new chat.
# x11grab includes the real pointer. The crop only magnifies the sidebar, not its contents.
ffmpeg -nostdin -loglevel error -y -f x11grab -framerate 40 -draw_mouse 1 -video_size 1280x820 \
  -i "$DISPLAY.0+0,0" -t 18 -vf 'crop=600:320:0:0,scale=1200:640' \
  -c:v libx264 -preset ultrafast -crf 21 -pix_fmt yuv420p "$out/hover.mp4" > "$out/ffmpeg.log" 2>&1 &
record_pid=$!
sleep 2
xdotool mousemove --window "$window_id" 236 30
sleep 2
xdotool mousemove --window "$window_id" 600 180
sleep 1
xdotool mousemove --window "$window_id" 130 30
sleep 2
xdotool mousemove --window "$window_id" 236 30
sleep 2
xdotool mousemove --window "$window_id" 130 30 click 1
sleep 2
xdotool mousemove --window "$window_id" 236 30
sleep 2
xdotool mousemove --window "$window_id" 600 180
wait "$record_pid"
ffprobe -v error -show_entries format=duration,size -show_entries stream=width,height,r_frame_rate -of default=noprint_wrappers=1 "$out/hover.mp4" > "$out/video-info.txt"
for moment in 1 3 6 8 10 12 14 16; do
  ffmpeg -nostdin -loglevel error -y -ss "$moment" -i "$out/hover.mp4" -frames:v 1 "$out/frame-$moment.png"
done
