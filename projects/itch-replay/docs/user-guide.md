# User guide

A practical cheat sheet for working on DPDK projects on this machine. For the
detailed "why" behind the setup, see [setup.md](setup.md) and [workflow.md](workflow.md).

---

## Quick reference

| I want to… | Do this |
|---|---|
| Open the project | `code ~/dpdk-projects/itch-replay` |
| Build **and** run | **Ctrl+Shift+B** in VS Code, or `./run` in a terminal |
| Only build | `ninja -C build` (optimized) / `ninja -C build-debug` (for debugging) |
| Run with arguments for my program | Put them in `eal.conf` after a `--` line (used by ./run **and** F5). One-off extras: `./run --verbose` if `eal.conf` already has a `--` line, otherwise `./run -- --verbose` |
| Debug | **F5** (set breakpoints first by clicking left of a line number) |
| Change cores / memory / ports | Edit `eal.conf`, then run again (no rebuild needed) |
| Rebuild from scratch | `rm -rf build && meson setup build && ninja -C build` |
| After editing `meson.build` | `meson setup --reconfigure build` |
| Stop a running program | **Ctrl+C** in its terminal |
| Commit and push | Ctrl+Shift+G in VS Code, or `git add -A && git commit -m "msg" && git push` |
| Check the cards are visible | `ibv_devices` (should list `mlx5_0`, `mlx5_1`) |
| Check cable/link state | `ip -br link \| grep enp133` (`UP` = cable connected, `NO-CARRIER` = no link) |
| Check hugepages | `grep HugePages /proc/meminfo` |

---

## VS Code

### Shortcuts

| Shortcut | What it does |
|---|---|
| **Ctrl+Shift+B** | **Set up for this project:** builds with ninja, then runs the program via `./run` |
| **F5** | **Set up for this project:** builds the debug version and starts it in the debugger |
| Ctrl+Shift+P | Command palette (search any command: "Meson: Build", "Reload Window", …) |
| Ctrl+\` | Open/close the built-in terminal |
| Ctrl+Space | Show autocomplete suggestions (clangd) |
| F12 | Go to definition (works on DPDK functions like `rte_eth_tx_burst`, too) |
| Alt+← | Go back after F12 |
| Shift+F12 | Find all references |
| Ctrl+Shift+O | Jump to a function in the current file |
| Ctrl+P | Open a file by name |
| Ctrl+Shift+G | Git / Source Control panel |
| Ctrl+Shift+M | Problems panel (compiler errors and warnings, clickable) |

Hovering over any `rte_*` function shows its documentation and signature.

### How it's configured

- **Autocomplete/errors come from clangd**, not Microsoft's C++ extension. The C++
  extension is installed only for its debugger. clangd learns the include paths from
  `compile_commands.json`, which meson generates. **If autocomplete stops
  working after adding files, run `ninja -C build`** (or Ctrl+Shift+B) so the file
  list updates, then Ctrl+Shift+P → "clangd: Restart language server".
- **Meson extension** is set to use the `build/` folder (user setting
  `mesonbuild.buildFolder`). Don't be surprised if it creates
  `.vscode/settings.json`; that's expected and git-ignored.

### Debugging (F5)

| Key | Action |
|---|---|
| Click left of a line number | Toggle a breakpoint (red dot) |
| **F5** | Start debugging / continue to next breakpoint |
| F10 | Step over (run the current line) |
| F11 | Step into the function on this line |
| Shift+F11 | Step out of the current function |
| Shift+F5 | Stop debugging |
| Ctrl+Shift+F5 | Restart |

While paused: the left panel shows **Variables** (expand structs/pointers), **Watch**
(type any expression, e.g. `mbuf->pkt_len`) and **Call Stack**. In the Debug Console
you can type expressions, or gdb commands prefixed with `-exec`, e.g.
`-exec x/64xb rte_pktmbuf_mtod(m, char *)` to dump packet bytes.

How it works:
- F5 first runs the task **"DPDK: build debug"**, which builds an **unoptimized** copy
  in `build-debug/` (so variables aren't `<optimized out>` and stepping follows the
  source) and turns `eal.conf` into `build-debug/args.gdb`.
- gdb is started through **`~/.local/bin/dpdk-gdb`** (gdb wrapped in `dpdk-run`), so the
  program gets the same network permissions as `./run`. No sudo.
- Config lives in `.vscode/launch.json` and `.vscode/tasks.json`.

Tips:
- Breakpoints in the packet send/receive loop pause the whole program, so the card
  stops sending. Fine for checking packet contents, useless for measuring speed.
- If F5 says it can't find `build-debug/args.gdb` or the program, run the task by hand:
  Ctrl+Shift+P → "Tasks: Run Task" → "DPDK: build debug", and read its error.
- `build-debug/` is for debugging only. Measure performance with `./run` (optimized `build/`).
- Command-line equivalent: `dpdk-gdb -x build-debug/args.gdb build-debug/itch-replay`.

---

## Running programs: `./run`, `eal.conf`, `dpdk-run`

```
./run                   → builds, then:
dpdk-run ./build/itch-replay <args from eal.conf> <your args>
```

- **`eal.conf`** holds the DPDK startup settings, one per line, `#` for comments:
  - `-l 0-1`: which CPU cores to use (core 0 = main, core 1 = worker)
  - `--socket-mem=256`: MB of hugepage memory grabbed at startup
  - `--socket-limit=1024`: max MB it may grow to
  - `--in-memory`: **keep this.** It's what lets it run without sudo and leave no files behind.
  - `-a 85:00.0` / `-a 85:00.1`: the two ConnectX ports. Remove a line to use only one.
  - Optional, at the bottom: a `--` line followed by **your program's own arguments**.
    Both `./run` and F5 use them.
