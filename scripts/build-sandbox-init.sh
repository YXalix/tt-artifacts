#!/usr/bin/env bash
#
# Build the guest PID 1 (sandbox-init) for $TARGET_ARCH, with the TF patch
# series applied (see patches/sandbox-init/README.md):
#
#   0001  vsock EOF handling for the PID 1 reader
#   0002  shared EROFS/ext4 lower for the dual-disk root layout
#   0003  unmounted-bootstrap kernel baseline gate (optional Data optimization)
#
# Source: kuasar-sandbox/sandboxer at SANDBOXER_COMMIT — the commit the
# patches were made against (verified to apply cleanly). CGO-free Go build.
#
# Output: bin/<arch>/sandbox-init.

set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

out_bin="$BIN_DIR/sandbox-init"

require_cmd git go

src_dir="$BUILD_DIR/src/sandboxer"
# checkout_pin force-checkouts the pin, resetting any previously applied
# patches; apply_patches then reapplies them fresh. Deterministic on re-runs.
checkout_pin "$SANDBOXER_REPO" "$SANDBOXER_COMMIT" "$src_dir"
apply_patches "$REPO_ROOT/patches/sandbox-init" "$src_dir"

log "go build sandbox-init (GOARCH=$GO_ARCH, CGO disabled)"
(
    cd "$src_dir"
    GOWORK=off GOOS=linux GOARCH="$GO_ARCH" CGO_ENABLED=0 \
        go build -p "$BUILD_JOBS" -trimpath -ldflags "-s -w" -o "$out_bin" ./cmd/sandbox-init
)

log "built $out_bin"
file "$out_bin" 2>&1 | head -1 || true
