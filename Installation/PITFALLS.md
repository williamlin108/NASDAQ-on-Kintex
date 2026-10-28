# Pitfalls (all hit for real while building this setup)

Each entry: **symptom → cause → fix**. The scripts already handle the ones marked
*(handled)*; they're listed so nobody "fixes" the scripts back into the bug.

## Driver stack

### 1. Installing MLNX_OFED / DOCA "because it's an NVIDIA card"
- **Cause:** not needed. The kernel's inbox `mlx5_core`/`mlx5_ib` plus distro
  `rdma-core` is a supported configuration for DPDK's mlx5 PMD. OFED/DOCA replaces
  rdma-core with its own copies, so mixing it with distro DPDK breaks in confusing ways,
  and DOCA doesn't support every distro release (e.g. Ubuntu 26.04).
- **Fix:** don't install it. `install.sh` refuses to run if it's present. *(handled)*

### 2. Binding the ports to vfio-pci with dpdk-devbind.py
- **Cause:** most DPDK guides say to, but mlx5 is a *bifurcated* driver: DPDK runs on
  top of the kernel driver through verbs. Binding to vfio-pci makes mlx5 unusable.
- **Fix:** keep them on `mlx5_core`. No IOMMU/vfio setup is needed. `verify.sh` fails
  if a port is bound to anything else. *(checked)*

## DPDK version

### 3. Different distro releases ship different DPDK versions
- **Symptom:** code that builds on one machine doesn't on another, or behaves differently.
- **Cause:** Ubuntu 26.04 = 25.11, Debian 13 = 24.11, Ubuntu 24.04 = 23.11, Ubuntu
  22.04 = 21.11.
- **Fix:** `install.sh --dpdk auto` (default) uses the distro package only if it's
  25.11, and otherwise builds 25.11 from source into `/usr/local`. *(handled)*

### 4. Source build: `undefined reference to vtable for std::__cxx11::basic_ostringstream` linking `librte_net_mlx5.so`
- **Cause:** the `mstflint` package installs a static `libmtcr_ul.a`. DPDK's mlx5
  build finds it automatically (`cc.find_library('mtcr_ul')`), then links it without
  libstdc++. There is no meson option to turn it off.
- **Fix:** `tools/build-dpdk-from-source.sh` edits that one line in the unpacked
  source so the lookup is skipped, matching how Ubuntu builds its package. The script
  aborts if a future DPDK version changes the line. *(handled)*

### 5. Two DPDKs installed at once (distro packages + /usr/local source build)
- **Symptom:** wrong headers, or mismatched PMD plugin directories at runtime.
- **Fix:** exactly one. `install.sh --dpdk source` refuses while distro DPDK packages
  are installed, and `verify.sh` fails if it finds both. *(handled)*

### 6. Verbs device names change (`mlx5_0` → `rocep133s0f0`)
- **Symptom:** a check or script looking for `mlx5_0`/`mlx5_1` in `ibv_devices` fails
  after the first reboot following the rdma-core install.
