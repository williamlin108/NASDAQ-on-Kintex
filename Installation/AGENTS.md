# Agent instructions: reproduce the DPDK + mlx5 dev setup

You are setting up (or repairing) a machine for DPDK development on NVIDIA/Mellanox
ConnectX NICs, matching a known-good reference machine. Everything below was verified
on that machine. **Read [PITFALLS.md](PITFALLS.md) before changing anything**: every
item in it cost real debugging time.

## Target state (reference machine, verified 2026-10-27)

| Component | Reference |
|---|---|
| OS | Ubuntu 26.04 LTS, kernel 7.0, x86_64 |
| NIC | ConnectX-4 Lx, dual port, firmware 14.32.2004 |
| Kernel driver | inbox `mlx5_core` + `mlx5_ib` + `ib_uverbs` (**no MLNX_OFED/DOCA**, **no vfio**) |
| rdma-core | distro package, 61.0 |
| DPDK | **25.11 LTS**: distro package if the distro ships 25.11, else source build to `/usr/local` |
| Hugepages | 2048 x 2 MB, persistent via `/etc/sysctl.d/80-hugepages.conf` |
| Unprivileged runs | `~/.local/bin/dpdk-caps` (capsh copy, file caps `cap_net_admin,cap_net_raw,cap_ipc_lock=p`) + `dpdk-run` + `dpdk-gdb` |
| Build | meson + ninja, `build/` (debugoptimized) and `build-debug/` (debug, for F5) |
| Editor | VS Code (.deb or snap) with clangd (IntelliSense), cpptools (debugger only), Meson extension |

## Procedure

1. **Inspect first; don't assume.**
   ```
   ./verify.sh            # tells you what's already right
   ./install.sh --dry-run # shows exactly what would change
   ```
2. **Install.** `install.sh` needs sudo for several steps (apt, sysctl, setcap, and
   `/usr/local` for a source build). If you can't enter a password (check with
   `sudo -n true`), ask the user to run it themselves: in Claude Code, `! ./install.sh`.
   Don't try to replicate its steps one by one with partial sudo access. It's
   idempotent, so re-running it is always safe.
   - Options: `--dpdk auto|distro|source`, `--hugepages-mb N`, `--no-vscode`.
3. **Verify.** `./verify.sh --full`. It must end with `All checks passed.`
   `--full` creates a throwaway project, runs it, and runs a headless F5 debug session
   through VS Code's own debug adapter (`tools/test-f5.py`).
4. **Create projects** with `./new-project.sh <name>` (into `~/dpdk-projects/<name>`).
   It detects the machine's mlx5 PCI addresses and NUMA layout for `eal.conf`.
   Don't copy `eal.conf` `-a` lines between machines.

## Files

| Path | Purpose |
|---|---|
| `install.sh` | Idempotent installer (packages, DPDK, drivers check, hugepages, caps launcher, VS Code) |
| `verify.sh` | Read-only checks plus a live testpmd probe; `--full` adds the project/run/F5 test |
| `new-project.sh` | New project from `template/` |
| `template/` | meson.build, eal.conf, run, .vscode/{tasks,launch}.json, src/main.c, gitignore (`__NAME__`, `__PORTS__`, `__SOCKET_MEM__`, `__SOCKET_LIMIT__` placeholders) |
| `bin/dpdk-run`, `bin/dpdk-gdb` | Installed to `~/.local/bin` |
| `tools/build-dpdk-from-source.sh` | Pinned DPDK 25.11 build (SHA-256 checked, mtcr_ul workaround) |
| `tools/merge-vscode-settings.py` | Adds missing VS Code user settings without touching existing ones |
| `tools/test-f5.py` | Headless F5 test over the Debug Adapter Protocol |
| `PITFALLS.md` | Known problems, causes and fixes |

## How the run/debug workflow works (don't redesign it without reason)

- `eal.conf` (per project) holds EAL args, one or more per line, `#` comments, with
  optional program args after a `--` line. `./run` = `ninja -C build` + `dpdk-run
  ./build/<name> $(eal.conf)`. Ctrl+Shift+B runs `./run`.
- F5: preLaunchTask "DPDK: build debug" builds `build-debug/` and writes
  `build-debug/args.gdb`; launch.json loads it in `setupCommands` and uses
  `miDebuggerPath: ~/.local/bin/dpdk-gdb`. No `"args"` in launch.json (pitfall 16).
- Ambient capabilities are the key trick: they survive exec into a non-setuid binary
  and are inherited under ptrace, so both rebuilt binaries and gdb's child get them.

## Rules

- Never install MLNX_OFED/DOCA, never bind mlx5 ports to vfio-pci/uio, never run DPDK
  apps with sudo as the normal workflow (use `dpdk-run`; sudo leaves `rtemap_*` files).
- Keep exactly one DPDK installation.
- Keep `--in-memory` in every eal.conf.
- Keep absolute paths in scripts (`/usr/sbin/getcap`, `$HOME/.local/bin/dpdk-run`,
  `/usr/bin/gdb`). PATH differs between login shells, VS Code tasks, and agents.
- If you change a script, re-run `shellcheck -S warning` on it and `./verify.sh --full`.
- If you hit a new pitfall, add it to PITFALLS.md (symptom, cause, fix) so the next
  agent doesn't repeat it.
- Changing `DPDK_VERSION` means updating `SHA256` in `tools/build-dpdk-from-source.sh`.
  dpdk.org doesn't publish checksum files next to tarballs, so the pinned hash was
  recorded from the reference download.
