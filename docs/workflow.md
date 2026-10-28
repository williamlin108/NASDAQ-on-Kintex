# Development workflow

## Layout

All DPDK projects live in `~/dpdk-projects/`, one folder each. Copy this
project's `meson.build` as the template for a new project.

```
itch-replay/
├── meson.build              # C17 + C++20, debugoptimized, -march=native, libdpdk
├── src/main.c               # EAL init + per-port driver/MAC/link print (skeleton)
├── build/                   # meson build dir (git-ignored)
├── compile_commands.json -> build/compile_commands.json   # for clangd
├── eal.conf                 # DPDK EAL args: cores, hugepage MB, ports
├── run                      # build + dpdk-run with eal.conf args
├── build-debug/             # unoptimized build for F5 (git-ignored, auto-created)
├── .vscode/tasks.json       # "DPDK: build & run" -> ./run (default); "DPDK: build debug"
├── .vscode/launch.json      # F5 "DPDK: debug" via dpdk-gdb
└── docs/
```

## Build

```
meson setup build                # first time, or after a fresh clone
meson setup --reconfigure build  # after editing meson.build
ninja -C build                   # incremental build; "no work to do" = up to date
```

If the project folder is moved, `rm -rf build && meson setup build`, because the
build dir stores absolute paths.

## Run: `./run` and `eal.conf`

`./run` builds, then runs `dpdk-run ./build/itch-replay <args from eal.conf>`.
App args: put them at the bottom of `eal.conf` after a `--` line (shared with F5),
or one-off on the command line: `./run -- --file itch.bin`. Don't use both at once.

`eal.conf` holds the EAL args, one or more per line, with `#` comments. Memory:
`--socket-mem=256` (MB preallocated) and `--socket-limit=1024` (MB cap; grows on
demand). Both must fit in the system pool `vm.nr_hugepages` (2048 × 2 MB = 4 GB),
which is set system-wide in `/etc/sysctl.d/80-hugepages.conf`. Single NUMA node, so
one value each.

## Run without sudo: `dpdk-run`

mlx5 needs `CAP_NET_RAW` to create DevX send-side objects. Without it, probe
fails with `DevX create TIS failed errno=121 ... syndrome=0x6a6678`. File caps on
the program itself get wiped on every relink, so a launcher holds them instead:

- `~/.local/bin/dpdk-caps`: a copy of `/usr/sbin/capsh` with file caps
  `cap_net_raw,cap_net_admin,cap_ipc_lock+p` (one-time root setup, done).
- `~/.local/bin/dpdk-run`: a script that raises those caps as *ambient* caps and
  execs the given program, so a rebuilt binary inherits them.

```
dpdk-run ./build/itch-replay -l 0-1 --in-memory -a 85:00.0 -a 85:00.1
```

Use `--in-memory` when running unprivileged. It avoids creating files in the
root-owned `/dev/hugepages`, and DPDK picks IOVA mode `VA`, which mlx5 supports,
so no physical-address access is needed. Verified 2026-10-27: unprivileged EAL
init and memory setup succeed; only mlx5 probe fails without caps.

Fallback (always works): `sudo ./build/itch-replay -l 0-1 -a 85:00.0 -a 85:00.1`.

## VS Code

- Open with `code ~/dpdk-projects/itch-replay` (VS Code is the classic-confinement
  snap, so it can see the whole home folder).
- **Ctrl+Shift+B** runs task "DPDK: build & run" (`./run`).
- IntelliSense is **clangd** (cpptools IntelliSense disabled; cpptools kept for
  gdb). clangd reads `compile_commands.json`; its index goes in `.cache/` (git-ignored).
- Meson extension (`mesonbuild.mesonbuild`): user setting
  `"mesonbuild.buildFolder": "build"` so it shares the CLI build dir instead of
  creating `builddir/`. The Meson language server download is enabled.

- **F5** = launch config "DPDK: debug" (cppdbg). preLaunchTask "DPDK: build debug"
  does `meson setup build-debug --buildtype=debug` if missing, `ninja -C build-debug`,
  and writes `build-debug/args.gdb` (`set args <eal.conf contents>`), which
  launch.json loads via `setupCommands`. `miDebuggerPath` is `~/.local/bin/dpdk-gdb`
  (`dpdk-run /usr/bin/gdb "$@"`). The ambient caps survive into the debuggee because
  ptrace only ignores *file* caps. No `"args"` key in launch.json, so MIEngine doesn't
  override the gdb `set args`.
- Verified 2026-10-27 from the CLI: `dpdk-gdb -batch -x build-debug/args.gdb -ex 'break main' -ex run`
  hits the breakpoint with argc=10 and probes both mlx5 ports. Not yet verified by
  pressing F5 in the VS Code UI.

User settings: `~/.config/Code/User/settings.json`.
