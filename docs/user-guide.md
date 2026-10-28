# DPDK user guide

How to work on the DPDK projects in this repo: opening, building, running, debugging,
making new projects, and what's different about this machine. Applies to every project
in `projects/`; examples use `itch-replay`.

Technical background (why things are set up this way) is in
[how-it-works.md](how-it-works.md). This machine's hardware, versions and installed
files are in [this-machine.md](this-machine.md). To set up another computer, see
[Installation/README.md](../Installation/README.md).

## Start here

1. **Open the project folder** in VS Code, not the repo root:
   ```
   code ~/dpdk-projects/projects/itch-replay
   ```
2. **Ctrl+Shift+B** builds and runs. **F5** debugs. No `sudo` needed.
3. Settings for a run (CPU cores, memory, network ports, program arguments) are in
   the project's `eal.conf`.

> **Why the project folder?** Ctrl+Shift+B and F5 are defined in each project's own
> `.vscode/` folder, and VS Code only reads `.vscode/` from the folder you opened. If
> you open `~/dpdk-projects` instead, Ctrl+Shift+B says "No build task to run found",
> F5 asks you to pick a debugger, and autocomplete may miss the DPDK headers. Git works
> either way. To switch projects use File → Open Recent, or one window per project.

## Quick reference

Terminal commands run inside the project folder (`cd ~/dpdk-projects/projects/<project>`).

| I want to… | Do this |
|---|---|
| Build and run | **Ctrl+Shift+B**, or `./run` |
| Debug | **F5** (set breakpoints first by clicking left of a line number) |
| Only build | `ninja -C build` (optimized) or `ninja -C build-debug` (debug build) |
| Pass arguments to my program | Add them to `eal.conf` after a `--` line (used by `./run` and F5) |
| One-off extra arguments | `./run --verbose` if `eal.conf` has a `--` line, otherwise `./run -- --verbose` |
| Change cores / memory / ports | Edit `eal.conf` and run again (no rebuild needed) |
| Stop a running program | **Ctrl+C** in its terminal |
| After editing `meson.build` | Nothing; the next build picks it up. If confused: `meson setup --reconfigure build` |
| Rebuild from scratch | `rm -rf build build-debug && meson setup build && ninja -C build` |
| New project | `~/dpdk-projects/Installation/new-project.sh <name>` |
| Commit and push | Ctrl+Shift+G in VS Code, or `git add -A && git commit -m "msg" && git push` |
| Check the whole setup | `~/dpdk-projects/Installation/verify.sh` |
| Check the cards are visible | `ibv_devices` (lists two devices, here `rocep133s0f0` and `rocep133s0f1`) |
| Check cable/link | `ip -br link \| grep enp133` (`UP` = link, `NO-CARRIER` = no cable/peer) |
| Check hugepages | `grep HugePages /proc/meminfo` |

## Building and running

```
./run          →  ninja -C build, then
                  dpdk-run ./build/<project> <arguments from eal.conf> <your extra arguments>
```

- `./run` always rebuilds first, so you never run stale code.
- `ninja: no work to do.` just means nothing changed since the last build.
- **Adding source files:** list each new `.c`/`.cpp` file in `executable(...)` in
  `meson.build`, e.g. `executable('itch-replay', 'src/main.c', 'src/itch.c', ...)`.
  The next build notices the change by itself.
- **Measure speed with `./run`**, which uses the optimized `build/`. `build-debug/`
  (used by F5) is unoptimized and much slower.

### eal.conf

DPDK's startup settings for the project, one or more per line, `#` starts a comment.

| Line | Meaning |
|---|---|
| `-l 0-1` | CPU cores to use (core 0 = main, core 1 = worker) |
| `--socket-mem=256` | MB of hugepage memory taken at startup |
| `--socket-limit=1024` | Maximum MB it may grow to |
| `--in-memory` | **Keep this.** It's what lets it run without sudo and leave no files behind |
| `-a 85:00.0`, `-a 85:00.1` | The two ConnectX ports (Ethernet 1 and 2). Remove a line to use one port |
| `--` then more lines | Optional: arguments for **your program** (both `./run` and F5 use them) |

