#!/usr/bin/env bash
set -euo pipefail

port_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
image_name="s20-z3s-kernel-builder:ubuntu22.04"
output_dir="${port_dir}/out-nethunter"
kernel_jobs="${KERNEL_JOBS:-4}"
rt2870_firmware="/lib/firmware/rt2870.bin"
rt2870_sha256="251b8918391eac6415d60dca239e415aad0177e885376f2a17782e64fcbbe317"

if [[ ! -r "${rt2870_firmware}" ]]; then
    printf 'Required firmware is missing: %s\n' "${rt2870_firmware}" >&2
    exit 1
fi

actual_firmware_sha256="$(sha256sum "${rt2870_firmware}" | awk '{print $1}')"
if [[ "${actual_firmware_sha256}" != "${rt2870_sha256}" ]]; then
    printf 'Unexpected rt2870.bin SHA-256: %s\n' "${actual_firmware_sha256}" >&2
    exit 1
fi

rm -rf "${output_dir}"
mkdir -p "${output_dir}"

docker run --rm \
    --user "$(id -u):$(id -g)" \
    --env "KERNEL_JOBS=${kernel_jobs}" \
    --volume "${port_dir}:/work" \
    --volume "${rt2870_firmware}:/firmware/rt2870.bin:ro" \
    --workdir /work/lineage-kernel \
    "${image_name}" \
    bash -euc '
        toolchain_args=(
            ARCH=arm64
            CC=clang
            LD=ld.lld
            AR=llvm-ar
            NM=llvm-nm
            OBJCOPY=llvm-objcopy
            OBJDUMP=llvm-objdump
            STRIP=llvm-strip
            LLVM_IAS=1
        )
        config=/work/out-nethunter/.config

        gzip -cd /work/running.config.gz > "${config}"

        scripts/config --file "${config}" --set-str LOCALVERSION "-nethunter-z3s-rt2800"

        # NetHunter USB Arsenal and USB traffic inspection.
        scripts/config --file "${config}" --enable USB_CONFIGFS_F_HID
        scripts/config --file "${config}" --enable USB_F_HID
        scripts/config --file "${config}" --enable USB_MON

        # Bluetooth Arsenal, including common external USB adapters.
        scripts/config --file "${config}" --enable BT_RFCOMM
        scripts/config --file "${config}" --enable BT_RFCOMM_TTY
        scripts/config --file "${config}" --enable BT_HCIBTUSB
        scripts/config --file "${config}" --enable BT_HCIBTUSB_BCM
        scripts/config --file "${config}" --enable BT_HCIBTUSB_RTL

        # mac80211 injection-capable external Wi-Fi adapters.
        scripts/config --file "${config}" --enable CFG80211_WEXT
        scripts/config --file "${config}" --enable MAC80211
        scripts/config --file "${config}" --enable MAC80211_MESH
        scripts/config --file "${config}" --enable ATH9K_HTC
        scripts/config --file "${config}" --enable ATH9K_HTC_DEBUGFS
        scripts/config --file "${config}" --enable RTL8187
        scripts/config --file "${config}" --enable RTL8XXXU
        scripts/config --file "${config}" --enable RTL8XXXU_UNTESTED
        scripts/config --file "${config}" --enable RT2X00
        scripts/config --file "${config}" --enable RT2800USB
        scripts/config --file "${config}" --set-str EXTRA_FIRMWARE "rt2870.bin"
        scripts/config --file "${config}" --set-str EXTRA_FIRMWARE_DIR "/firmware"

        # Container networking used by chroot/proot workloads.
        scripts/config --file "${config}" --enable BRIDGE
        scripts/config --file "${config}" --enable BRIDGE_NETFILTER
        scripts/config --file "${config}" --enable NETFILTER_XT_MATCH_ADDRTYPE

        make O=/work/out-nethunter "${toolchain_args[@]}" olddefconfig

        # Samsung 4.19 firmware Makefile does not copy CONFIG_EXTRA_FIRMWARE
        # from CONFIG_EXTRA_FIRMWARE_DIR for out-of-tree builds. Stage the
        # verified blob in the object tree where its generated-object rule
        # expects it.
        mkdir -p /work/out-nethunter/firmware
        install -m 0644 /firmware/rt2870.bin /work/out-nethunter/firmware/rt2870.bin

        required=(
            USB_CONFIGFS_F_HID
            USB_F_HID
            USB_MON
            BT_RFCOMM
            BT_RFCOMM_TTY
            BT_HCIBTUSB
            CFG80211_WEXT
            MAC80211
            MAC80211_MESH
            ATH9K_HTC
            RTL8187
            RTL8XXXU
            RT2X00
            RT2800USB
            BRIDGE
            BRIDGE_NETFILTER
            NETFILTER_XT_MATCH_ADDRTYPE
        )
        for symbol in "${required[@]}"; do
            if ! grep -q "^CONFIG_${symbol}=y$" "${config}"; then
                printf "Required kernel option CONFIG_%s=y was not resolved\n" "${symbol}" >&2
                exit 1
            fi
        done

        if ! grep -q "^CONFIG_EXTRA_FIRMWARE=\"rt2870.bin\"$" "${config}"; then
            printf "Required rt2870.bin firmware was not embedded\n" >&2
            exit 1
        fi

        make O=/work/out-nethunter "${toolchain_args[@]}" -j"${KERNEL_JOBS}"
    '
