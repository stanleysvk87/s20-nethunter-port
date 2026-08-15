#!/system/bin/sh

log_file=/data/local/tmp/nethunter-ssh-once.log

for attempt in 1 2 3 4 5 6 7 8 9 10 11 12; do
    if /system/bin/bootkali ssh start >>"$log_file" 2>&1; then
        mv "$0" "$0.done"
        exit 0
    fi
    sleep 10
done

exit 1
