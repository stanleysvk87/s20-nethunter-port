#!/system/bin/sh
set -eu

mnt=/data/local/nhsystem/kali-arm64
bb=/data/adb/magisk/busybox

for rel in dev/pts dev/shm dev/binderfs sdcard system proc sys dev; do
    target="$mnt/$rel"
    while grep -q " $target " /proc/self/mountinfo; do
        "$bb" umount "$target"
    done
done

while grep -q " $mnt " /proc/self/mountinfo; do
    "$bb" umount "$mnt"
done

before=$(grep -c " $mnt" /proc/self/mountinfo || true)
echo "MOUNTS_BEFORE_START=$before"
[ "$before" -eq 0 ]

/system/bin/bootkali_init

roots=$(grep -c " $mnt " /proc/self/mountinfo || true)
echo "ROOT_MOUNT_COUNT=$roots"
[ "$roots" -eq 1 ]
