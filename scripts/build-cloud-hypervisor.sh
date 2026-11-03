#!/usr/bin/env bash
#
# Build Cloud Hypervisor with the TF patch series for $TARGET_ARCH.
#
# Baseline: upstream cloud-hypervisor at CLOUD_HYPERVISOR_COMMIT, plus
# patches/cloud-hypervisor/*.patch applied in `series` order (generic/profile
# prewarming, seccomp cache, block backing capacity — see
# patches/cloud-hypervisor/README.md).
#
# Native builds are the primary path (CI uses per-arch native runners). A
# cross build works when the matching rustup target and cross linker are
# installed; the script wires the linker via CARGO_TARGET_<triple>_LINKER.
#
# Output: bin/<arch>/cloud-hypervisor.

set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

out_bin="$BIN_DIR/cloud-hypervisor"

require_cmd git cargo

src_dir="$BUILD_DIR/src/cloud-hypervisor"
checkout_pin "$CLOUD_HYPERVISOR_REPO" "$CLOUD_HYPERVISOR_COMMIT" "$src_dir"

# Guard: the series file documents the application order; the sorted *.patch
# glob used by apply_patches must agree with it.
mapfile -t series < <(grep -vE '^\s*(#|$)' "$REPO_ROOT/patches/cloud-hypervisor/series")
mapfile -t patches < <(ls "$REPO_ROOT/patches/cloud-hypervisor"/*.patch 2>/dev/null | sort)
if [ "${#series[@]}" -ne "${#patches[@]}" ] \
    || ! diff <(printf '%s\n' "${series[@]}") \
              <(printf '%s\n' "${patches[@]##*/}") >/dev/null; then
    die "patches/cloud-hypervisor/series and *.patch disagree"
fi

apply_patches "$REPO_ROOT/patches/cloud-hypervisor" "$src_dir"

cargo_flags=(--release --bin cloud-hypervisor)
if [ "$TARGET_ARCH" != "$HOST_ARCH" ]; then
    case "$TARGET_ARCH" in
        x86_64)  rust_target=x86_64-unknown-linux-gnu ;;
        aarch64) rust_target=aarch64-unknown-linux-gnu ;;
    esac
    cargo_flags+=(--target "$rust_target")
    export CARGO_TARGET_"${rust_target^^}"_LINKER="${CROSS_PREFIX}gcc"
    log "cross build via rust target $rust_target (rustup target add $rust_target first)"
else
    case "$HOST_ARCH" in
        x86_64)  rust_target=x86_64-unknown-linux-gnu ;;
        aarch64) rust_target=aarch64-unknown-linux-gnu ;;
    esac
fi

export CARGO_TARGET_DIR="$BUILD_DIR/ch/target/$TARGET_ARCH"
log "cargo build cloud-hypervisor (this takes several minutes)"
(cd "$src_dir" && cargo build "${cargo_flags[@]}")

built="$CARGO_TARGET_DIR/release/cloud-hypervisor"
[ -x "$built" ] || die "cargo build finished but $built is missing"
install -m 0755 "$built" "$out_bin"
log "built $out_bin"
