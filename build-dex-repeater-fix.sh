#!/usr/bin/env bash
set -euo pipefail

port_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
image_name="s20-z3s-kernel-builder:ubuntu22.04"
output_dir="${port_dir}/out-dex-repeater-fix"
firmware_dir="${port_dir}/firmware-input"
kernel_jobs="${KERNEL_JOBS:-8}"

declare -A expected_sha256=(
    ["${firmware_dir}/npu/NPU.bin"]="38712ba909dea900eb0d7ccb666e1c0f5c962804fdb9bdd2852e1f684f7bb5b1"
    ["${firmware_dir}/valhall-1691526.wa"]="1a52a7f3c7c8b15e13e226d0956091621a83baafd80a3f93debb8271110e5951"
    ["${firmware_dir}/rt2870.bin"]="251b8918391eac6415d60dca239e415aad0177e885376f2a17782e64fcbbe317"
)

for firmware in "${!expected_sha256[@]}"; do
    if [[ ! -r "${firmware}" ]]; then
        printf 'Required firmware is missing: %s\n' "${firmware}" >&2
        exit 1
    fi
    actual_sha256="$(sha256sum "${firmware}" | awk '{print $1}')"
    if [[ "${actual_sha256}" != "${expected_sha256[${firmware}]}" ]]; then
        printf 'Unexpected firmware SHA-256 for %s: %s\n' "${firmware}" "${actual_sha256}" >&2
        exit 1
    fi
done

rm -rf "${output_dir}"
mkdir -p "${output_dir}"

docker run --rm \
    --user "$(id -u):$(id -g)" \
    --env "KERNEL_JOBS=${kernel_jobs}" \
    --volume "${port_dir}:/work" \
    --volume "${firmware_dir}:/firmware-input:ro" \
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
        config=/work/out-dex-repeater-fix/.config

        gzip -cd /work/running.config.gz > "${config}"
        scripts/config --file "${config}" --set-str LOCALVERSION "-nh-z3s-dexfix"

        scripts/config --file "${config}" --enable USB_CONFIGFS_F_HID
        scripts/config --file "${config}" --enable USB_F_HID
        scripts/config --file "${config}" --enable USB_MON

        scripts/config --file "${config}" --enable USB_SERIAL_CP210X
        scripts/config --file "${config}" --enable USB_SERIAL_CH341

        scripts/config --file "${config}" --enable BT_RFCOMM
        scripts/config --file "${config}" --enable BT_RFCOMM_TTY
        scripts/config --file "${config}" --enable BT_HCIBTUSB
        scripts/config --file "${config}" --enable BT_HCIBTUSB_BCM
        scripts/config --file "${config}" --enable BT_HCIBTUSB_RTL

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

        # Preserve the two firmware payloads from the running Samsung config
        # and append the Ralink firmware required by RT2800USB.
        scripts/config --file "${config}" --set-str EXTRA_FIRMWARE \
            "npu/NPU.bin valhall-1691526.wa rt2870.bin"
        scripts/config --file "${config}" --set-str EXTRA_FIRMWARE_DIR "/firmware-input"

        scripts/config --file "${config}" --enable POSIX_MQUEUE
        scripts/config --file "${config}" --disable IPC_NS
        scripts/config --file "${config}" --disable USER_NS
        scripts/config --file "${config}" --disable CGROUP_PIDS
        scripts/config --file "${config}" --disable CGROUP_DEVICE
        scripts/config --file "${config}" --enable BRIDGE
        scripts/config --file "${config}" --enable BRIDGE_NETFILTER
        scripts/config --file "${config}" --enable NETFILTER_XT_MATCH_ADDRTYPE

        make O=/work/out-dex-repeater-fix "${toolchain_args[@]}" olddefconfig

        # Samsung 4.19 firmware Makefile expects these paths in the object tree
        # for this out-of-tree build even with EXTRA_FIRMWARE_DIR configured.
        mkdir -p /work/out-dex-repeater-fix/firmware/npu
        install -m 0644 /firmware-input/npu/NPU.bin \
            /work/out-dex-repeater-fix/firmware/npu/NPU.bin
        install -m 0644 /firmware-input/valhall-1691526.wa \
            /work/out-dex-repeater-fix/firmware/valhall-1691526.wa
        install -m 0644 /firmware-input/rt2870.bin \
            /work/out-dex-repeater-fix/firmware/rt2870.bin

        required=(
            USB_CONFIGFS_F_HID USB_F_HID USB_MON
            BT_RFCOMM BT_RFCOMM_TTY BT_HCIBTUSB
            CFG80211_WEXT MAC80211 MAC80211_MESH ATH9K_HTC
            RTL8187 RTL8XXXU RT2X00 RT2800USB
            POSIX_MQUEUE POSIX_MQUEUE_SYSCTL
            BRIDGE BRIDGE_NETFILTER NETFILTER_XT_MATCH_ADDRTYPE
        )
        for symbol in "${required[@]}"; do
            if ! grep -q "^CONFIG_${symbol}=y$" "${config}"; then
                printf "Required kernel option CONFIG_%s=y was not resolved\n" "${symbol}" >&2
                exit 1
            fi
        done

        forbidden=(IPC_NS USER_NS CGROUP_PIDS CGROUP_DEVICE)
        for symbol in "${forbidden[@]}"; do
            if grep -q "^CONFIG_${symbol}=" "${config}"; then
                printf "Forbidden kernel option CONFIG_%s was enabled\n" "${symbol}" >&2
                exit 1
            fi
        done

        if ! grep -q "^CONFIG_EXTRA_FIRMWARE=\"npu/NPU.bin valhall-1691526.wa rt2870.bin\"$" "${config}"; then
            printf "Required combined firmware list was not resolved\n" >&2
            exit 1
        fi

        make O=/work/out-dex-repeater-fix "${toolchain_args[@]}" -j"${KERNEL_JOBS}"
    '
