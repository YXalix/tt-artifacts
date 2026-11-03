#!/usr/bin/env bash
#
# Build the guest kernel (vmlinux) for $TARGET_ARCH.
#
#   x86_64  raw ELF kernel, PVH-bootable by Cloud Hypervisor
#   aarch64 PE-format Image (EFI stub + ACPI), bootable by Cloud Hypervisor
#
# Method: upstream Linux tarball + patches/kernel/*.patch (currently none),
# configuration from config/sandbox-common.config + config/sandbox-<arch>.config
# (the kuasar-sandbox guest-runtime fragments). Output: bin/<arch>/vmlinux.
#
# Build deps: gcc/(cross gcc), bc, bison, flex, make, libelf headers,
# libssl headers, pkg-config.
#
# Inputs (env): TARGET_ARCH, BUILD_JOBS, TARBALL_CACHE, LINUX_TARBALL(_SHA256)
# override via pins.sh-compatible env.

set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

src_dir="$BUILD_DIR/src/linux"
out_dir="$BUILD_DIR/linux/$TARGET_ARCH"
out_bin="$BIN_DIR/vmlinux"

require_cmd make gcc bc bison flex pkg-config sha256sum curl git tar

tarball="$(resolve_tarball "${LINUX_TARBALL_OVERRIDE:-$LINUX_TARBALL}" "${LINUX_TARBALL_SHA256_OVERRIDE:-$LINUX_TARBALL_SHA256}")"
extract_tarball "$tarball" "$src_dir"

# Import the pristine source as a git tree so patches stay reviewable.
if [ ! -d "$src_dir/.git" ]; then
    git -C "$src_dir" init --quiet
    git -C "$src_dir" add -A
    git -C "$src_dir" -c user.name=tt-artifacts -c user.email=tt-artifacts@localhost \
        commit --quiet -m "linux-${LINUX_VERSION} import"
    git -C "$src_dir" tag linux-base
    log "imported source, tagged linux-base"
fi

apply_patches "$REPO_ROOT/patches/kernel" "$src_dir"

# Merge the configuration fragments into a defconfig for this arch.
fragments=("$REPO_ROOT/config/sandbox-common.config"
           "$REPO_ROOT/config/sandbox-$TARGET_ARCH.config")
defconfig_dir="$src_dir/arch/$KERNEL_ARCH/configs"
mkdir -p "$defconfig_dir"
cat "${fragments[@]}" > "$defconfig_dir/sandbox_defconfig"
log "wrote sandbox_defconfig from ${fragments[*]##*/}"

make_kbuild() {
    # out_dir must exist for a clean O= out-of-tree build (an empty O= would
    # silently build into the shared source tree).
    mkdir -p "$out_dir"
    make -C "$src_dir" O="$out_dir" \
        ARCH="$KERNEL_ARCH" ${CROSS_PREFIX:+CROSS_COMPILE="$CROSS_PREFIX"} "$@"
}

make_kbuild sandbox_defconfig
make_kbuild olddefconfig
log "building $KBUILD_TARGET ($BUILD_JOBS jobs) — multi-minute cold build"
make_kbuild -j "$BUILD_JOBS" "$KBUILD_TARGET"

install -m 0644 "$out_dir/$KIMAGE_SUBPATH" "$out_bin"
log "built $out_bin ($(du -h "$out_bin" | cut -f1))"
