# sandbox-init 补丁

`0001-report-vsock-eof.patch` 修复 Guest PID 1 的 vsock reader：对非空 buffer，系统调用返回 `(0, nil)` 表示连接已关闭，必须转换为 Go `io.EOF`。否则 `io.ReadFull` 会不断重试，导致 Guest 在 Host 关闭控制连接后持续占用 vCPU。零长度 buffer 仍返回 `(0, nil)`。

补丁适用于模块 `github.com/kuasar-sandbox/sandboxer` 中的 `cmd/sandbox-init`。输入来自维护的源码导出，未提供 Git revision；原始 `vsock.go` 的 SHA-256 为 `05b7546e1e9eefaaef026efe8bb0da5232557633878d75f75fa1ce4d59ded65b`。在独立的该模块源码根目录应用：

```bash
patch --dry-run -p1 < /path/to/0001-report-vsock-eof.patch
patch -p1 < /path/to/0001-report-vsock-eof.patch
CGO_ENABLED=0 go test ./cmd/sandbox-init ./pkg/mux ./pkg/proto ./internal/wireio
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags '-s -w' \
  -o sandbox-init ./cmd/sandbox-init
```

ARM64 构建使用同样命令并将 `GOARCH=amd64` 改为 `GOARCH=arm64`。两种架构均须应用 EOF 修复并重新物化快照。

回归测试通过真实 stream socket 的对端关闭验证 EOF 契约，包括 `io.ReadFull`。TT 不依赖该源码工作区；将独立构建、记录来源和校验和的静态二进制作为 bootstrap 镜像输入，替换 `/sbin/init`。

复用已有 bootstrap 内容时，先只读挂载镜像并核对文件大小和 SHA-256。提取工具对 chunked EROFS 的兼容性必须验证，不能仅凭退出码成功认定文件完整。新镜像使用未压缩、禁用 inline data 的 EROFS，并将文件大小向上补齐到 2 MiB 边界，以满足 CH 的 pmem 映射要求。镜像构建后再次只读挂载，验证除 `/sbin/init` 外所有文件内容、权限及符号链接保持一致。

变更 bootstrap 镜像后必须重新制作一次快照，并为新快照训练热集。旧 Full 快照包含旧 PID 1 的内存状态，单独替换镜像不能修复已保存的进程。随后复用新快照及其热集；不要复用旧附件或修改兼容性标识绕过检查。该修复不需要新增 CH API，标准 CH 也可使用。

## 共享 EROFS / ext4 lower

`0002-shared-ext4-lower.patch` 让双盘根目录的 `/dev/vda` 按 superblock 识别 EROFS 或 ext4，并保持只读；`/dev/vdb` 仍为每实例独占的 ext4 upper。ext4 lower 必须标记干净且无 pending journal recovery，以 `ro,noload` 挂载，禁止通过日志回放修改共享镜像。单盘 Direct 路径保持原有行为。

补丁输入为用户提供的 `sandbox-init-maintained-source-20260907.tar.gz`（源码归档，不限构建架构）；未提供 Git revision，输入 SHA-256 为 `31b7eab82e4dbc52e6f67327e165a2e050a2b5590f279e55d2bf8a1254b84f8e`，其中原始 `cmd/sandbox-init/main.go` SHA-256 为 `f5b714696248d26ffdbf05e241062b4635c311ee09f42bc636c73b7024d59de4`。该归档已包含 EOF 修复，不要重复应用 `0001`。保留归档中的 sibling Go 模块布局，在解压后的 `sandboxer` 根目录执行：

```sh
patch --dry-run -p1 < /path/to/0002-shared-ext4-lower.patch
patch -p1 < /path/to/0002-shared-ext4-lower.patch
CGO_ENABLED=0 GOTOOLCHAIN=go1.25.1 go test ./cmd/sandbox-init ./pkg/mux ./pkg/proto ./internal/wireio
CGO_ENABLED=0 GOTOOLCHAIN=go1.25.1 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags '-s -w' -o sandbox-init ./cmd/sandbox-init
```

ARM64 使用同一补丁，将上述 `GOARCH=amd64` 改为 `GOARCH=arm64`，在 Orb 编译 sandbox-init。旧 ARM bootstrap 若仅包含 EOF 修复，仍需应用 `0002`；不能因架构相同就视为包含共享 ext4 lower 支持。

在对应架构的验证主机（x86_64 的 `gw-ubuntu` 或 ARM64 的 Lima `dev-kvm`）重建 bootstrap：仅替换 `/sbin/init`，其余文件、权限、符号链接保持原样；按上文重建、挂载和核验 EROFS。更新后的 bootstrap 支持两种 lower 格式。旧 Full 模板的 bootstrap 摘要不匹配时应保留旧部署使用，或在新部署重新导入/制作；不能改兼容性 manifest 绕过检查。

发布验证应分别使用 EROFS 和 ext4 业务镜像，检查两个运行中 VMM 使用同一个只读基础 ublk 设备和不同的可写 diff 设备，修改 lower 文件触发 copy-up 后相互隔离，并覆盖 Full/Data 捕获、暂停恢复、节点重启、官方 SDK 与退出清理。

## 挂载前的可复用内核基线

`0003-unmounted-bootstrap.patch` 应用在同一已校验源码归档并完成 `0002` 之后。
按上述 Go 命令测试、构建，再只替换 bootstrap 的 `/sbin/init` 并核验镜像内容。

这是私有 Data pause/connect 的可选优化，不是普通启动、Full 或配套 Data Golden 恢复的前置条件。
这些已有路径直接使用原协议，旧 bootstrap 无需应用本补丁。仅 Data Bootstrap connect 探测基线能力；
旧 init 的普通 `hello` 会触发回收探测 VM 和冷启动兼容，新 init 则复用内核基线。
首次 Data connect 可能承担基线制作成本，后续缓存复用；Full 热池不再提前制作基线。
能力探测使用独占私有磁盘副本且不捕获内存，支持确认后另启空白盘 VM 制作基线；
这避免旧 init 并行挂载空白盘失败，也保证共享基线不包含业务数据。

只有带 `sandbox.bootstrap.gate=1` 的基线构建 VM 启用门控。PID 1 在 `/proc`、`/sys`、`/dev`
及两块空白盘就绪后通知宿主，在收到业务 launch spec 和挂载业务文件系统之前等待恢复。
宿主必须使用匿名内存和同容量空白盘；禁止针对已经挂载业务盘的内存重用此协议。
通知连接关闭后才允许捕获。恢复消息提供当前时间和新的 256 位宿主随机种子，Guest 必须成功
校时、重新播种内核随机数并用 `BLKFLSBUF` 清除两盘块缓存，才继续挂载及启动正常入口。
常规 Full 恢复仍走原有 restore 握手。两种路径均不自动改变 `/tmp` 挂载策略。

该补丁改变 bootstrap 摘要；必须重新制作模板，禁止修改旧快照的兼容性 manifest 绕过检查。
