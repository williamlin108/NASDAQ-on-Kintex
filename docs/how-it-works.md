# How it works

The technical background behind the workflow in the [user guide](user-guide.md):
why it's set up this way and what each piece does. Known problems and their fixes
are in [Installation/PITFALLS.md](../Installation/PITFALLS.md).

## Repo layout

```
~/dpdk-projects/                 git repo: github.com/williamlin108/NASDAQ-on-Kintex
├── docs/                        user guide (md + generated html), this file, this-machine.md
├── Installation/                install.sh, verify.sh, new-project.sh, template/, bin/, tools/
└── projects/<project>/
    ├── meson.build              C17 + C++20, debugoptimized, -march=native, dependency('libdpdk')
    ├── src/
    ├── eal.conf                 EAL args (cores, hugepage MB, ports) + optional "--" program args
    ├── run                      ninja -C build, then dpdk-run ./build/<project> <eal.conf> "$@"
    ├── compile_commands.json -> build/compile_commands.json   (for clangd)
    ├── .vscode/tasks.json       "DPDK: build & run" (default build task) and "DPDK: build debug"
    ├── .vscode/launch.json      F5 "DPDK: debug"
    ├── build/                   optimized build (git-ignored)
    ├── build-debug/             debug build for F5 (git-ignored, created on first F5)
    └── docs/                    project-specific notes and status
```

## Driver stack: inbox mlx5, no OFED, no vfio

DPDK's mlx5 driver (PMD) runs on top of the Linux kernel's own `mlx5_core` +
`mlx5_ib` + `ib_uverbs` modules, through the verbs library from the distro's
`rdma-core`. This is a supported NVIDIA configuration. MLNX_OFED/DOCA is deliberately
not used: it replaces rdma-core with its own copies, and DOCA doesn't support every
distro release.

mlx5 is a **bifurcated** driver: the ports stay bound to `mlx5_core` and keep their
Linux network interfaces. They must not be bound to `vfio-pci`/`uio`, and no IOMMU
setup is needed. While a DPDK program runs on a port, it receives that port's traffic.

## DPDK version

Everything targets **DPDK 25.11 LTS**. Ubuntu 26.04 ships it as a package; other
distros ship other versions, so `Installation/install.sh` builds 25.11 from source
there (`Installation/tools/build-dpdk-from-source.sh`). There must only ever be one
DPDK installation per machine. Projects find it with `pkg-config` (`libdpdk`).

## Running without root

DPDK on mlx5 needs three Linux capabilities, not full root:

| Capability | Why |
|---|---|
| `CAP_NET_RAW` | Create mlx5 DevX send/receive objects. Without it: `DevX create TIS failed errno=121` |
| `CAP_NET_ADMIN` | Port settings DPDK changes through the kernel (MAC address, promiscuous mode, MTU) |
| `CAP_IPC_LOCK` | Lock (pin) memory |

Capabilities attached to the program file are wiped every time ninja relinks it, so
a fixed launcher holds them instead:

- `~/.local/bin/dpdk-caps` is a copy of `/usr/sbin/capsh` with those three as file
  capabilities (permitted set). Created once with sudo.
- `~/.local/bin/dpdk-run <program> ...` uses it to raise them as **ambient**
  capabilities and then exec the program. Ambient capabilities pass through exec into
  ordinary binaries, so any freshly built program inherits them.
- `~/.local/bin/dpdk-gdb` is `dpdk-run /usr/bin/gdb "$@"`. Ambient capabilities are
  also inherited under ptrace (only *file* capabilities are ignored there), so the
  program gdb starts can open the ports too.

All three scripts use absolute paths (`/usr/sbin/getcap`, `/usr/bin/gdb`,
`$HOME/.local/bin/dpdk-run`) because PATH differs between login shells, VS Code
tasks, and agents.

### Memory: hugepages and --in-memory

- DPDK needs hugepages. The machine reserves a fixed pool of 2 MB pages at boot
  (`/etc/sysctl.d/80-hugepages.conf`); each project's `--socket-mem` (taken at
  startup) and `--socket-limit` (maximum) must fit inside it.
- `/dev/hugepages` is root-owned, so an unprivileged program can't create DPDK's
  usual hugepage files there. `--in-memory` uses anonymous hugepage memory instead:
  no files, freed automatically when the program exits (even after `kill -9`).
- Without root, DPDK can't read physical addresses and selects IOVA mode `VA`, which
  mlx5 supports.

## eal.conf and ./run

`eal.conf` is split into words (with filename globbing turned off) and passed to the
program after DPDK's own arguments are parsed by `rte_eal_init`. Anything after a `--`
line goes to the program itself. `./run` appends its own command-line arguments at
the end, so extra arguments land after the `eal.conf` ones.

## VS Code integration

- **IntelliSense:** clangd (`llvm-vs-code-extensions.vscode-clangd`) reads
  `compile_commands.json`, which meson generates in `build/`; each project has a
  symlink to it. Microsoft's C++ extension (`ms-vscode.cpptools`) has IntelliSense
  disabled and is kept only for its gdb debugger.
- **Meson extension:** the user setting `"mesonbuild.buildFolder": "build"` makes it
  share the terminal's build folder (its default would be `builddir/`). It writes
  `.vscode/settings.json` with machine-specific paths; that file is git-ignored.
- **Ctrl+Shift+B** is the default build task "DPDK: build & run", which runs `./run`.
- **F5** is the launch configuration "DPDK: debug" (`cppdbg`):
  1. preLaunchTask "DPDK: build debug" runs `meson setup build-debug --buildtype=debug`
     if needed, `ninja -C build-debug`, and writes `build-debug/args.gdb`
     (`set args <eal.conf>`).
  2. `setupCommands` sources `args.gdb`; `miDebuggerPath` is `~/.local/bin/dpdk-gdb`.
  3. `launch.json` deliberately has no `"args"` key. If it had one, the C++ extension
     would send its own arguments to gdb and override `args.gdb`.
- User settings live in `~/.config/Code/User/settings.json`. The installer adds only
  missing keys (`Installation/tools/merge-vscode-settings.py`).

## How it's tested

- `Installation/verify.sh` checks packages, drivers, permissions, hugepages, the
  launcher and VS Code, and opens the ports with testpmd through `dpdk-run`.
- `verify.sh --full` also creates a throwaway project, runs it, and runs a full F5
  session headlessly with `Installation/tools/test-f5.py`. That script drives the C++
  extension's own debug adapter (OpenDebugAD7) over the Debug Adapter Protocol with
  the project's real `launch.json`, so it tests what pressing F5 does.
