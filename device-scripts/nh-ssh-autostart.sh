#!/system/bin/sh
# Autostart NetHunter sshd on boot (Magisk late_start service).
# Uses the NetHunter app's own official entrypoint (mounts the chroot fs
# THEN starts ssh) instead of a raw chroot - a raw chroot without the
# bootkali_init mount step (bind /proc,/dev,/sys,/system,sdcard into the
# chroot) leaves sshd unable to start correctly on a cold boot where the
# NetHunter app was never opened. See build-note 2026-08-10.
#
# /data/data/com.offsec.nethunter is CE-encrypted (File-Based Encryption) -
# it does not exist until the phone has been unlocked at least once after
# boot, and that unlock is a human action (PIN/biometric) with no fixed
# time bound. A fixed timeout here (previous version: 300s) gives up
# before the phone owner gets around to unlocking, which is exactly what
# happened on two reboots on 2026-08-10 (unlock came ~25-30 min after
# boot, well past the old 5-minute cutoff). Poll indefinitely instead -
# this is a lightweight background loop (2s sleep), the cost of waiting
# longer is negligible compared to silently giving up.
LOG=/data/local/tmp/nh-ssh-autostart.log
echo "[$(date)] boot autostart fired" >> "$LOG"

while [ ! -x /data/data/com.offsec.nethunter/scripts/bootkali ]; do
    sleep 2
done

echo "[$(date)] bootkali path ready, starting ssh" >> "$LOG"
/system/bin/sh /data/data/com.offsec.nethunter/scripts/bootkali ssh start >> "$LOG" 2>&1
echo "[$(date)] bootkali ssh start exit=$?" >> "$LOG"

# Unconditional fallback: "bootkali ssh start" runs `service ssh start`
# inside the chroot, which on this Debian/Kali rootfs redirects through
# systemctl whenever /run/systemd/system exists there (init-functions.d/
# 40-systemd, and confirmed this also affects calling /etc/init.d/ssh start
# directly - the redirect lives in the sourced init-functions, not in a
# particular entrypoint). systemctl then detects it's inside a chroot and
# silently no-ops WITHOUT starting sshd, yet still exits 0 -
# "bootkali ssh start exit=0" alone does NOT prove sshd is listening. Seen
# live 2026-08-14: a stray /run/systemd/system dir (leftover from faking
# sd_booted() for a gnome-session experiment) caused this exact silent
# no-op on every subsequent boot until removed by hand.
#
# Rather than verify first (pgrep through busybox's chroot proved
# unreliable here - likely /proc visibility with hidepid across the chroot
# boundary) just always invoke the raw /usr/sbin/sshd binary too, bypassing
# service/systemctl/init.d entirely. If bootkali's path already started it,
# this second call simply fails to bind the in-use port and exits
# immediately - harmless. If bootkali's path silently no-op'd, this is the
# call that actually starts it.
. /data/data/com.offsec.nethunter/scripts/bootkali_env
if [ -n "$BUSYBOX" ] && [ -n "$MNT" ]; then
    echo "[$(date)] also starting /usr/sbin/sshd directly (idempotent)" >> "$LOG"
    $BUSYBOX chroot "$MNT" /usr/sbin/sshd >> "$LOG" 2>&1
    echo "[$(date)] direct sshd start exit=$?" >> "$LOG"
fi
