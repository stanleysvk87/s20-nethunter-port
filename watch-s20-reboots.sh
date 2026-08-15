#!/usr/bin/env bash

# Read-only S20 reboot monitor. It never changes phone state: it only pings,
# opens key-authenticated SSH sessions, and copies kernel/Android logs to OPI.

set -uo pipefail

mode=${1:?usage: watch-s20-reboots.sh state|dmesg [output-dir]}
output_dir=${2:-/home/stanley/s20ultra-lineage/nethunter-kernel-port/artifacts/reboot-monitor-20260810}
lan_address=10.30.0.156
tail_address=100.73.181.56
interval_seconds=30

mkdir -p "$output_dir"
log_file="$output_dir/$mode.log"
ssh_options=(
    -o BatchMode=yes
    -o ConnectTimeout=5
    -o ConnectionAttempts=1
    -o ServerAliveInterval=10
    -o ServerAliveCountMax=2
)

log_line() {
    printf '%s %s\n' "$(date --iso-8601=seconds)" "$*" >>"$log_file"
}

select_ssh_host() {
    local address
    for address in "$lan_address" "$tail_address"; do
        if timeout 8 ssh "${ssh_options[@]}" "root@$address" true >/dev/null 2>&1; then
            printf '%s\n' "$address"
            return 0
        fi
    done
    return 1
}

watch_state() {
    local last_boot_id=""
    local address snapshot boot_id uptime kernel lan_state tail_state event

    log_line "MONITOR_START interval=${interval_seconds}s lan=$lan_address tail=$tail_address"
    while true; do
        lan_state=down
        tail_state=down
        ping -c 1 -W 2 "$lan_address" >/dev/null 2>&1 && lan_state=up
        ping -c 1 -W 2 "$tail_address" >/dev/null 2>&1 && tail_state=up

        address=""
        snapshot=""
        if address=$(select_ssh_host); then
            snapshot=$(timeout 8 ssh "${ssh_options[@]}" "root@$address" \
                'printf "%s " "$(cat /proc/sys/kernel/random/boot_id)"; printf "%s " "$(cut -d" " -f1 /proc/uptime)"; uname -r' \
                2>/dev/null || true)
        fi

        if [[ -n "$snapshot" ]]; then
            read -r boot_id uptime kernel <<<"$snapshot"
            event=""
            if [[ -z "$last_boot_id" ]]; then
                event="BOOT_OBSERVED"
            elif [[ "$boot_id" != "$last_boot_id" ]]; then
                event="REBOOT_DETECTED previous=$last_boot_id new=$boot_id"
            fi

            log_line "STATE lan=$lan_state tail=$tail_state ssh=up via=$address boot_id=$boot_id uptime_s=$uptime kernel=$kernel ${event}"

            if [[ "$boot_id" != "$last_boot_id" ]]; then
                timeout 12 ssh "${ssh_options[@]}" "root@$address" \
                    'dmesg --color=never 2>/dev/null' \
                    >"$output_dir/boot-$boot_id-dmesg.log" 2>&1 || true
                timeout 12 ssh "${ssh_options[@]}" "root@$address" \
                    'tar -C /sys/fs/pstore -cf - . 2>/dev/null' \
                    >"$output_dir/boot-$boot_id-pstore.tar" 2>/dev/null || true
            fi
            last_boot_id=$boot_id
        else
            log_line "STATE lan=$lan_state tail=$tail_state ssh=down last_boot_id=${last_boot_id:-unknown}"
        fi

        sleep "$interval_seconds"
    done
}

watch_stream() {
    local stream=$1
    local address remote_command status

    case "$stream" in
        dmesg) remote_command='dmesg --follow-new --color=never' ;;
        *) return 2 ;;
    esac

    log_line "MONITOR_START stream=$stream lan=$lan_address tail=$tail_address"
    while true; do
        if ! address=$(select_ssh_host); then
            log_line "STREAM_WAIT ssh=down"
            sleep 10
            continue
        fi

        log_line "STREAM_CONNECT via=$address"
        set +e
        timeout 86400 ssh "${ssh_options[@]}" "root@$address" "$remote_command" 2>&1 |
            while IFS= read -r line; do
                log_line "$line"
            done
        status=${PIPESTATUS[0]}
        set -e
        log_line "STREAM_DISCONNECT via=$address status=$status"
        sleep 5
    done
}

case "$mode" in
    state) watch_state ;;
    dmesg) watch_stream "$mode" ;;
    *) printf 'unknown mode: %s\n' "$mode" >&2; exit 2 ;;
esac
