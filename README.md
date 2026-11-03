# tt-artifacts

构建 tfc-server 启动和验证沙箱所需的全部制品：Guest 内核 `vmlinux`、bootstrap `rootfs.erofs`、业务镜像 `base.erofs`、Guest 代理 `envd`，以及打了补丁的 Cloud Hypervisor。支持 x86_64 和 aarch64，所有上游输入均固定版本并记录校验和，本地 Makefile 与 GitHub Actions 都能一键构建。

## 产物清单

| 产物 | 说明 | 来源（固定版本） |
| --- | --- | --- |
| `vmlinux` | Guest 内核。x86_64 为 ELF（PVH 启动），aarch64 为 PE Image（EFI stub + ACPI） | linux-6.1.169 LTS + `config/sandbox-*.config` 片段（取自 kuasar-sandbox/guest-runtime） |
| `rootfs.erofs` | bootstrap（裸 EROFS，未压缩、禁用 inline data、2 MiB 对齐）。`/sbin/init` = sandbox-init，`/opt/sandbox-runtime/bin/{envd,flatten-ctl,mkfs.erofs}` | sandboxer `8aefa222` + 本仓库 TF 补丁；envd = e2b-dev/runtime `2026.22`；flatten-ctl = guest-runtime `9cda6a9`；mkfs.erofs = erofs-utils `v1.9.4` |
| `base.erofs` | 业务根文件系统（裸 EROFS，未压缩）。只读 lower 层，与现有 `tt-resource` 资源包一致（Ubuntu Noble，`/home/ubuntu`） | Ubuntu 24.04 cloud rootfs（cloud-images.ubuntu.com，带 SHA256） |
| `envd` | E2B Guest 代理（也单独提供） | e2b-dev/runtime `2026.22` |
| `cloud-hypervisor` | VMM，上游固定基线 + TF 8 个补丁（seccomp 缓存、通用/规格预热、块设备容量查询） | cloud-hypervisor `640566123b7c` + `patches/cloud-hypervisor/series` |
| `sandbox-init` | Guest PID 1（也单独提供） | sandboxer `8aefa222` + `patches/sandbox-init/`（vsock EOF、共享 ext4 lower、unmounted bootstrap） |
| `flatten-ctl`、`mkfs.erofs`、`fsck.erofs`、`dump.erofs` | Guest 内 OCI 拉平工具；镜像构建与校验工具 | guest-runtime / erofs-utils |

所有固定版本集中在 [`pins.sh`](pins.sh)，构建出的 `dist/<arch>/manifest.json` 会记录本次构建使用的全部 pin 与产物 SHA256。

补丁基线已逐个验证：三个 sandbox-init 补丁在 `8aefa222` 干净套用；八个 CH 补丁在 `640566123b7c` 按 `series` 顺序干净套用；linux 补丁目录当前为空（纯上游 + 配置片段）。

## 本地构建

要求：Linux，bash 5+，gcc/make，bc、bison、flex、libelf/libssl 头文件（内核），Go ≥1.25（`GOTOOLCHAIN=auto` 自动拉取所需版本），Rust stable（CH），autoconf/automake/libtool（erofs-utils）。交叉编译用 `x86_64-linux-gnu-` / `aarch64-linux-gnu-` 前缀；CH 跨架构还需对应 rustup target 和链接器。

```sh
git clone https://github.com/YXalix/tt-artifacts.git
cd tt-artifacts

make all                    # 本机架构的全部制品
make dist                   # 再汇编 dist/<arch>/（含 SHA256SUMS、manifest.json）

make all TARGET_ARCH=aarch64   # 指定架构
make vmlinux rootfs            # 只跑部分目标（见 make help）
```

产物布局（`make dist` 之后）：

```text
dist/<arch>/
├── vmlinux  rootfs.erofs  base.erofs  cloud-hypervisor
├── envd  sandbox-init  flatten-ctl  mkfs.erofs  fsck.erofs  dump.erofs
├── SHA256SUMS
└── manifest.json
```

