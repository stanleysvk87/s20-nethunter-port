#!/usr/bin/env bash

# Start a detached, read-only 24-hour S20 reboot monitor on OPI.

set -euo pipefail

session_name=s20-watch-24h
runtime=${S20_MONITOR_RUNTIME:-24h}
monitor_script=/home/stanley/s20ultra-lineage/nethunter-kernel-port/watch-s20-reboots.sh
output_dir=/home/stanley/s20-reboot-monitor
metadata_log="$output_dir/monitor-meta.log"

mkdir -p "$output_dir"

if tmux has-session -t "$session_name" 2>/dev/null; then
    printf 'Monitor is already running in tmux session %s.\n' "$session_name"
    exit 0
fi

started_at=$(date --iso-8601=seconds)
expected_end=$(date --iso-8601=seconds --date='+24 hours')
printf '%s START session=%s runtime=%s expected_end=%s\n' \
    "$started_at" "$session_name" "$runtime" "$expected_end" >>"$metadata_log"

tmux new-session -d -s "$session_name" -n state \
    "timeout --signal=TERM --kill-after=10s '$runtime' bash '$monitor_script' state '$output_dir'"
tmux new-window -d -t "$session_name" -n dmesg \
    "timeout --signal=TERM --kill-after=10s '$runtime' bash '$monitor_script' dmesg '$output_dir'"

printf 'Started %s; expected end %s.\n' "$session_name" "$expected_end"
printf 'Logs: %s\n' "$output_dir"

