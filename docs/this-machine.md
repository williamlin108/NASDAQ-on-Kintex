# This machine

Facts about the reference machine (the one this setup was built on), and every file
the setup created or changed on it, with how to undo each. Last checked 2026-10-28.

## Hardware and OS

| Item | Value |
|---|---|
| OS / kernel | Ubuntu 26.04.1 LTS, Linux 7.0.0-38-generic |
| CPU / RAM | Intel Core Ultra 7 265K (20 cores, single socket, one NUMA node), 45 GB |
| NIC | ConnectX-4 Lx (MT27710), dual port, Dell firmware 14.32.2004 (DEL2420110034) |
| Port 0 (Ethernet 1) | PCI `0000:85:00.0`, interface `enp133s0f0np0`, verbs `rocep133s0f0`, MAC 1c:34:da:72:c4:9e |
| Port 1 (Ethernet 2) | PCI `0000:85:00.1`, interface `enp133s0f1np1`, verbs `rocep133s0f1`, MAC 1c:34:da:72:c4:9f |
| Verbs device names | `rocep133s0f0`/`rocep133s0f1` since the 2026-10-28 reboot (rdma-core's udev rule renames them by PCI slot); they were `mlx5_0`/`mlx5_1` before. DPDK uses PCI addresses, so the names don't matter |
| Other network | Realtek RTL8125 `enp132s0` (normal LAN), Wi-Fi `wlp131s0`, `tailscale0` |

## Installed software

| Package(s) | Version |
|---|---|
| `dpdk`, `dpdk-dev`, `libdpdk-dev` (includes the mlx5 driver) | 25.11-2 (DPDK 25.11.0 LTS) |
| `rdma-core`, `libibverbs1`, `libibverbs-dev`, `ibverbs-providers`, `ibverbs-utils` | 61.0-2ubuntu3 |
| `meson` / `ninja-build` | 1.10.1 / 1.13.2 |
| `infiniband-diags`, `mstflint`, `ethtool`, `pkg-config`, `python3-pyelftools`, `libnuma-dev`, `libpcap-dev` | archive versions |
| `shellcheck`, `python3-markdown` | archive versions (script linting, HTML user guide) |
| Toolchain | gcc/g++ 15, gdb 17.1, clangd 21, cmake 4.2, bear 3.1 |
| VS Code (snap, classic) | extensions: clangd, C/C++ (debugger only), Meson |

DPDK is installed in system paths: headers in `/usr/include/dpdk`, libraries in
`/usr/lib/x86_64-linux-gnu`, driver plugins in `/usr/lib/x86_64-linux-gnu/dpdk/pmds-26.0`,
tools (`dpdk-testpmd`, `dpdk-hugepages.py`, `dpdk-devbind.py`) in `/usr/bin`.

## Files created or changed outside the repo

| Path | What | Undo |
|---|---|---|
| `/etc/sysctl.d/80-hugepages.conf` | `vm.nr_hugepages = 2048` (4 GB of 2 MB pages at every boot) | `sudo rm` it, then `sudo sysctl vm.nr_hugepages=0` |
| `~/.local/bin/dpdk-caps` | Copy of `capsh` with file caps `cap_net_admin,cap_net_raw,cap_ipc_lock=p` | `rm` |
| `~/.local/bin/dpdk-run` | Launcher that passes those caps to a program (source: `Installation/bin/`) | `rm` |
| `~/.local/bin/dpdk-gdb` | gdb started through `dpdk-run`; used by F5 (source: `Installation/bin/`) | `rm` |
| `~/.config/Code/User/settings.json` | `mesonbuild.buildFolder: "build"`, `mesonbuild.downloadLanguageServer: true` (and the earlier clangd settings) | delete those lines |
| `/etc/sudoers.d/claude-apt` | Passwordless `sudo apt-get update` / `install` (from the earlier dev setup) | `sudo rm` |
| apt packages | See [Installed software](#installed-software) | `sudo apt-get remove ...` |

## Verification log

| Date | Check | Result |
|---|---|---|
| 2026-10-27 | Both ports open through `dpdk-run` without sudo (`./run`, testpmd) | Pass |
| 2026-10-27 | F5 through VS Code's debug adapter: breakpoints, variables, watch, step, arguments | Pass |
| 2026-10-27 | New project via the user guide steps / `new-project.sh`, end to end | Pass |
| 2026-10-27 | DPDK 25.11 source build (`build-dpdk-from-source.sh --no-install`) incl. mlx5 driver | Builds (not run on the card: blocked by the agent's permission rules) |
| 2026-10-28 | After reboot: 2048 hugepages reserved, no leftover `rtemap_*` | Pass |
| 2026-10-28 | `Installation/verify.sh --full` | All checks passed |
| 2026-10-28 | Scripts and `main.c` restructured into one-sentence functions + small `main` (per `docs/coding-standards.md`): `install.sh --dry-run` output identical, `verify.sh` same results, `new-project.sh` all modes, F5 test, HTML guide byte-identical | Pass |

Not yet tested: link up and real packet send/receive (no cable between the ports yet).