常用环境变量：`BUILD_JOBS`（并行度，默认 nproc）、`TARGET_ARCH`、`TARBALL_CACHE`（tarball 共享缓存）、`TT_ARTIFACTS_BUILD_DIR`（构建工作区位置）、`MKFS_EROFS`/`FSCK_EROFS`（镜像工具路径覆盖）。网络受限时可为 Go 构建设置 `GOPROXY=https://goproxy.cn,direct`。

非 root 用户也可以构建：base 镜像里的 `/dev/*` 设备节点（mknod）和 0000 权限目录（如 snapd `void`）需要特权，脚本会自动用 sudo 重试该步，再把产物属主交还；无 sudo 时请用 root 运行对应目标。

## GitHub Actions

- `build.yml`：push 到 main / PR / 手动触发。矩阵覆盖 x86_64（`ubuntu-24.04`）和 aarch64（`ubuntu-24.04-arm`，公开仓库免费原生 runner），产出 `tt-artifacts-<arch>` artifact。
- `release.yml`：推送 `v*` tag 时调用 build 工作流，将两个架构的产物打包为 `tt-artifacts-<arch>-<tag>.tar.gz` 并附 `SHA256SUMS` 发布到 GitHub Release。

## 接入 tfc-server 验证

把 `dist/<arch>/` 里的文件按架构放到任意目录（例如 `/srv/tt-components`），然后在 tfc-server 源码树生成 `tests/resources.conf`：

```sh
TT_COMPONENTS=/srv/tt-components          # 与本仓库 arch 保持一致
cat > tests/resources.conf <<EOF
TTLET_BIN=/root/openEuler/tfc-server/target/release/ttlet
TTCTL_BIN=/root/openEuler/tfc-server/target/release/ttctl
UBLKD_BIN=/root/openEuler/storage/ublkd/target/release/ublkd
CLOUD_HYPERVISOR_BIN=$TT_COMPONENTS/cloud-hypervisor
ROOTFS_EROFS=$TT_COMPONENTS/rootfs.erofs
KERNEL_IMAGE=$TT_COMPONENTS/vmlinux
BUSINESS_IMAGE=$TT_COMPONENTS/base.erofs
DISK_SIZE_MB=8192
ENVD_VERSION=<manifest.json 中 envd 的实际版本>
EOF

bash tests/single.sh --check-resources    # 静态检查
sudo POOL_CAPACITY=4 PROFILE_CPU_COUNT=1 PROFILE_MEMORY_MB=512 \
  WARMUP=0 SINGLE_SAMPLES=1 bash tests/single.sh
```

`tfclet`/`ttctl`/`ublkd` 在 tfc-server（及其依赖 ublk 仓库）按普通 `cargo build --release` 构建，不属于本仓库范围。注意不要混用不同架构的组件；`ENVD_VERSION` 填 envd 实际上报版本（见 `dist/<arch>/manifest.json`），bootstrap 内容变化后需要重新制作模板/快照。

## 目录结构

```text
├── pins.sh                    # 全部固定版本与校验和（唯一事实来源）
├── Makefile                   # make help 查看目标
├── scripts/                   # 每个产物一个构建脚本 + 公共助手
├── config/sandbox-*.config    # 内核配置片段（common + x86_64/arm64）
├── patches/
│   ├── kernel/                # 内核补丁（当前为空，机制保留）
│   ├── sandbox-init/          # TF PID 1 补丁 + README
│   └── cloud-hypervisor/      # TF CH 补丁 series + README
└── .github/workflows/         # build / release
```

## 幂等与增量

- tarball 下载一次后缓存（`build/tarball/`），带 SHA256 校验；
- git 源码树固定在 pin 提交；补丁可重复运行（已应用则跳过，基线漂移则拒绝）；
- 内核 kbuild 增量编译；Go 构建命中 `GOWORK=off` 缓存；
- `make clean` 删除 `build/ bin/ dist/`，回到全新状态。
