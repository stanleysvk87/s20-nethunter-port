#!/system/bin/sh
set -eu

boot=/data/data/com.offsec.nethunter/scripts/bootkali_init
kill=/data/data/com.offsec.nethunter/scripts/killkali

sed -i 's/\$BUSYBOX mountpoint -q "\$MNT"/grep -q " \$MNT " \/proc\/self\/mountinfo/g' "$boot"
sed -i 's/\$BUSYBOX mountpoint -q "\$MNT"/grep -q " \$MNT " \/proc\/self\/mountinfo/g' "$kill"

grep -q 'grep -q " \$MNT " /proc/self/mountinfo' "$boot"
grep -q 'grep -q " \$MNT " /proc/self/mountinfo' "$kill"
