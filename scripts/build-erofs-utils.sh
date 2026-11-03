#!/usr/bin/env bash
#
# Build erofs-utils (mkfs.erofs, fsck.erofs, dump.erofs) for $TARGET_ARCH.
#
# mkfs.erofs builds the bootstrap rootfs.erofs and business base.erofs images;
# a copy of mkfs.erofs is also embedded into the bootstrap so template builds
# can produce EROFS inside the guest. fsck.erofs/dump.erofs stay on the host
# for image validation. Static linking keeps the embedded binary free of guest
# library requirements.
#
# Images produced by this repo are uncompressed (-z none) with inline data
# disabled (-E noinline_data) to match the pmem/ublkd consumption path of the
# tfc-server runtime.
#
# Output: bin/<arch>/mkfs.erofs, fsck.erofs, dump.erofs.

set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

out_dir="$BIN_DIR"
build_dir="$BUILD_DIR/erofs-utils/$TARGET_ARCH"

require_cmd make sha256sum curl tar

tarball="$(resolve_tarball "$EROFS_UTILS_TARBALL" "$EROFS_UTILS_TARBALL_SHA256")"
src_dir="$BUILD_DIR/src/erofs-utils"
extract_tarball "$tarball" "$src_dir"

# The GitHub source archive has no generated configure; autoreconf needs
# libtoolize (the libtool package's guaranteed binary, unlike libtool itself).
if [ ! -x "$src_dir/configure" ]; then
    require_cmd autoreconf automake autoconf libtoolize
    (cd "$src_dir" && ./autogen.sh)
fi

mkdir -p "$build_dir"
log "configure erofs-utils ($EROFS_UTILS_TAG) for $TARGET_ARCH (static)"
(
    cd "$build_dir"
    # Static build with every optional library disabled: the images this
    # repo produces are uncompressed EROFS, so no compression backends are
    # needed, and the embedded mkfs.erofs then depends only on libc.
    # libtool needs -all-static; a plain -static only affects the project's
    # own libraries and the binary stays dynamically linked.
    "$src_dir/configure" \
        CC="${CROSS_PREFIX}gcc" \
        --quiet \
        --disable-lz4 \
        --disable-lzma \
        --disable-ublk \
        --disable-s3 \
        --disable-oci \
        --disable-fanotify \
        --without-zlib \
        --without-libdeflate \
        --without-libzstd \
        --without-qpl \
        --without-xxhash \
        --without-libcurl \
        --without-openssl \
        --without-libxml2 \
        --without-json_c \
        --without-libnl3 \
        --without-uuid
)

# -all-static is a libtool flag: gcc would reject it during configure's
# compiler probes, so pass it to make instead of configure.
log "make erofs-utils ($BUILD_JOBS jobs, static)"
make -C "$build_dir" LDFLAGS="-all-static" -j "$BUILD_JOBS"

install -m 0755 "$build_dir/mkfs/mkfs.erofs" "$out_dir/mkfs.erofs"
install -m 0755 "$build_dir/fsck/fsck.erofs" "$out_dir/fsck.erofs"
install -m 0755 "$build_dir/dump/dump.erofs" "$out_dir/dump.erofs"

log "built $out_dir/{mkfs,fsck,dump}.erofs"
file "$out_dir/mkfs.erofs" 2>&1 | head -1 || true
