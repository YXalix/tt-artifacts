#!/usr/bin/env bash
#
# Build flatten-ctl for $TARGET_ARCH — the in-guest OCI image flattener used
# by template building. It is embedded into the bootstrap rootfs at
# /opt/sandbox-runtime/bin/flatten-ctl.
#
# Source: kuasar-sandbox/guest-runtime at GUEST_RUNTIME_COMMIT, whose go.mod
# replaces github.com/kuasar-sandbox/accelerator with the sibling directory
# ../accelerator — cloned at ACCELERATOR_COMMIT to keep the pair consistent.
# CGO-free Go build, GOARCH cross-compilation.
#
# Output: bin/<arch>/flatten-ctl.

set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

out_bin="$BIN_DIR/flatten-ctl"

require_cmd git go

src_dir="$BUILD_DIR/src/guest-runtime"
acc_dir="$BUILD_DIR/src/accelerator"
checkout_pin "$GUEST_RUNTIME_REPO" "$GUEST_RUNTIME_COMMIT" "$src_dir"
checkout_pin "$ACCELERATOR_REPO" "$ACCELERATOR_COMMIT" "$acc_dir"

# The replace directive expects the sibling layout build/src/guest-runtime
# and build/src/accelerator.
[ -d "$acc_dir" ] || die "sibling accelerator tree missing at $acc_dir"

log "go build flatten-ctl (GOARCH=$GO_ARCH, CGO disabled)"
(
    cd "$src_dir"
    GOWORK=off GOOS=linux GOARCH="$GO_ARCH" CGO_ENABLED=0 \
        go build -p "$BUILD_JOBS" -trimpath -ldflags "-s -w" -o "$out_bin" ./cmd/flatten-ctl
)

log "built $out_bin"
file "$out_bin" 2>&1 | head -1 || true
