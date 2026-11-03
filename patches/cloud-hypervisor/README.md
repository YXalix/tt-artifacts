# VMM process prewarming（VMM 进程预热）

These eight patches add generic/profile prewarming and a block-backing capacity
query fix to official
Cloud Hypervisor `main`, pinned at
`640566123b7cca6ffbea85b0f19eb477a351a82f` (2026-09-08). Template prewarm denotes a fully
restored, paused instance using upstream `CopyOnWrite` and `resume:false`.
There is no custom template prewarm API, memory-restore phase, hotset or KVM prefetch patch.
Historical series and validation remain available in Git history.

## Prewarm modes and patch boundaries

| Patch | Responsibility |
| --- | --- |
| 01 | Cache immutable device seccomp programs |
| 02 | generic prewarm: explicitly create an empty ordinary KVM VM |
| 03 | generic prewarm: precompile device seccomp programs |
| 04 | profile prewarm: reserve KVM vCPU descriptors for the CPU profile |
| 05 | profile prewarm: reserve one-shot device workers through activation context |
| 06 | profile prewarm: reserve pristine PCI queue kick eventfds through the same resource path |
| 07 | generic/profile prewarm capability declaration, owned state, retries and profile transitions |
| 08 | Query block-device capacity for CopyOnWrite snapshot backing; retain the saved-range lower bound |

Apply patches in `series` order. A focused patch is not necessarily applicable
independently to the upstream base. Patch 07 supplies the structured v2
capability and generic/profile prewarm lifecycle contract used by TT when prewarming. It contains no template-memory preparation.

- **Generic prewarm（通用预热）:** no template or vCPU count is selected. An idle process owns
  the empty ordinary KVM VM and compiled seccomp cache.
- **Profile prewarm（规格预热）:** reserves the specified kernel vCPU descriptors, independently
  of guest image. CPU IDs must match the eventual boot count/topology. Optional
  device fields reserve workers and queue kick eventfds. vCPU execution threads
  remain in normal initialization.
- **Template prewarm（模板预热）:** restores RAM mappings, registers memory and initializes
  CPU and device state with upstream restore, then waits for `vm.resume`.

Worker and queue-eventfd preparation are independent profile prewarm patches after vCPU
reservation. One VM-owned `DeviceResources` object passes through
VM construction, DeviceManager, PCI transport and `ActivationContext` to the
existing `WorkerThreads` collection. The `VirtioDevice` trait is unchanged;
participating devices forward one optional activation-context field. The
ordinary seccomp installation and panic/error wrapper still run before each
handler. No global or thread-local pool is introduced.

Only initial activation can consume workers. Hotplug, reset and subsequent
activation allocate normally. Unused workers close their channels and join;
consumed handles keep the existing device cleanup rules. Only pristine PCI
queue kick eventfds are reserved, transferred once and never recycled. Kill,
pause, MSI-X and interrupt descriptors keep their normal allocation paths.

Set cgroups, NUMA policy, nice level and inherited placement before preparation,
keep them stable, and do not reconfigure parked workers individually. Worker
reuse requires the creating VMM thread and unchanged affinity, signal mask,
and scheduler policy/priority. A mismatch falls back to ordinary creation.
Landlock-enabled restores discard device reservations so new workers inherit
restrictions at the normal activation point. Only read-only scheduler queries
are added to VMM seccomp; device filters remain unchanged.

## API and ownership

Ping advertises the distinct draft contract:

```json
{"prewarm":{"version":2,"generic_prepare":true,"profile_prepare":true}}
```

| Operation | Request/result |
| --- | --- |
| generic prewarm | `PUT /api/v1/vmm.prepare` with `{}` |
| profile prewarm | Same endpoint with `{"vcpu_ids":[0,1],"block_queues":[1],"console":true,"rng":true}` |
| generic/profile prewarm response | `{"vm":true,"vcpus":2,"workers":3,"eventfds":4}` for the example prewarm profile |
| template prewarm | `PUT /api/v1/vm.restore` with `CopyOnWrite`, `prefault:false`, `resume:false` |
| Start template prewarm | `PUT /api/v1/vm.resume` without a body |
| Release | `vm.delete`; reap the VMM before releasing its disks and immutable backing |

Device capacity hints are optional: `block_queues` gives queues per block
device; `net_queues` gives even RX/TX queue counts per network device, excluding
control queues; `console`, `rng`, `vsock` and `balloon` are booleans; `pmem`
is a device count. There are at most 32 block/network/PMEM devices, 64 queues
per listed device, 256 workers and 4096 reserved eventfds. Network workers
use one per queue pair plus one control worker. Actual topology may consume
fewer resources or use ordinary allocation after exhaustion. A device-only
profile uses profile prewarm even when `vcpu_ids` is empty. Generic prewarm reports zero workers/eventfds.

