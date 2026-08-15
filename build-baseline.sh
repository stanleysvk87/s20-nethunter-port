#!/usr/bin/env bash
set -euo pipefail

port_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
image_name="s20-z3s-kernel-builder:ubuntu22.04"
output_dir="${port_dir}/out-baseline"
kernel_jobs="${KERNEL_JOBS:-4}"

rm -rf "${output_dir}"
mkdir -p "${output_dir}"

docker run --rm \
    --user "$(id -u):$(id -g)" \
    --env "KERNEL_JOBS=${kernel_jobs}" \
    --volume "${port_dir}:/work" \
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

        gzip -cd /work/running.config.gz > /work/out-baseline/.config
        make O=/work/out-baseline "${toolchain_args[@]}" olddefconfig
        make O=/work/out-baseline "${toolchain_args[@]}" -j"${KERNEL_JOBS}"
    '
