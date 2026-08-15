#!/system/bin/sh
# Keep Smart Dock as the secondary-display HOME (desktop icons), while the
# Android desktop shell owns windows, navigation and the taskbar.

LOG=/data/local/tmp/smartdock-hybrid.log
last_display=

log_msg() {
    echo "[$(date)] $*" >> "$LOG"
}

smartdock_overlay_height() {
    dumpsys window windows 2>/dev/null | awk -v display_id="$1" '
        /^  Window #[0-9]+ Window\{.*cu\.axel\.smartdock\}:$/ {
            in_smartdock = 1
            on_display = 0
            next
        }
        /^  Window #[0-9]+ Window\{/ {
            in_smartdock = 0
            on_display = 0
        }
        in_smartdock && $0 ~ "mDisplayId=" display_id {
            on_display = 1
        }
        in_smartdock && on_display && /mAttrs=.*fillx[0-9]+.*APPLICATION_OVERLAY/ {
            if (match($0, /fillx[0-9]+/)) {
                value = substr($0, RSTART + 5, RLENGTH - 5)
                print value
                exit
            }
        }
    '
}

log_msg "helper started"

while true; do
    if [ "$(getprop sys.boot_completed)" != "1" ] || \
       [ ! -d /data/user/0/cu.axel.smartdock ]; then
        sleep 5
        continue
    fi

    display_id=$(cmd display get-displays -i --type external 2>/dev/null | head -n 1)
    case "$display_id" in
        ''|*[!0-9]*)
            last_display=
            sleep 3
            continue
            ;;
    esac

    if [ "$display_id" != "$last_display" ]; then
        log_msg "external display $display_id connected; starting secondary HOME"
        am start --user 0 --display "$display_id" \
            -a android.intent.action.MAIN \
            -c android.intent.category.SECONDARY_HOME >/dev/null 2>&1
        last_display=$display_id
        sleep 3
    fi

    dock_height=$(smartdock_overlay_height "$display_id")
    if [ -n "$dock_height" ] && [ "$dock_height" -gt 10 ]; then
        size=$(wm size -d "$display_id" 2>/dev/null | awk -F': ' '/Physical size/{print $2; exit}')
        width=${size%x*}
        height=${size#*x}
        case "$width:$height" in
            *[!0-9:]*|:|*:) ;;
            *)
                # A downward gesture over Smart Dock always calls unpinDock();
                # unlike its pin button, this cannot toggle the wrong way.
                input touchscreen -d "$display_id" swipe \
                    "$((width / 2))" "$((height - 45))" \
                    "$((width / 2))" "$((height - 2))" 250
                log_msg "hid duplicate Smart Dock panel on display $display_id"
                sleep 2
                ;;
        esac
    fi

    sleep 3
done
