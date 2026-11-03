#!/usr/bin/env bash
#
# tt-artifacts pinned upstream inputs — single source of truth.
#
# All build scripts source this file. Update a pin by changing the value here
# and revalidating the affected artifact; record the reason in the commit.

# Guest kernel: upstream LTS tarball from kernel.org.
LINUX_VERSION=6.1.169
LINUX_TARBALL="https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${LINUX_VERSION}.tar.gz"
LINUX_TARBALL_SHA256="ab28b4ca2a2eca38b3da9aa33b231288168c3560bbc866359045f1c8f4d48d94"

# E2B guest agent (envd): e2b-dev/runtime release tarball.
ENVD_TAG="2026.22"
ENVD_TARBALL="https://codeload.github.com/e2b-dev/runtime/tar.gz/refs/tags/${ENVD_TAG}#e2b-runtime-${ENVD_TAG}.tar.gz"
ENVD_TARBALL_SHA256="8f074b23dcb2c9db48f8e674a8ab8082b54a16088fb29b66376178feeb7fe040"

# Guest PID 1 (sandbox-init): kuasar-sandbox/sandboxer commit the TF patches
# were made against (verified: all three patches apply cleanly, builds CGO-free).
SANDBOXER_REPO="https://github.com/kuasar-sandbox/sandboxer.git"
SANDBOXER_COMMIT="8aefa222af40f019a99c1297f88a8f7c4288fba1"

# In-guest OCI flattener (flatten-ctl): kuasar-sandbox/guest-runtime plus its
# replaced sibling module kuasar-sandbox/accelerator (pinned together).
GUEST_RUNTIME_REPO="https://github.com/kuasar-sandbox/guest-runtime.git"
GUEST_RUNTIME_COMMIT="9cda6a9bea6951882b68575016c63d8d74cbcb78"
ACCELERATOR_REPO="https://github.com/kuasar-sandbox/accelerator.git"
ACCELERATOR_COMMIT="6ecec94495c0a255479f18e6219e52b4eb2408e7"

# Cloud Hypervisor baseline for the TF prewarm patch series (see
# patches/cloud-hypervisor/README.md; series applies cleanly at this commit).
CLOUD_HYPERVISOR_REPO="https://github.com/cloud-hypervisor/cloud-hypervisor.git"
CLOUD_HYPERVISOR_COMMIT="640566123b7cca6ffbea85b0f19eb477a351a82f"

# erofs-utils: upstream release used for mkfs.erofs / fsck.erofs / dump.erofs.
EROFS_UTILS_TAG="v1.9.4"
EROFS_UTILS_TARBALL="https://github.com/erofs/erofs-utils/archive/refs/tags/${EROFS_UTILS_TAG}.tar.gz#erofs-utils-${EROFS_UTILS_TAG}.tar.gz"
EROFS_UTILS_TARBALL_SHA256="7d135aa2550326a5acf20f53c518aea5a8900015ce50700044e40f818c31dd80"

# Business base image: Ubuntu Noble (24.04) cloud rootfs tarballs, per arch.
UBUNTU_SUITE="noble"
UBUNTU_VERSION="24.04"
UBUNTU_ROOTFS_BASE="https://cloud-images.ubuntu.com/releases/${UBUNTU_SUITE}/release"
UBUNTU_ROOTFS_AMD64="ubuntu-24.04-server-cloudimg-amd64-root.tar.xz"
UBUNTU_ROOTFS_ARM64="ubuntu-24.04-server-cloudimg-arm64-root.tar.xz"
UBUNTU_ROOTFS_AMD64_SHA256="ec6972af8ea2bd05c55299d204e5ae3f91769b84cfaec7395639d236a39f9a03"
UBUNTU_ROOTFS_ARM64_SHA256="b68ef0444ca56ce4f00ae7e8ccfb0c553ffbc92e4a1b14ed7dd8aa18c6d68652"