Generic prewarm can upgrade to profile prewarm; identical profiles can be retried. A nonempty profile
cannot be rebound. One owned generic/profile state transfers resources into
ordinary VM construction. Invalid profile requests retain the reserve;
allocation failures after consumption drop it. Delete discards idle reserves.
Ordinary create drops them, while receive-migration requires deleting them first.

## Template prewarm: upstream paused restore

Prepare a complete per-instance restore configuration, then issue:

```sh
curl --unix-socket "$CH_SOCKET" -X PUT \
  -H 'Content-Type: application/json' \
  -d '{"source_url":"file:///srv/instances/example/restore","memory_restore_mode":"CopyOnWrite","prefault":false,"resume":false}' \
  http://localhost/api/v1/vm.restore
```

On success, `vm.info` reports `Paused`. CH has restored CPU/device state and
created paused vCPU threads, but the guest has not executed. Assignment starts
it through the upstream API:

```sh
curl --unix-socket "$CH_SOCKET" -X PUT http://localhost/api/v1/vm.resume
```

Template prewarm can use an ordinary VMM or consume a generic/profile prewarm reserve. Restore fixes each
instance's writable disk leases, TAP/vsock identity and backend resources;
these must be allocated before restore and retained for the paused instance.
Template prewarm occupies one complete instance slot and consumes more idle resources than
generic/profile prewarm. It is not a shared memory-only object and cannot be rebound by editing
the already-consumed config file.

`resume:false` controls execution, not page population. `CopyOnWrite` keeps
untouched memory demand-paged; this series provides no hotspot list, eager
write-CoW preparation or explicit KVM translation prefetch. Guest first-touch
faults can therefore remain after resume. No comparative latency claim is made.

## TT integration

TT negotiates structured prewarm v2 and uses generic prewarm or CPU-only profile prewarm
according to idle profile targets. Ordinary restore uses `resume:true`; the
optional template prewarm pool restores with `resume:false` and claims through
`vm.resume`. TT owns paused-instance reservations, policy and teardown; this
CH patch series provides generic/profile prewarm and uses upstream restore/resume APIs for template prewarm. Template Full pagecache
pre-reading remains independent of slots. See [the integration guide](../../docs/standalone/cloud-hypervisor-extensions.md)
for policy, identity constraints, capacity accounting and ownership.

If `vmm.ping` lacks compatible prewarm capabilities, TT skips `vmm.prepare`
and keeps an ordinary idle process. It is usable but counted as `unprepared`,
not as generic/profile prewarm. Ping errors and failed preparation still fail
the launch. This fallback changes neither the upstream restore API nor the
snapshot/backing compatibility requirements.

## Apply

Use an independently obtained clean upstream checkout, with `CH_SOURCE` set to
that checkout, and run these commands from the TT source root:

```sh
set -eu
test "$(git -C "$CH_SOURCE" rev-parse HEAD)" = 640566123b7cca6ffbea85b0f19eb477a351a82f
test -z "$(git -C "$CH_SOURCE" status --porcelain)"
while IFS= read -r patch; do
  git -C "$CH_SOURCE" am "$PWD/patches/cloud-hypervisor/$patch"
done < patches/cloud-hypervisor/series
```

Build the patched checkout using upstream instructions and the
`x86_64-unknown-linux-musl` or `aarch64-unknown-linux-musl` target to match the
validation host. ARM64 compilation uses Orb and hardware validation uses Lima
`dev-kvm`; x86_64 uses `gw-ubuntu` for both. Earlier validation records are available in
Git history; they do not replace validation of a newly built binary.
No upstream PR has been submitted.

Patch 08 replaces the snapshot backing metadata-length query with the existing
block capacity helper. Block devices can report `stat_size=0` even when their
capacity covers the saved ranges. The check still rejects backing shorter than
the saved ranges; it does not relax the capacity requirement or change mappings.
This compatibility fix is independent of generic/profile prewarming.
Restore uses anonymous private RAM zones (`file:null`),
with immutable backing at `source_url/memory-ranges`. The caller must provide
backing compatible with upstream's size checks and mapping requirements.
Upstream Copy fallback behavior is unchanged: passthrough, KSM, resizable RAM
and unsupported zone layouts may trigger it. Too-short or unmappable backing
fails restore. The prewarm capability does not advertise block-backing support.
