#!/usr/bin/env bash
set -e

# Start MPV daemon with youtube-dl options in background
nohup mpv --no-video --idle=yes --input-ipc-server="$XDG_RUNTIME_DIR/mpv.sock" --ytdl --ytdl-raw-options=mark-watched=,cookies-from-browser=firefox > mpv.log 2>&1 &
MPV_PID=$!

# Give MPV time to create the socket
sleep 1

# Run the Python controller in foreground
python kiosk.py

# Cleanup MPV on exit
trap 'kill $MPV_PID 2>/dev/null' EXIT
