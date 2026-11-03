#!/usr/bin/env bash
#
# Assemble the bootstrap rootfs.erofs for $TARGET_ARCH (bare, uncompressed
# EROFS, inline data disabled, size padded up to a 2 MiB boundary for CH's
# virtio-pmem mapping).
#
# Layout (mirrors the validated tt-resource bootstrap):
#
#   /sbin/init                            sandbox-init (guest PID 1)
#   /opt/sandbox-runtime/bin/envd         E2B guest agent
#   /opt/sandbox-runtime/bin/flatten-ctl  in-guest OCI flattener
#   /opt/sandbox-runtime/bin/mkfs.erofs   in-guest EROFS builder
#   /proc /sys /dev /sysroot              empty mountpoints
#   /overlay/lower /overlay/upper         dual-disk root mountpoints
#   /sysdisks/disk-{0..7}{,-lower,-upper} data-disk mountpoints
#
# Requires: bin/<arch>/{sandbox-init,envd,flatten-ctl} and mkfs.erofs
# (host copy; bin/<arch> or from PATH via MKFS_EROFS).
#
# Output: dist/<arch>/rootfs.erofs.

set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

require_cmd install truncate

for f in sandbox-init envd flatten-ctl mkfs.erofs; do
    [ -x "$BIN_DIR/$f" ] || die "missing prerequisite: $BIN_DIR/$f (run the matching build target first)"
done

mkfs_bin="${MKFS_EROFS:-$BIN_DIR/mkfs.erofs}"
fsck_bin="${FSCK_EROFS:-$BIN_DIR/fsck.erofs}"
[ -x "$mkfs_bin" ] || die "mkfs.erofs not found: $mkfs_bin"

out="$DIST_DIR/rootfs.erofs"
staging="$BUILD_DIR/rootfs/$TARGET_ARCH/root"
mkdir -p "$staging"

# Payload
install -D -m 0755 "$BIN_DIR/sandbox-init" "$staging/sbin/init"
install -D -m 0755 "$BIN_DIR/envd"         "$staging/opt/sandbox-runtime/bin/envd"
install -D -m 0755 "$BIN_DIR/flatten-ctl"  "$staging/opt/sandbox-runtime/bin/flatten-ctl"
install -D -m 0755 "$BIN_DIR/mkfs.erofs"   "$staging/opt/sandbox-runtime/bin/mkfs.erofs"

# Mountpoints (dirs must preexist; nothing else ships in the image)
mkdir -p "$staging/proc" "$staging/sys" "$staging/dev" "$staging/sysroot" \
         "$staging/overlay/lower" "$staging/overlay/upper"
for i in 0 1 2 3 4 5 6 7; do
    mkdir -p "$staging/sysdisks/disk-$i" \
             "$staging/sysdisks/disk-$i-lower" \
             "$staging/sysdisks/disk-$i-upper"
done

log "mkfs.erofs: bare, uncompressed, no inline data"
mkdir -p "$DIST_DIR"
rm -f "$out"
# No -z option: erofs-utils 1.9.x has no "none" compressor; without -z the
# image is plain uncompressed EROFS.
"$mkfs_bin" -E noinline_data "$out" "$staging"

# Pad the image up to a 2 MiB boundary (CH virtio-pmem mapping requirement).
size=$(stat -c %s "$out")
aligned=$(( (size + 2097151) / 2097152 * 2097152 ))
if [ "$aligned" -ne "$size" ]; then
    truncate -s "$aligned" "$out"
    log "padded image $size -> $aligned bytes (2 MiB boundary)"
fi

if [ -x "$fsck_bin" ]; then
    "$fsck_bin" "$out" >/dev/null 2>&1 || die "fsck.erofs failed on $out"
    log "fsck.erofs passed"
fi

log "built $out ($(du -h "$out" | cut -f1))"