- **Cause:** rdma-core's udev rule (`60-rdma-persistent-naming.rules`, `rdma_rename
  NAME_FALLBACK`) renames RDMA devices by PCI slot when they appear at boot.
- **Fix:** never depend on verbs names. Map via the PCI address
  (`/sys/bus/pci/devices/<pci>/infiniband/`); DPDK's `-a <pci>` already does. *(handled in verify.sh)*

## Running without root

### 7. `mlx5_common: DevX create TIS failed errno=121 ... syndrome=0x6a6678`
- **Cause:** the process lacks `CAP_NET_RAW`. Creating mlx5 send-side DevX objects needs it.
- **Fix:** run through `dpdk-run` (or sudo). *(handled by ./run and F5)*

### 8. Capabilities set on the program itself disappear
- **Cause:** `setcap` on `build/myprog` is wiped every time ninja relinks it.
- **Fix:** `~/.local/bin/dpdk-caps` (a copy of `capsh` with file caps) raises them as
  *ambient* capabilities and execs the program, so they survive rebuilds and are
  inherited by gdb's child. Copying or replacing `dpdk-caps` strips its caps; re-run
  `install.sh`. *(handled)*

### 9. File caps silently ignored
- **Cause:** home directory on a `nosuid` mount, or a filesystem without xattr/caps
  support (some NFS homes).
- **Fix:** `install.sh` stops if `~/.local/bin` is mounted nosuid. On NFS, move `BIN`
  to a local disk. *(checked)*

### 10. `Cannot create lock on '/dev/hugepages/...'` / permission errors on hugepages
- **Cause:** `/dev/hugepages` is root-owned (0755).
- **Fix:** always pass `--in-memory` (it's in every `eal.conf`). It uses anonymous
  hugepage memory, creates no files, and selects IOVA mode VA (fine for mlx5, and no
  `/proc/self/pagemap` access needed). *(handled)*

### 11. Leftover `/dev/hugepages/rtemap_*` files holding memory
- **Cause:** a `sudo` run without `--in-memory`.
- **Fix:** `sudo rm /dev/hugepages/rtemap_*` or reboot. Runs via `dpdk-run`
  never leave these, even when killed with `kill -9`.

### 12. Hugepages gone after reboot
- **Cause:** `dpdk-hugepages.py --setup` / writing `/proc/sys/vm/nr_hugepages` is runtime-only.
- **Fix:** `/etc/sysctl.d/80-hugepages.conf`. *(handled)*

### 13. Scripts work in one terminal but not another / from VS Code
- **Cause:** `~/.local/bin` or `/usr/sbin` missing from PATH (`getcap` lives in `/usr/sbin`).
- **Fix:** all scripts call each other and `getcap`/`gdb` by absolute path. Don't
  "simplify" that away. *(handled)*

## VS Code

### 14. Meson extension creates `builddir/`, so clangd and the build disagree
- **Fix:** user setting `"mesonbuild.buildFolder": "build"`. *(handled)*

### 15. Meson extension writes `.vscode/settings.json` with absolute paths
- **Fix:** git-ignored in the template. It configures cpptools IntelliSense, which is
  disabled anyway (clangd does IntelliSense). *(handled)*

### 16. F5 can't open the ports
- **Cause:** plain `gdb` has no capabilities.
- **Fix:** `miDebuggerPath` = `~/.local/bin/dpdk-gdb` (`dpdk-run /usr/bin/gdb`). *(handled)*

### 17. F5 program gets no / wrong arguments
- **Cause:** launch.json can't read eal.conf.
- **Fix:** preLaunchTask writes `build-debug/args.gdb` (`set args ...`), loaded via
  `setupCommands`. **Don't add `"args"` to launch.json:** the C++ extension would then
  send `-exec-arguments` and override it. *(handled)*

### 18. Variables show `<optimized out>` while debugging
- **Fix:** F5 uses a separate `build-debug/` (`--buildtype=debug`). `build/` stays
  `debugoptimized` for performance. *(handled)*

### 19. Flatpak VS Code
- **Cause:** sandboxed, so dpdk-gdb/./run from inside it can't get capabilities.
- **Fix:** use the .deb or snap (classic) build. `install.sh` warns. *(checked)*

### 20. Ctrl+Shift+B says "No build task to run found", F5 asks which debugger to use
- **Cause:** VS Code was opened on the repo root (`~/dpdk-projects`) instead of a
  project folder. Tasks and launch configs live in each project's `.vscode/`, which
  VS Code only reads from the opened folder.
- **Fix:** `code ~/dpdk-projects/projects/<name>`. A multi-root `.code-workspace` was
  considered and rejected: it makes Ctrl+Shift+B prompt for a project every time.

## Machine-specific values (don't copy between machines)

### 21. PCI addresses, NUMA layout
- `-a 85:00.0`-style addresses and `--socket-mem` per NUMA node differ per machine.
  `new-project.sh` detects them. For an existing project moved to another machine,
  fix the `-a` lines in `eal.conf` (`lspci -D -d 15b3:`).
  On multi-socket machines also pick `-l` cores on the NIC's node
  (`cat /sys/bus/pci/devices/<pci>/numa_node`, `lscpu`).

### 22. `-march=native` binaries
- Built for the CPU they're compiled on. Rebuild on each machine; don't copy binaries.

## For AI agents specifically

### 23. `sudo` in non-interactive shells
- Agents usually can't type a sudo password. On the reference machine a sudoers rule
  allowed **only** `sudo apt-get update` and `sudo apt-get install ...`, each as its
  own command. Chaining them in one sudo call (`sudo sh -c "apt-get update && ..."`)
  doesn't match the rule. Use `sudo -n` to test. Anything else (sysctl, setcap,
  install to /usr/local) must be run by the user, e.g. `! ./install.sh` in Claude Code.

### 24. `pkill -f <pattern>` killing the agent's own shell
- The agent's shell command line contains the pattern, so `pkill -f` / `pgrep -f | xargs kill`
  kills the shell itself (exit 144). Use a bracket trick (`pgrep -f '[O]penDebugAD7$'`)
  or kill by PID.

### 25. Testing F5 without a human
- You can't press F5, but `tools/test-f5.py <project>` drives the same debug adapter
  (OpenDebugAD7) VS Code uses. DAP messages arrive out of order (the launch response
  can come before `initialized`); the script keeps a backlog of unmatched messages. A
  naive client hangs forever.

### 26. Ubuntu blocks unprivileged user namespaces
- `kernel.apparmor_restrict_unprivileged_userns = 1`, so `unshare -r` tricks fail
  (`write failed /proc/self/uid_map`). Don't plan around them.

### 27. Messages that look like errors but aren't
| Message | Meaning |
|---|---|
| `EAL: No free 1048576 kB hugepages reported on node 0` | No 1 GB pages configured; only 2 MB are used |
| `mlx5_net: No available register for sampler.` | ConnectX-4 Lx lacks flow-sampling registers |
| `link down` | No cable / peer down |
| `ninja: no work to do.` | Up to date |
| clangd `--check`: `tweak: SwapBinaryOperands ==> FAIL` | clangd self-test of a refactoring, not a code error |
| clangd errors (`'rte_eal.h' file not found`) in `Installation/template/src/main.c` | The template is never built, so it has no `compile_commands.json`. Projects made from it are fine |