- **`dpdk-run`** (in `~/.local/bin`) starts a program with just enough network
  permissions for DPDK, so **you never need `sudo` to run your programs.** It works for any
  DPDK program, e.g. `dpdk-run dpdk-testpmd -l 0-1 --in-memory -a 85:00.0 -- -i`.

### Useful DPDK tools (all need `dpdk-run` in front)

| Command | Use |
|---|---|
| `dpdk-run dpdk-testpmd -l 0-1 --in-memory -a 85:00.1 -- -i` | Interactive tool; `start` then `show port stats all` to see packets arriving. `quit` to exit. |
| `dpdk-run dpdk-testpmd -l 0-1 --in-memory -a 85:00.1 -- --forward-mode=rxonly --stats-period 1` | Print RX stats every second (Ctrl+C to stop) |

---

## Making a new project

**Easiest:** `~/dpdk-projects/Installation/new-project.sh my-project`. It does all the
steps below, fills in this machine's card addresses, builds, and makes the first git
commit. The manual steps are kept here for reference.

```
cd ~/dpdk-projects
mkdir -p my-project/src my-project/.vscode && cd my-project
cp ../itch-replay/{meson.build,eal.conf,run,.gitignore} .
cp ../itch-replay/.vscode/{tasks.json,launch.json} .vscode/
sed -i 's/itch-replay/my-project/g' meson.build run .vscode/launch.json
```

Then:

1. The `sed` line renames the program in the three files that contain its name:
   `meson.build` (project + executable), `run` (`./build/...`) and
   `.vscode/launch.json` (`build-debug/...`). Check with `grep -rn itch-replay . .vscode`
   (should print nothing).
2. In `eal.conf`, adjust cores/memory/ports, and remove any program arguments after
   a `--` line that don't apply to the new program.
3. Write `src/main.c` (copy `../itch-replay/src/main.c` as a starting point).
4. Set up the build and the clangd link:
   ```
   meson setup build
   ln -s build/compile_commands.json .
   ninja -C build
   ```
5. `code .` to open it. Ctrl+Shift+B builds and runs; F5 debugs (it creates
   `build-debug/` the first time by itself).
6. Git (optional): `git init && git add -A && git commit -m "Initial commit"`. To put
   it on GitHub: create an **empty** repo on github.com, then
   `git remote add origin git@github.com:williamlin108/<repo>.git && git push -u origin main`.

**Adding source files:** list each new `.c`/`.cpp` file in the `executable(...)`
call in `meson.build`, e.g. `executable('my-project', 'src/main.c', 'src/itch.c', ...)`.
Meson notices the change automatically on the next build.

---

## Things that behave differently from a default Linux install

These were changed during setup. If something odd happens, check here first.

### 4 GB of RAM is reserved for hugepages
- **What:** `/etc/sysctl.d/80-hugepages.conf` reserves 2048 × 2 MB pages at every boot.
- **What you'll notice:** `free -h` and System Monitor show about 4 GB less available
  memory, even when no DPDK program is running.
- **Change it:** edit the number (512 = 1 GB, 0 = none) and apply without reboot:
  `echo 'vm.nr_hugepages = 512' | sudo tee /etc/sysctl.d/80-hugepages.conf && sudo sysctl -p /etc/sysctl.d/80-hugepages.conf`.
  Keep it at least as big as `--socket-limit` in `eal.conf`.
- **Undo completely:** `sudo rm /etc/sysctl.d/80-hugepages.conf && sudo sysctl vm.nr_hugepages=0`.

