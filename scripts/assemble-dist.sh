#!/usr/bin/env bash
#
# Collect all artifacts for $TARGET_ARCH into dist/<arch>/ with a SHA256SUMS
# file and a manifest.json recording the pins used and the repository state.
# Run after the individual build targets.

set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$script_dir/common.sh"

require_cmd sha256sum

mkdir -p "$DIST_DIR"

case "$TARGET_ARCH" in
    x86_64)  tarball_name="$UBUNTU_ROOTFS_AMD64";  tarball_sha="$UBUNTU_ROOTFS_AMD64_SHA256"  ;;
    aarch64) tarball_name="$UBUNTU_ROOTFS_ARM64";  tarball_sha="$UBUNTU_ROOTFS_ARM64_SHA256"  ;;
esac

artifacts=(vmlinux rootfs.erofs base.erofs cloud-hypervisor envd sandbox-init flatten-ctl mkfs.erofs fsck.erofs dump.erofs)

for f in "${artifacts[@]}"; do
    if [ -f "$BIN_DIR/$f" ]; then
        install -m 0644 "$BIN_DIR/$f" "$DIST_DIR/$f"
    elif [ -f "$DIST_DIR/$f" ]; then
        : # image produced in place by build-rootfs/build-base-image
    else
        die "missing artifact for dist: $f (bin/$TARGET_ARCH/$f not built)"
    fi
done

(
    cd "$DIST_DIR"
    sha256sum "${artifacts[@]}" > SHA256SUMS
)

repo_rev="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
built_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

export LINUX_VERSION ENVD_TAG SANDBOXER_COMMIT GUEST_RUNTIME_COMMIT \
    ACCELERATOR_COMMIT CLOUD_HYPERVISOR_COMMIT EROFS_UTILS_TAG

python3 - "$DIST_DIR/manifest.json" "$TARGET_ARCH" "$tarball_name" "$tarball_sha" \
    "$built_at" "$repo_rev" "${artifacts[@]}" <<'EOF'
import hashlib
import json
import os
import sys

manifest_path, arch, tarball_name, tarball_sha, built_at, repo_rev = sys.argv[1:7]
artifacts = sys.argv[7:]
dist = os.path.dirname(manifest_path)

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

manifest = {
    "schema": 1,
    "generator": "tt-artifacts",
    "architecture": arch,
    "built_at": built_at,
    "tt_artifacts_revision": repo_rev,
    "pins": {
        "linux": {"version": os.environ.get("LINUX_VERSION", "")},
        "envd": {"tag": os.environ.get("ENVD_TAG", "")},
        "sandboxer": {"commit": os.environ.get("SANDBOXER_COMMIT", "")},
        "guest_runtime": {"commit": os.environ.get("GUEST_RUNTIME_COMMIT", "")},
        "accelerator": {"commit": os.environ.get("ACCELERATOR_COMMIT", "")},
        "cloud_hypervisor": {"commit": os.environ.get("CLOUD_HYPERVISOR_COMMIT", "")},
        "erofs_utils": {"tag": os.environ.get("EROFS_UTILS_TAG", "")},
        "ubuntu_rootfs": {"file": tarball_name, "sha256": tarball_sha},
    },
    "files": {name: {"size": os.path.getsize(os.path.join(dist, name)),
                     "sha256": sha256(os.path.join(dist, name))}
              for name in artifacts},
}
with open(manifest_path, "w") as f:
    json.dump(manifest, f, indent=2, sort_keys=True)
    f.write("\n")
EOF

log "dist/$TARGET_ARCH assembled:"
ls -lh "$DIST_DIR" | awk 'NR>1 {print "  " $5 "\t" $9}'
