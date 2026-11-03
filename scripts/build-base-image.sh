#!/usr/bin/env bash
#
# Build the business base image (base.erofs) for $TARGET_ARCH: the stock
# Ubuntu Noble cloud rootfs as a bare, uncompressed EROFS image. tfc-server
# consumes it as a shared read-only lower layer (virtio-blk or pmem), so no
# partition table, no OCI tar, no qcow2 — a plain filesystem image, 512-byte
# aligned as mkfs.erofs produces it.
#
# The rootfs tarball is pinned per arch in pins.sh with SHA256.
#
# Output: dist/<arch>/base.erofs.

set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

require_cmd install

case "$TARGET_ARCH" in
    x86_64)  tarball_name="$UBUNTU_ROOTFS_AMD64";  tarball_sha="$UBUNTU_ROOTFS_AMD64_SHA256"  ;;
    aarch64) tarball_name="$UBUNTU_ROOTFS_ARM64";  tarball_sha="$UBUNTU_ROOTFS_ARM64_SHA256"  ;;
esac

mkfs_bin="${MKFS_EROFS:-$BIN_DIR/mkfs.erofs}"
fsck_bin="${FSCK_EROFS:-$BIN_DIR/fsck.erofs}"
[ -x "$mkfs_bin" ] || die "mkfs.erofs not found: $mkfs_bin"

out="$DIST_DIR/base.erofs"
staging="$BUILD_DIR/base/$TARGET_ARCH/root"
tarball="$(resolve_tarball "$UBUNTU_ROOTFS_BASE/$tarball_name" "$tarball_sha")"

if [ ! -f "$staging/.extracted" ]; then
    require_cmd tar
    rm -rf "$staging"
    mkdir -p "$staging"
    # The cloud rootfs tarball has no top-level directory and ships /dev/*
    # device nodes; creating them (mknod) needs privileges a plain CI runner
    # user lacks, so fall back to sudo and hand the tree back afterwards.
    tar_err="$BUILD_DIR/base/$TARGET_ARCH/tar.err"
    if ! tar -xJf "$tarball" -C "$staging" 2>"$tar_err"; then
        if grep -q "Cannot mknod" "$tar_err" && command -v sudo >/dev/null 2>&1; then
            log "device nodes need mknod privileges; retrying with sudo"
            sudo tar -xJf "$tarball" -C "$staging"
            sudo chown -R "$(id -u):$(id -g)" "$staging"
        else
            cat "$tar_err" >&2
            die "tar extraction failed: $tarball_name"
        fi
    fi
    touch "$staging/.extracted"
    log "extracted $tarball_name -> $staging"
fi

log "mkfs.erofs: bare, uncompressed, no inline data"
mkdir -p "$DIST_DIR"
rm -f "$out"
# No -z option: erofs-utils 1.9.x has no "none" compressor; without -z the
# image is plain uncompressed EROFS.
"$mkfs_bin" -E noinline_data "$out" "$staging"

if [ -x "$fsck_bin" ]; then
    "$fsck_bin" "$out" >/dev/null 2>&1 || die "fsck.erofs failed on $out"
    log "fsck.erofs passed"
fi

log "built $out ($(du -h "$out" | cut -f1))"