### `dpdk-run` grants network permissions without sudo
- **What:** `~/.local/bin/dpdk-caps` is a copy of the system `capsh` tool with the
  `cap_net_raw`, `cap_net_admin` and `cap_ipc_lock` capabilities attached.
- **Security trade-off:** anything you start through `dpdk-run` can capture and send raw
  packets and change network settings. Don't run untrusted programs through it.
- **If it stops working** (`dpdk-caps missing or has no caps`): the file was replaced or
  copied, which strips capabilities. Recreate it:
  ```
  sudo install -m 0750 -o wl -g wl /usr/sbin/capsh ~/.local/bin/dpdk-caps
  sudo setcap cap_net_raw,cap_net_admin,cap_ipc_lock+p ~/.local/bin/dpdk-caps
  ```
- **`dpdk-gdb`** (also in `~/.local/bin`) is gdb started through `dpdk-run`; F5 uses it.
- **Undo:** `rm ~/.local/bin/dpdk-caps ~/.local/bin/dpdk-run ~/.local/bin/dpdk-gdb`.

### Running with `sudo` instead leaves files behind
- `sudo ./build/itch-replay ...` **without** `--in-memory` creates root-owned files in
  `/dev/hugepages/` (e.g. `rtemap_0`) that keep memory reserved until reboot or
  `sudo rm /dev/hugepages/rtemap_*`. Use `./run` / `dpdk-run` instead.

### The ConnectX ports are shared between Linux and DPDK
- The ports were **not** bound to `vfio-pci`, which many DPDK guides tell you to do;
  mlx5 doesn't need it, so **don't run `dpdk-devbind.py`** on them. They stay
  visible as normal network interfaces (`enp133s0f0np0`, `enp133s0f1np1`).
- **While a DPDK program is running on a port, it takes that port's traffic**, so
  tools like `ping` or `tcpdump` on that interface won't see packets.
- **Once a cable is connected,** NetworkManager will try to get an IP address (DHCP)
  on those ports and may show a "Wired connection" that never finishes connecting. It's
  harmless. To stop it:
  `sudo nmcli device set enp133s0f0np0 managed no && sudo nmcli device set enp133s0f1np1 managed no`
  (lasts until reboot).

### Messages you can ignore
| Message | Meaning |
|---|---|
| `EAL: No free 1048576 kB hugepages reported on node 0` | No 1 GB pages configured. Only 2 MB pages are used. |
| `mlx5_net: No available register for sampler.` | ConnectX-4 Lx lacks an optional feature (packet sampling). |
| `link down` | No cable connected / other end not up. |
| `ninja: no work to do.` | Nothing changed since the last build. |

### Sudo rule for Claude
- `/etc/sudoers.d/claude-apt` lets `sudo apt-get update` and `sudo apt-get install …`
  run **without a password** (so Claude can install packages). Everything else still
  asks for your password. Remove with `sudo rm /etc/sudoers.d/claude-apt`.

---

## Troubleshooting

First run `~/dpdk-projects/Installation/verify.sh`: it checks the whole setup and
prints a `FAIL` line for anything wrong. `Installation/PITFALLS.md` explains each known problem.

| Symptom | Fix |
|---|---|
| `dpdk-caps missing or has no caps` | Recreate dpdk-caps (see above). |
| `Cannot allocate memory` / `No available hugepages` | `grep HugePages /proc/meminfo`. If total is 0, re-apply the sysctl. If free is low, another DPDK program is running, or there are leftover `/dev/hugepages/rtemap_*` files from a sudo run. |
| `DevX create TIS failed errno=121` | Program was run without permissions. Use `./run` or `dpdk-run`. |
| `Requested device 0000:85:00.x cannot be used` | Same as above, or the card is in use by another DPDK program. |
| `Dependency "libdpdk" not found` | `sudo apt-get install libdpdk-dev` |
| Autocomplete/red squiggles wrong in VS Code | `ninja -C build`, then Ctrl+Shift+P → "clangd: Restart language server". |
| Build errors after moving the project folder | `rm -rf build build-debug && meson setup build` (F5 recreates build-debug) |
| F5: `DevX create TIS failed` / ports can't be used | launch.json isn't using `dpdk-gdb` (check `miDebuggerPath`), or dpdk-caps lost its caps. |
| F5 starts but my program gets no arguments | Check `build-debug/args.gdb` exists and has `set args ...`; rerun task "DPDK: build debug". Don't put `"args"` in launch.json, because it overrides args.gdb. |
| F5: `<optimized out>` variables | You're debugging the `build/` binary. launch.json `program` should point at `build-debug/`. |
