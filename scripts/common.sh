#!/usr/bin/env bash
#
# Shared helpers for tt-artifacts build scripts. Sourced, not executed.
#
# Provides: arch normalization/mapping, logging, tarball fetch/extract with
# optional SHA256 verification, git source checkout at a pinned commit.
# Callers must set TARGET_ARCH (x86_64 | aarch64) before sourcing, or accept
# the host architecture as the default.

set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../pins.sh
source "$REPO_ROOT/pins.sh"

# --- architecture selection -------------------------------------------------

normalize_arch() {
    case "$1" in
        amd64|x86_64) echo x86_64 ;;
        arm64|aarch64) echo aarch64 ;;
        *) die "unsupported architecture: $1 (want x86_64 or aarch64)" ;;
    esac
}

TARGET_ARCH="$(normalize_arch "${TARGET_ARCH:-$(uname -m)}")"
HOST_ARCH="$(normalize_arch "$(uname -m)")"

case "$TARGET_ARCH" in
    x86_64)  GO_ARCH=amd64;    KERNEL_ARCH=x86;    KBUILD_TARGET=vmlinux;  KIMAGE_SUBPATH=vmlinux ;;
    aarch64) GO_ARCH=arm64;    KERNEL_ARCH=arm64;  KBUILD_TARGET=Image;   KIMAGE_SUBPATH=arch/arm64/boot/Image ;;
esac

if [ "$HOST_ARCH" = "$TARGET_ARCH" ]; then
    CROSS_PREFIX=""
else
    case "$TARGET_ARCH" in
        x86_64)  CROSS_PREFIX=x86_64-linux-gnu- ;;
        aarch64) CROSS_PREFIX=aarch64-linux-gnu- ;;
    esac
fi

# --- paths -------------------------------------------------------------------

BUILD_DIR="${TT_ARTIFACTS_BUILD_DIR:-$REPO_ROOT/build}"
BIN_DIR="$REPO_ROOT/bin/$TARGET_ARCH"
DIST_DIR="$REPO_ROOT/dist/$TARGET_ARCH"
TARBALL_CACHE="${TARBALL_CACHE:-$BUILD_DIR/tarball}"
BUILD_JOBS="${BUILD_JOBS:-$(nproc)}"

mkdir -p "$BIN_DIR" "$TARBALL_CACHE"

# --- tarball fetch/extract ---------------------------------------------------

require_cmd() {
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 || die "missing required tool: $c"
    done
}

resolve_tarball() {
    local spec="$1" sha256="${2:-}"
    [ -n "$spec" ] || die "tarball spec is empty"

    local url="" filename=""
    case "$spec" in
        *'#'*) url="${spec%#*}"; filename="${spec##*#}" ;;
        http://*|https://*)
            url="$spec"
            local u="${url%%\?*}"
            filename="${u##*/}" ;;
        *) filename="$(basename "$spec")" ;;
    esac
    [ -n "$filename" ] || die "could not derive filename from: $spec"

    local cache="$TARBALL_CACHE/$filename"
    if [ -f "$cache" ]; then
        log "tarball cache hit: $cache" >&2
    elif [ -n "$url" ]; then
        require_cmd curl
        log "downloading $url" >&2
        curl -fsSL --retry 3 -o "$cache.tmp" "$url" \
            || die "download failed: $url"
        mv "$cache.tmp" "$cache"
    else
        [ -f "$spec" ] || die "local tarball not found: $spec"
        log "using local tarball: $spec" >&2
        cp "$spec" "$cache"
    fi

    if [ -n "$sha256" ]; then
        require_cmd sha256sum
        echo "$sha256  $cache" | sha256sum -c - >&2 \
            || die "sha256 mismatch for $cache (expected $sha256)"
        log "sha256 verified: $filename" >&2
    fi
    echo "$cache"
}

# extract_tarball TARBALL DEST_DIR — idempotent via .extracted marker.
extract_tarball() {
    local tarball="$1" dest="$2"
    if [ -f "$dest/.extracted" ]; then
        log "already extracted: $dest"
        return 0
    fi
    require_cmd tar
    mkdir -p "$dest"
    tar -xf "$tarball" -C "$dest" --strip-components=1
    touch "$dest/.extracted"
    log "extracted $(basename "$tarball") -> $dest"
}

# --- pinned git source -------------------------------------------------------

# checkout_pin CLONE_URL COMMIT DEST_DIR — clone once, then checkout the pin.
# Idempotent: skips network access when the commit is already checked out.
checkout_pin() {
    local url="$1" commit="$2" dest="$3"
    if [ -d "$dest/.git" ]; then
        if [ "$(git -C "$dest" rev-parse HEAD)" = "$commit" ]; then
            log "source already at $commit: $dest"
            return 0
        fi
        git -C "$dest" fetch --quiet origin "$commit" 2>/dev/null \
            || git -C "$dest" fetch --quiet origin
    else
        mkdir -p "$(dirname "$dest")"
        git clone --quiet --filter=blob:none "$url" "$dest"
    fi
    git -C "$dest" checkout --quiet --force "$commit" \
        || die "failed to checkout $commit in $dest"
    # Drop files a previous patch application created so apply_patches can
    # reapply the series cleanly (checkout --force only resets tracked files).
    git -C "$dest" clean -fdq
    log "checked out $commit -> $dest"
}

# --- patch application -------------------------------------------------------

# apply_patches PATCH_DIR GIT_TREE_DIR — apply *.patch sorted by name, once.
# Detects a previous application by reversing the whole series; the reversal
# must run in reverse order because later patches may modify files created by
# earlier ones. Refuses ambiguous states instead of guessing.
apply_patches() {
    local patch_dir="$1" tree="$2"
    local patches=()
    # shellcheck disable=SC2012
    mapfile -t patches < <(ls "$patch_dir"/*.patch 2>/dev/null | sort) || true
    [ "${#patches[@]}" -gt 0 ] || { log "no patches in $patch_dir"; return 0; }

    # Detect a previous application: reverse the series one patch at a time,
    # in reverse order (later patches may modify files created by earlier
    # ones; a single multi-patch `git apply --check --reverse` is unreliable
    # for such series).
    local i
    for ((i = ${#patches[@]} - 1; i >= 0; i--)); do
        if ! git -C "$tree" apply --check --reverse "${patches[i]}" >/dev/null 2>&1; then
            break
        fi
        if [ "$i" -eq 0 ]; then
            log "patches already applied: $patch_dir"
            return 0
        fi
    done
    for p in "${patches[@]}"; do
        git -C "$tree" apply --check "$p" \
            || die "patch does not apply to current tree: $p"
        git -C "$tree" apply "$p"
        log "applied $(basename "$p")"
    done
}
