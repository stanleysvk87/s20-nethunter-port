# Galaxy S20 Ultra z3s NetHunter kernel port + Linux handheld

Target device and ROM:

- Samsung Galaxy S20 Ultra 5G Exynos (`SM-G988B`, `z3s`)
- LineageOS 23.2 / Android 16
- Lineage kernel commit `88a015858b05`

`z3s` has no official NetHunter support — Kali's own reference kernel target
is the Note20 Ultra Exynos 990 (`c2s`). A NetHunter kernel for this exact
chip did exist before ([WhimsyGiga/Samsung-S20-ultra-exynos-nethunter-kernel](https://github.com/WhimsyGiga/Samsung-S20-ultra-exynos-nethunter-kernel)),
but it targets Android 13, flashes via TWRP rather than Magisk, and its own
README lists only partial functionality (Bluetooth with caveats, one tested
Wi-Fi adapter, USB Arsenal not working). People running the current
LineageOS 23 / Android 16 branch on this device have publicly asked for a
working NetHunter kernel for their version and not found one (see the XDA
LineageOS-21-for-z3s thread). This repo picks that gap up for the current
OS branch: a from-scratch kernel port validated with checksums for every
build, Magisk-based (not TWRP), plus a full "Linux handheld" build on top
of it — native Kali NetHunter chroot, a working Android desktop-hybrid mode
driving an external monitor (which nothing published elsewhere for this
device combines with the rest), USB HID/ADB/serial gadget, and remote SSH
access.

> **Safety note**: flashing a pre-built `boot.img` from this repo onto a
> *different* `z3s` unit or a different LineageOS/ROM build is not
> automatically safe. Boot images are tied to the exact ramdisk, DTB and
> partition layout validated here. Re-validate before flashing, keep the
> stock rollback images, and never flash the `c2s` reference kernel — it is
> for a different SoC revision and is included here only as a comparison
> reference, not as something to flash.

This repo intentionally excludes two large, non-original directories that
were part of the working build tree: the official `c2s` reference kernel
source (~3.6 GB, third-party, get it from Kali NetHunter's own repos if you
need it) and the full set of built kernel `Image`/`boot.img` binaries
(~3.3 GB total, 45-62 MB each — over GitHub's 100 MB file limit anyway).
What's here is the actual original work: build scripts, the Docker build
environment, chroot/module patches, on-device automation scripts, and the
exact checksums of every artifact that was built and flashed, so the build
is fully reproducible.

The `lineage-kernel/` tree is the exact source revision used by the installed
LineageOS build. The official NetHunter Exynos 990 kernel reference for the
Note20 Ultra must never be flashed directly on `z3s`.

`running.config.gz` was read from the running phone and is used to prove that
the unmodified source builds before any NetHunter changes are introduced.

Build the reusable container and baseline kernel:

```bash
docker build -t s20-z3s-kernel-builder:ubuntu22.04 .
./build-baseline.sh
```

Run CPU-heavy builds on `victus` (`mjolnir-lan`), not on `opi`. The verified
build used Docker with `KERNEL_JOBS=8` on Victus.

Build the first NetHunter feature kernel after the baseline succeeds:

```bash
KERNEL_JOBS=8 ./build-nethunter.sh
```

This enables ConfigFS HID, USB monitoring, Bluetooth RFCOMM, common external
USB Wi-Fi drivers with mac80211, and container networking. Internal BCM4375B1
monitor mode is a separate driver and firmware port and is not implied by this
first feature build.

Flashing is intentionally outside these scripts. A build artifact is not safe
to flash until its kernel, DTB, DTBO, boot image layout, and rollback images
have all been validated for `z3s`.

## Downloads

Pre-built, flashed-and-validated boot images are attached to the
[GitHub Releases](https://github.com/stanleysvk87/s20-nethunter-port/releases)
page (each 45-62 MB, over GitHub's 100 MB git-blob limit, so they're release
assets rather than tracked files):

- `boot-z3s-dexfix-RUNNING.img` — the build currently flashed and running on
  the phone (`659f32a1c5351b5bc4b97a7f4eb1b0f4835b965ad63a4d8dee9544ffb9ffdb12`).
- `boot-z3s-lineage23.2-nethunter-config-only.img` /
  `boot-z3s-lineage23.2-nethunter-magisk-v30.7.img` — the two intermediate,
  individually-validated milestones described below.
- `stock-boot.img` / `stock-dtbo.img` / `stock-vbmeta.img` — the original
  images pulled from this exact phone before any modification, for rollback.

Read the safety note at the top of this file before flashing any of these.

## Kernel build variants

The kernel went through several incremental builds after the initial
config-only baseline, each fixing one concrete bug found on-device. All of
them use the same Docker builder image and firmware inputs
(`firmware/`, SHA-256-checked by each build script):

- `build-bt-hcisock-fix.sh` — `net/bluetooth/hci_sock.c` had
  `hci_sock_create/bind/release/ioctl/getname` wrapped in `#if 0` with a
  stray `return 0` fallback (`hci_sock_create` never called `sk_alloc`),
  crashing on any `hciconfig` use. Restored.
- `build-bt-eventfilter-fix.sh` — `bredr_setup()` sent
  `HCI_OP_SET_EVENT_FLT`, which the CSR8510 dongle used for testing doesn't
  support ("Unknown HCI Command"); the kernel treated the response as
  fatal. Removed the redundant command.
- `build-ncm-fix.sh` — fixed 3 NULL-pointer dereferences in `f_ncm.c`
  (USB NCM/network gadget). The remaining blocker for `adb`+`rndis`
  together is an Android framework policy decision
  (`UsbService.setCurrentFunctions` explicitly rejects that combination),
  not a kernel bug — tracked as still open.
- `build-dex-repeater-fix.sh` — the variant currently flashed and running
  (`uname -r` reports `...st10-nh-z3s-dexfix-...`).
- `build-final-consolidated.sh` — combines the verified fixes into one
  kernel.

## Verified config-only build

The config-only kernel was built successfully on Victus and copied to
`artifacts/config-only/`. Its enabled feature set includes ConfigFS HID,
Bluetooth RFCOMM, USB monitoring, `mac80211`, `ath9k_htc`, `rtl8187`,
`rtl8xxxu`, bridge networking, and the Netfilter `addrtype` match.

`artifacts/boot-z3s-lineage23.2-nethunter-config-only.img` contains only the
new kernel. MagiskBoot v30.7 was used to preserve the stock LineageOS ramdisk,
the device-specific embedded DTB, boot header, and image size. A second unpack
verified all three components byte-for-byte.

Important artifacts and SHA-256 values:

```text
stock/boot.img
0ef4c3df3e0eab6a19b51a5c2f76caf769e12ab1434e66631561cc484a63aaa6

config-only/Image
2b1a8c36c63430a77714caeb2c01b17e9f9b1e2b571a5fe1fe898352e2c3c521

boot-z3s-lineage23.2-nethunter-config-only.img
17fa504a7dd9b64b43b325c565fdbf46da6d8595755e22f1c46814cf163047bf
```

The config-only image was flashed to `boot` after explicit confirmation on
2026-08-09. The phone completed Android boot with kernel
`4.19.325-cip126-st10-nethunter-z3s-g88a015858b05`. Runtime checks passed for
Wi-Fi connectivity, Bluetooth, ADB, core Android services, and every expected
kernel config symbol. Only `boot` was changed; stock `boot.img`, `dtbo.img`,
and `vbmeta.img` remain under `artifacts/stock/` for rollback.

## Magisk and NetHunter installation

Magisk v30.7 was installed by patching the already verified config-only boot
image. The resulting image preserves the Lineage ramdisk and the validated
NetHunter feature kernel:

```text
boot-z3s-lineage23.2-nethunter-magisk-v30.7.img
cb172c56727c4418fa378ca43c2a4fd59a0d12509d4ff5f6dd6c8cd0103e5910
```

The phone booted successfully with Magisk root. Android initially boots with
SELinux Enforcing, but launching NetHunter 2026.2 deliberately runs
`setenforce 0` and changes it to Permissive for NetHunter compatibility. The
active kernel remains:

```text
4.19.325-cip126-st10-nethunter-z3s-g88a015858b05
```

The official Kali 2026.2 generic ARM64 full package was installed as a Magisk
module. It contains no replacement kernel, so the validated `z3s` boot image
remains in use.

```text
kali-nethunter-2026.2-generic-arm64-full.zip
b09756fab7939092bcf7c6242c360022426aa85b435a3285daee36a608bf8880
```

The active module is `/data/adb/modules/nethunter` version 1.4.0. The native
full chroot is `/data/local/nhsystem/kali-arm64`, with `kalifs` pointing to it.
The older Termux rootless environment under the Termux app data is untouched.

Two more chroot fixes are applied directly against the NetHunter app's own
scripts (`bootkali_init`/`killkali` under its private, CE-encrypted storage,
not the Magisk module itself — hence idempotent sed-based fixup scripts
rather than a source patch against files that can't be packaged ahead of
time):

- `module-fixes/fix-nethunter-mount-detection.sh` — the app's own mount
  check (`busybox mountpoint -q "$MNT"`) reports false negatives in this
  environment; replaced with a direct `/proc/self/mountinfo` grep. Confirmed
  live and correct via `restart-nethunter-clean-v2.sh`, a verification
  script that force-unmounts everything, asserts a clean state, restarts
  the chroot, and asserts exactly one root mount afterward.
- `module-fixes/add-nethunter-cgroup-mount.sh` — binds Android's
  `/sys/fs/cgroup` (cgroup2) into the chroot at the same path, needed for
  any container runtime (Docker/Podman) run inside the Kali chroot.

An earlier attempt at the mount-detection problem (bind-mounting the chroot
root to itself so `mountpoint -q` would recognize it) was superseded by the
`/proc/self/mountinfo` approach above — the working version is what's in
this repo.

LineageOS mounts `/system/xbin` with permissions that prevent the NetHunter app
UID from traversing the module's original BusyBox symlink. The persistent fix
in `module-fixes/post-fs-data.sh` also exposes a relative BusyBox hardlink under
`/system/bin`, which is executable by the app. Its SHA-256 is:

```text
aa28e38c8785bef34852502456d29a300d822d1d4bf9d5eca25ea8c175552815
```

Reinstalling or updating the NetHunter Magisk module may overwrite this script.
Reapply the local fix and reboot if the app reports that `busybox_nh` is missing.

## Runtime validation

Validated on the phone:

- NetHunter 2026.2 app starts with root and all-files access.
- NetHunter Terminal opens the native chroot as `root@kali`; its Magisk
  superuser policy is persistent.
- NetHunter KeX 5.2.5 client launches. A KeX server password is deliberately
  not preconfigured because it must be known by the user.
- Native Kali 2026.2 ARM64 chroot mounts `/dev`, `/proc`, `/sys`, `/system`,
  binderfs, and shared storage.
- Nmap, Metasploit, `iw`, OpenSSH, package repositories, DNS, and outbound
  networking work inside the chroot.
- The chroot sees Android network interfaces, including `wlan0` and `wlan1`.
- ConfigFS, HID gadget support, USB monitoring, Bluetooth RFCOMM, and the
  selected external USB Wi-Fi drivers are enabled in the running kernel.
- Wi-Fi, Bluetooth, ADB, Magisk root, and normal Android boot survive reboots.

The OPI public key is installed for native Kali root SSH. SSH is restricted to
public-key authentication by
`module-fixes/99-nethunter-handheld.conf`; password and keyboard-interactive
login are disabled. The OPI SSH alias is `s20-kali` on port 22. Start the
service from NetHunter or with `bootkali ssh start` when needed.

## Known limits

- The internal Broadcom PHY advertises managed, AP, and P2P modes, but not
  monitor mode. Internal Wi-Fi monitor/injection is therefore not functional.
- External monitor/injection needs a supported USB adapter and was not tested
  because no adapter was attached. The kernel includes `ath9k_htc`, `rtl8187`,
  and `rtl8xxxu`.
- Standard ConfigFS HID support is present, but USB Arsenal/HID was not switched
  live because doing so would disconnect the only ADB control path. Samsung
  gadget compatibility beyond standard ConfigFS remains unverified.
- Bluetooth RFCOMM and USB Bluetooth drivers are present, but Bluetooth Arsenal
  attacks requiring specific external hardware were not tested.
- Opening the NetHunter app changes SELinux from Enforcing to Permissive. This
  improves compatibility with offensive tooling but weakens Android process
  isolation. `setenforce 1` restores Enforcing until NetHunter changes it again
  or the phone reboots.
- Kali rolling's `systemd-machine-id-setup` from systemd 261 expects
  `STATX_MNT_ID`, which the Android 4.19 host kernel does not return. The
  existing machine ID is valid, so `chroot-fixes/systemd.postinst` skips its
  regeneration when the file is already non-empty. A future systemd package
  update can replace this maintainer script and require the workaround again.

Do not claim that every NetHunter attack works until the relevant external
adapter and USB gadget workflow have been tested. Never flash the `c2s`
reference kernel onto this device.

## Android desktop-hybrid mode (external monitor + mouse)

Beyond the kernel/NetHunter work, the phone now drives a genuine AOSP
connected-displays desktop on an external monitor (HP 24es, 1920x1080 over
USB-C/DisplayPort via a dock), with a USB mouse pointer routed to the
external screen and the phone keeping its own separate lock screen/launcher.
This is native Android "Desktop Experience" windowing, not DeX (LineageOS
does not ship Samsung's proprietary DeX framework) and not a VNC/remote
desktop — real freeform windows, a taskbar, and a desktop with icons on the
physical external monitor.

Getting there required two independent gates:

1. `ro.build.characteristics=tablet`, set persistently via a Magisk
   `post-fs-data` script — the first prerequisite for `canHostTasks` on an
   external display.
2. The actual blocker: AOSP's Desktop Experience developer-preview flag,
   `persist.wm.debug.desktop_experience_devopts=true`. After a
   `system_server` restart this flips `enable_display_content_mode_management`
   to `true` and the external display gets `canHostTasks=true`.

Persistent settings involved: `Settings.Secure` `mirror_built_in_display=0`
and `include_default_display_in_topology=1`; `Settings.Global`
`force_desktop_mode_on_external_displays=1`; a per-monitor
`IDisplayManager.setConnectionPreference(<displayUniqueId>, DESKTOP)`; and
`persist.sys.display.enable_on_connect.external=true` so the desktop
auto-enables whenever the monitor is plugged in, including after a full
reboot. Display topology (phone left of monitor) is set via
`IDisplayManager.setDisplayTopology` and persists in
`/data/system_ce/0/display_topology.xml`.

**Smart Dock** (`cu.axel.smartdock`) is used only as the secondary-display
launcher/icon grid — actual window management, the taskbar and freeform
windows are handled by the AOSP shell itself. Two problems had to be solved
to make that combination stable:

- Smart Dock's own overlay panel would sometimes render duplicated on top of
  the AOSP desktop. `device-scripts/smartdock-hybrid.sh` (installed as a
  Magisk `service.d` boot script) watches for the duplicate overlay via
  `dumpsys window windows` and, when it appears, dispatches a synthetic
  downward swipe over the dock panel — this reliably calls Smart Dock's own
  `unpinDock()` internal handler. A swipe was used instead of a tap on the
  pin button specifically because the swipe gesture is not a toggle, so it
  can't accidentally invert the wrong state.
- `com.android.wm.shell.desktopmode.DesktopWallpaperActivity` (SystemUI) was
  disabled for user 0 because it was rendering over the secondary launcher.
  Rollback: `pm enable --user 0
  com.android.systemui/com.android.wm.shell.desktopmode.DesktopWallpaperActivity`.

Smart Dock also needed a full permission set granted manually: overlay,
usage-stats, `WRITE_SECURE_SETTINGS`/`WRITE_SETTINGS`, restricted settings,
notification listener, Doze whitelist, a bound accessibility service (its
component name had to be normalized after Android listed duplicate
equivalent entries post-reboot), a live Shizuku binder connection, and a
permanent Magisk root allow rule for its UID.

Rollback to mirror/no-desktop mode: `setprop
persist.wm.debug.desktop_experience_devopts false` and `setprop
persist.sys.display.enable_on_connect.external false`, then restart
`system_server` or reboot.

Screenshots: `screenshots/desktop-hybrid-screenshot.png` (phone's own
screen) and `screenshots/desktop-hybrid-external-display.png` (the actual
desktop on the HP monitor — taskbar, desktop icons, a sticky-note widget).

## USB gadget and remote access

`device-scripts/swiss-gadget.sh` is a Termux:Boot script that configures a
permanent "swiss knife" USB gadget on every boot: a ConfigFS HID keyboard
(standard boot-keyboard report descriptor), ADB, and an ACM serial console,
all combined on a single UDC (`10e00000.dwc3`). Because this keeps the port
in USB device mode, it directly conflicts with using a USB-C dock (which
needs host mode) — that conflict is resolved by a separate `dock-on`/
`dock-off` toggle script (unbinds/rebinds the UDC on demand), not included
in this repo.

`device-scripts/nh-ssh-autostart.sh` (Magisk `service.d`) autostarts sshd
inside the NetHunter chroot on every boot. It encodes two hard-won fixes,
documented inline in the script itself:

1. `/data/data/com.offsec.nethunter` is credential-encrypted storage and
   does not exist until the phone has been unlocked at least once after
   boot — a human action with no fixed time bound. The script polls
   indefinitely instead of giving up after a fixed timeout.
2. NetHunter's own `bootkali ssh start` routes through `systemctl`, which
   silently no-ops (exit 0, sshd never actually starts) if a stray
   `/run/systemd/system` directory exists inside the chroot. The script
   therefore always also invokes `/usr/sbin/sshd` directly as an idempotent
   fallback, bypassing `systemctl`/`init.d` entirely.

SSH access points into the device:

- Native Kali chroot, root, port 22 (public-key only — see
  `module-fixes/99-nethunter-handheld.conf`).
- Termux (Android host, unprivileged `u0_a*` user), port 8022.

## Field manual

`docs/field-manual.html` is a self-contained (Slovak-language) field guide
covering day-to-day use once the handheld is built: the full NetHunter app
GUI menu, Wi-Fi attacks/monitoring, wardriving+GPS, SDR, network recon and
exploitation, web app testing, Bluetooth, USB HID physical attacks,
containers, using the phone as a portable workstation, diagnostics, and the
system's permanent limits. Open it directly in a browser — no build step,
no external dependencies.

## Repository layout

- `build-*.sh`, `Dockerfile` — reproducible kernel build environment and
  build steps (baseline → NetHunter feature kernel → per-bug fix variants →
  final consolidated build).
- `firmware/` — third-party firmware blobs required by the build scripts
  (Mali GPU, NPU, `rt2870` Wi-Fi), checksummed by each build script. Not
  original work — included only so the build scripts are self-contained.
- `chroot-fixes/`, `module-fixes/` — fixes applied inside the Kali chroot
  and to the NetHunter Magisk module / app scripts.
- `device-scripts/` — on-device automation (USB gadget, SSH autostart,
  desktop-hybrid launcher watchdog) pulled from the phone itself.
- `docs/field-manual.html` — day-to-day usage guide, see above.
- `screenshots/` — the desktop-hybrid mode running live.
- `watch-s20-reboots.sh`, `start-s20-monitor-24h.sh` — spontaneous-reboot
  diagnostic logging used during kernel bring-up.

## Reproducing the kernel source tree

The full LineageOS kernel source (`lineage-kernel/`, ~2.3 GB) and the
official NetHunter Note20 reference (`c2s-reference/`, ~3.6 GB) used
during development are not included in this repo for size reasons. Clone
the LineageOS kernel source for `z3s` at commit `88a015858b05` to
reproduce the baseline; the NetHunter Exynos 990 reference kernel is
available from Kali NetHunter's own repositories if you want to diff
against it (again: never flash it directly on `z3s`).