The memory values must fit in the machine's hugepage pool (4 GB, see
[below](#4-gb-of-ram-is-reserved-for-hugepages)).

### dpdk-run

`dpdk-run` (in `~/.local/bin`) starts any program with just enough network
permissions for DPDK, so **you never need `sudo` to run DPDK programs**. `./run` and
F5 use it for you. To use it directly:

```
dpdk-run ./build/itch-replay -l 0-1 --in-memory -a 85:00.0 -a 85:00.1
dpdk-run dpdk-testpmd -l 0-1 --in-memory -a 85:00.1 -- -i
```

## Debugging (F5)

| Key | Action |
|---|---|
| Click left of a line number | Toggle a breakpoint (red dot) |
| **F5** | Start debugging / continue to the next breakpoint |
| F10 | Step over (run the current line) |
| F11 | Step into the function on this line |
| Shift+F11 | Step out of the current function |
| Shift+F5 | Stop debugging |
| Ctrl+Shift+F5 | Restart |

While paused, the left panel shows **Variables** (expand structs and pointers),
**Watch** (type any expression, e.g. `mbuf->pkt_len`) and **Call Stack**. In the
**Debug Console** you can type expressions, or gdb commands prefixed with `-exec`,
e.g. `-exec x/64xb rte_pktmbuf_mtod(m, char *)` to dump packet bytes.

What F5 does:

1. Runs the task "DPDK: build debug": builds an unoptimized copy in `build-debug/`
   (so variables aren't `<optimized out>` and stepping follows the source) and turns
   `eal.conf` into `build-debug/args.gdb`.
2. Starts gdb through `dpdk-gdb` (gdb wrapped in `dpdk-run`), so the program gets the
   same network permissions as `./run`.

Tips:

- A breakpoint in the packet send/receive loop pauses the whole program, so the card
  stops sending. Fine for checking packet contents, useless for measuring speed.
- If F5 fails before the program starts, run the task by hand to see the error:
  Ctrl+Shift+P → "Tasks: Run Task" → "DPDK: build debug".
- Don't add `"args"` to `launch.json`. It replaces the arguments from `eal.conf`.
- Command-line equivalent: `dpdk-gdb -x build-debug/args.gdb build-debug/itch-replay`.

## VS Code

### Shortcuts

| Shortcut | What it does |
|---|---|
| **Ctrl+Shift+B** | Build and run this project (`./run`) |
| **F5** | Build the debug version and start it in the debugger |
| Ctrl+Shift+P | Command palette (any command: "Meson: Build", "Reload Window", …) |
| Ctrl+\` | Open/close the built-in terminal |
| Ctrl+Space | Show autocomplete suggestions |
| F12 | Go to definition (works on DPDK functions like `rte_eth_tx_burst` too) |
| Alt+← | Go back after F12 |
| Shift+F12 | Find all references |
| Ctrl+Shift+O | Jump to a function in the current file |
| Ctrl+P | Open a file by name |
| Ctrl+Shift+G | Git / Source Control panel |
| Ctrl+Shift+M | Problems panel (compiler errors and warnings, clickable) |

Hovering over any `rte_*` function shows its documentation and signature.

### How it's configured

- **Autocomplete and error squiggles come from clangd**, not Microsoft's C++
  extension (that one is installed only for its debugger). clangd finds the DPDK
  headers through `compile_commands.json`, which meson writes. If autocomplete stops
  working after adding files, build once (Ctrl+Shift+B), then Ctrl+Shift+P →
  "clangd: Restart language server".
- **The Meson extension** uses the same `build/` folder as the terminal. It may create
  `.vscode/settings.json` in a project; that's expected and git-ignored.

## Making a new project

```
~/dpdk-projects/Installation/new-project.sh my-project
code ~/dpdk-projects/projects/my-project
```

The script copies the project template into `projects/my-project`, fills in this
machine's card addresses and memory layout in `eal.conf`, names the program
`my-project`, and builds it. Ctrl+Shift+B and F5 work straight away.

The project is part of the main repo. Commit it like any other change
(`git add . && git commit -m "Add my-project" && git push`), and don't `git init`
inside it.

## Useful DPDK tools

These need `dpdk-run` in front. 0 packets is normal until a cable is connected.

| Command | Use |
|---|---|
| `dpdk-run dpdk-testpmd -l 0-1 --in-memory -a 85:00.1 -- -i` | Interactive: `start`, then `show port stats all` to see packets arriving; `quit` to exit |
| `dpdk-run dpdk-testpmd -l 0-1 --in-memory -a 85:00.1 -- --forward-mode=rxonly --stats-period 1` | Print receive stats every second (Ctrl+C to stop) |

## What's different from a default Linux install

These were changed during setup. If something odd happens, check here first.

### 4 GB of RAM is reserved for hugepages

- **What:** `/etc/sysctl.d/80-hugepages.conf` reserves 2048 × 2 MB pages at every boot.
- **What you'll notice:** `free -h` and System Monitor show about 4 GB less available
  memory, even when no DPDK program is running. There's no CPU cost.
- **Change it** (512 = 1 GB, 0 = none), no reboot needed:
  ```
  echo 'vm.nr_hugepages = 512' | sudo tee /etc/sysctl.d/80-hugepages.conf && sudo sysctl -p /etc/sysctl.d/80-hugepages.conf
  ```
  Keep it at least as large as `--socket-limit` in your projects' `eal.conf`.
- **Undo:** `sudo rm /etc/sysctl.d/80-hugepages.conf && sudo sysctl vm.nr_hugepages=0`

### dpdk-run grants network permissions without sudo

- **What:** `~/.local/bin/dpdk-caps` is a copy of the system `capsh` tool with the
  `cap_net_raw`, `cap_net_admin` and `cap_ipc_lock` capabilities attached. `dpdk-run`
  and `dpdk-gdb` use it.
- **Security trade-off:** anything you start through `dpdk-run` can capture and send
  raw packets and change network settings. Don't run untrusted programs through it.
- **If it stops working** (`dpdk-caps missing or has no caps`): copying or replacing the
  file strips its capabilities. Re-run `~/dpdk-projects/Installation/install.sh`, or:
  ```
  sudo install -m 0750 -o wl -g wl /usr/sbin/capsh ~/.local/bin/dpdk-caps
  sudo setcap cap_net_raw,cap_net_admin,cap_ipc_lock+p ~/.local/bin/dpdk-caps
  ```
- **Undo:** `rm ~/.local/bin/dpdk-caps ~/.local/bin/dpdk-run ~/.local/bin/dpdk-gdb`

### Running with sudo leaves files behind

- `sudo ./build/itch-replay ...` **without** `--in-memory` creates root-owned files in
  `/dev/hugepages/` (e.g. `rtemap_0`) that keep memory reserved until a reboot or
  `sudo rm /dev/hugepages/rtemap_*`. Use `./run` or `dpdk-run` instead.

### The ConnectX ports are shared between Linux and DPDK

- The ports were **not** bound to `vfio-pci`, which many DPDK guides tell you to do.
  mlx5 doesn't need it, so **don't run `dpdk-devbind.py`** on them. They stay visible
  as normal network interfaces (`enp133s0f0np0`, `enp133s0f1np1`).
- **While a DPDK program runs on a port, it takes that port's traffic**, so `ping` or
  `tcpdump` on that interface won't see packets.
- **Once a cable is connected,** NetworkManager will try to get an IP address on those
  ports and may show a "Wired connection" that never finishes connecting. It's
  harmless. To stop it (lasts until reboot):
  ```
  sudo nmcli device set enp133s0f0np0 managed no && sudo nmcli device set enp133s0f1np1 managed no
  ```

### Passwordless sudo for package installs

- `/etc/sudoers.d/claude-apt` lets `sudo apt-get update` and `sudo apt-get install …`
  run **without a password**, so Claude can install packages. Everything else still
  asks for your password. Remove with `sudo rm /etc/sudoers.d/claude-apt`.

## Messages you can ignore

| Message | Meaning |
|---|---|
| `EAL: No free 1048576 kB hugepages reported on node 0` | No 1 GB pages configured; only 2 MB pages are used |
| `mlx5_net: No available register for sampler.` | The ConnectX-4 Lx lacks an optional feature (packet sampling) |
| `link down` | No cable connected, or the other end isn't up |
| `ninja: no work to do.` | Nothing changed since the last build |

## Troubleshooting

First run `~/dpdk-projects/Installation/verify.sh`. It checks the whole setup and
prints a `FAIL` line for anything wrong. Every known problem is explained in
[Installation/PITFALLS.md](../Installation/PITFALLS.md).

| Symptom | Fix |
|---|---|
| Ctrl+Shift+B says "No build task to run found", or F5 asks which debugger to use | You opened `~/dpdk-projects` or another parent folder. Open the project folder: `code ~/dpdk-projects/projects/<project>` |
| `dpdk-caps missing or has no caps` | Re-run `Installation/install.sh` (see [dpdk-run](#dpdk-run-grants-network-permissions-without-sudo)) |
| `DevX create TIS failed errno=121` | The program ran without permissions. Use `./run` or `dpdk-run` |
| `Requested device 0000:85:00.x cannot be used` | Same as above, or another DPDK program is using the card |
| `Cannot allocate memory` / `No available hugepages` | `grep HugePages /proc/meminfo`. Total 0: re-apply the sysctl. Free low: another DPDK program is running, or leftover `/dev/hugepages/rtemap_*` files |
| `Dependency "libdpdk" not found` | DPDK isn't installed: run `Installation/install.sh` |
| Autocomplete or red squiggles wrong | Build once, then Ctrl+Shift+P → "clangd: Restart language server" |
| Build errors after moving or renaming the project folder | `rm -rf build build-debug && meson setup build` (F5 recreates `build-debug`) |
| F5: ports can't be used | `launch.json` must use `dpdk-gdb` (`miDebuggerPath`), and `verify.sh` must show dpdk-caps OK |
| F5: my program gets no arguments | Check `build-debug/args.gdb` contains `set args ...`; run the task "DPDK: build debug". No `"args"` in `launch.json` |
| F5: variables show `<optimized out>` | `launch.json` `program` must point at `build-debug/`, not `build/` |
