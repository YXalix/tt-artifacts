# tt-artifacts — build the guest/host artifacts tfc-server needs to boot
# and verify sandboxes: vmlinux, rootfs.erofs (bootstrap), base.erofs,
# envd, and the patched cloud-hypervisor.
#
# Usage:
#   make all                       # everything for the host architecture
#   make all TARGET_ARCH=aarch64   # one architecture
#   make vmlinux rootfs            # selected targets
#   make dist                      # + assemble dist/<arch>/ with SHA256SUMS
#
# Cross builds: TARGET_ARCH != $(uname -m) uses the GNU cross prefix
# (x86_64-linux-gnu- / aarch64-linux-gnu-). Cloud Hypervisor additionally
# needs the matching rustup target + linker. Per-arch native builds run in CI.

SHELL := /bin/bash

HOST_ARCH := $(shell uname -m | sed 's/amd64/x86_64/;s/arm64/aarch64/')
TARGET_ARCH ?= $(HOST_ARCH)

SCRIPTS := scripts
export TARGET_ARCH

.PHONY: all dist erofs-utils sandbox-init flatten-ctl envd vmlinux cloud-hypervisor rootfs base-image clean help
.DEFAULT_GOAL := help

help:
	@echo "tt-artifacts — targets (TARGET_ARCH=$(TARGET_ARCH)):"
	@echo "  make erofs-utils      mkfs.erofs / fsck.erofs / dump.erofs (host + embedded)"
	@echo "  make sandbox-init     guest PID 1 with the TF patch series"
	@echo "  make flatten-ctl      in-guest OCI flattener"
	@echo "  make envd             E2B guest agent"
	@echo "  make vmlinux          guest kernel (x86_64 ELF / aarch64 Image)"
	@echo "  make cloud-hypervisor patched Cloud Hypervisor"
	@echo "  make rootfs           bootstrap rootfs.erofs (needs the four above)"
	@echo "  make base-image       business base.erofs (Ubuntu Noble)"
	@echo "  make all              everything"
	@echo "  make dist             assemble dist/$(TARGET_ARCH)/ + SHA256SUMS + manifest"

erofs-utils:
	bash $(SCRIPTS)/build-erofs-utils.sh

sandbox-init:
	bash $(SCRIPTS)/build-sandbox-init.sh

flatten-ctl:
	bash $(SCRIPTS)/build-flatten-ctl.sh

envd:
	bash $(SCRIPTS)/build-envd.sh

vmlinux:
	bash $(SCRIPTS)/build-vmlinux.sh

cloud-hypervisor:
	bash $(SCRIPTS)/build-cloud-hypervisor.sh

rootfs: erofs-utils sandbox-init flatten-ctl envd
	bash $(SCRIPTS)/build-rootfs.sh

base-image: erofs-utils
	bash $(SCRIPTS)/build-base-image.sh

all: vmlinux cloud-hypervisor rootfs base-image

dist: all
	bash $(SCRIPTS)/assemble-dist.sh

clean:
	rm -rf build bin dist
