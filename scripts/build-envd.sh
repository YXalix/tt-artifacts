#!/usr/bin/env bash
#
# Build the E2B guest agent (envd) for $TARGET_ARCH.
#
# Source: e2b-dev/runtime release tarball (pinned by tag). CGO-free, so
# GOARCH alone handles cross-compilation. The binary is embedded into the
# bootstrap rootfs at /opt/sandbox-runtime/bin/envd.
#
# envd's go.mod pins a Go toolchain newer than many distro packages; with
# GOTOOLCHAIN=auto (the default) the go command fetches it on demand. Keep
# GOSUMDB enabled — Go refuses toolchain downloads when it is off.
#
# Output: bin/<arch>/envd.

set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

out_bin="$BIN_DIR/envd"
if [ -x "$out_bin" ]; then
    log "already built: $out_bin (delete it to force rebuild)"
    exit 0
fi

require_cmd go tar sha256sum curl

tarball="$(resolve_tarball "$ENVD_TARBALL" "$ENVD_TARBALL_SHA256")"
src_dir="$BUILD_DIR/src/e2b-runtime"
extract_tarball "$tarball" "$src_dir"

envd_dir="$src_dir/packages/envd"
[ -f "$envd_dir/main.go" ] || die "$envd_dir/main.go not found (upstream layout changed?)"

log "go build envd (GOARCH=$GO_ARCH, CGO disabled)"
(
    cd "$envd_dir"
    GOWORK=off GOOS=linux GOARCH="$GO_ARCH" CGO_ENABLED=0 \
        go build -p "$BUILD_JOBS" -trimpath -ldflags "-s -w" -o "$out_bin" .
)

log "built $out_bin"
file "$out_bin" 2>&1 | head -1 || true
