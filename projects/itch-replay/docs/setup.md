# Machine and system setup

## Hardware

| Item | Value |
|---|---|
| OS / kernel | Ubuntu 26.04.1 LTS, Linux 7.0.0-38-generic |
| CPU / RAM | Intel Core Ultra 7 265K (20 cores, single socket, NUMA node -1), 45 GB |
| NIC | ConnectX-4 Lx (MT27710), dual port, Dell firmware 14.32.2004 (DEL2420110034) |
| Port 0 | PCI `0000:85:00.0`, netdev `enp133s0f0np0`, verbs `mlx5_0`, MAC 1c:34:da:72:c4:9e |
| Port 1 | PCI `0000:85:00.1`, netdev `enp133s0f1np1`, verbs `mlx5_1`, MAC 1c:34:da:72:c4:9f |
| Other NICs | Realtek RTL8125 `enp132s0` (normal LAN), Wi-Fi `wlp131s0`, `tailscale0` |

## Driver stack: inbox, no MLNX_OFED / DOCA

The kernel's own `mlx5_core` + `mlx5_ib` + `ib_uverbs` modules are used, with
Ubuntu's rdma-core userspace. MLNX_OFED/DOCA was deliberately **not** installed:
it does not target Ubuntu 26.04, and the upstream stack is a supported NVIDIA
configuration for DPDK.

mlx5 is a **bifurcated** driver: DPDK runs on top of the kernel driver through
verbs. Do **not** bind the ports to `vfio-pci` / `uio` with `dpdk-devbind.py`.
The netdevs stay usable alongside DPDK.

## Packages (apt, Ubuntu archive)

| Package(s) | Version |
|---|---|
| `dpdk`, `dpdk-dev`, `libdpdk-dev` (includes `librte_net_mlx5`, `librte_common_mlx5`) | 25.11-2 (DPDK 25.11.0 LTS) |
| `rdma-core`, `libibverbs1`, `libibverbs-dev`, `ibverbs-providers`, `ibverbs-utils` | 61.0-2ubuntu3 |
| `infiniband-diags`, `mstflint`, `ethtool` | archive versions |
| `meson` / `ninja-build` | 1.10.1 / 1.13.2 |
| `pkg-config`, `python3-pyelftools`, `libnuma-dev`, `libpcap-dev` | archive versions |

DPDK lives in system paths (headers `/usr/include/dpdk`, libs
`/usr/lib/x86_64-linux-gnu`, PMD plugins `/usr/lib/x86_64-linux-gnu/dpdk/pmds-*`,
tools `dpdk-testpmd`, `dpdk-hugepages.py`, `dpdk-devbind.py` in `/usr/bin`).
Projects find it with meson `dependency('libdpdk')`.

Checked 2026-10-27 after `apt-get update`: no newer dpdk/rdma packages available.

Toolchain from earlier setup: gcc/g++ 15, clangd 21, cmake 4.2, bear 3.1.

## Sudo

`/etc/sudoers.d/claude-apt` allows passwordless `sudo apt-get update` and
`sudo apt-get install *` only, each run as its own command (chaining them with
`&&` in one sudo call doesn't match the rule). Anything else needing root has to
be run by the user.

## Hugepages

- 2 MB pages; the hugetlbfs mount `/dev/hugepages` is set up by systemd
  (root-owned, mode 0755).
- Runtime reservation: `sudo dpdk-hugepages.py -p 2M --setup 4G` (2048 pages).
  **Lost on reboot.**
- Persistent (done 2026-10-27, `/etc/sysctl.d/80-hugepages.conf`):
  `echo 'vm.nr_hugepages = 2048' | sudo tee /etc/sysctl.d/80-hugepages.conf && sudo sysctl -p /etc/sysctl.d/80-hugepages.conf`
- Cost: the 4 GB is unavailable to other programs; no CPU cost.
- The EAL warning `No free 1048576 kB hugepages` is harmless (no 1 GB pages configured).
