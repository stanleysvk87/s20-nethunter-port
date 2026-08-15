#!/system/bin/sh
set -eu

boot=/data/data/com.offsec.nethunter/scripts/bootkali_init
kill=/data/data/com.offsec.nethunter/scripts/killkali

if ! grep -q 'mounted /sys/fs/cgroup' "$boot"; then
    sed -i '/mount -t sysfs sys "$MNT\/sys"/a\
\
    ######### BIND ANDROID CGROUP2 #########\
    mkdir -p "$MNT/sys/fs/cgroup"\
    $BUSYBOX mount -o bind /sys/fs/cgroup "$MNT/sys/fs/cgroup" \&\& bklog "[+] mounted /sys/fs/cgroup"' "$boot"
fi

sed -i 's/FS=(proc sys dev dev\/pts system sdcard)/FS=(proc sys sys\/fs\/cgroup dev dev\/pts system sdcard)/' "$boot"
sed -i 's/FS=(dev\/pts dev\/shm dev proc sys system sdcard)/FS=(dev\/pts dev\/shm dev proc sys\/fs\/cgroup sys system sdcard)/' "$kill"

grep -q 'mounted /sys/fs/cgroup' "$boot"
grep -q 'sys/fs/cgroup' "$kill"
