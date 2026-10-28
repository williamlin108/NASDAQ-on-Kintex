# User guide

A practical cheat sheet for working on DPDK projects on this machine. For the
detailed "why" behind the setup, see [setup.md](setup.md) and [workflow.md](workflow.md).

---

## Quick reference

| I want to… | Do this |
|---|---|
| Open the project | `code ~/dpdk-projects/itch-replay` |
| Build **and** run | **Ctrl+Shift+B** in VS Code, or `./run` in a terminal |
| Only build | `ninja -C build` |
| Run with arguments for my program | `./run -- --file itch.bin` (everything after `--` goes to your program) |
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
- **F5 (debugging) is not set up yet.** Debugging needs the same network
  permissions as running; ask Claude to add a `launch.json` that runs gdb through
  `dpdk-run`.

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

```
cd ~/dpdk-projects
mkdir my-project && cd my-project
mkdir src
cp ../itch-replay/{meson.build,eal.conf,run,.gitignore} .
cp -r ../itch-replay/.vscode .
rm -f .vscode/settings.json
```

Then:

1. In `meson.build`, change `itch-replay` (project name and executable name) to `my-project`.
2. In `run`, change `./build/itch-replay` to `./build/my-project`.
3. Write `src/main.c` (copy `../itch-replay/src/main.c` as a starting point).
4. Set up the build and the clangd link:
   ```
   meson setup build
   ln -s build/compile_commands.json .
   ninja -C build
   ```
5. `code .` to open it, and Ctrl+Shift+B to build and run.
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
- **Undo:** `rm ~/.local/bin/dpdk-caps ~/.local/bin/dpdk-run`.

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

| Symptom | Fix |
|---|---|
| `dpdk-caps missing or has no caps` | Recreate dpdk-caps (see above). |
| `Cannot allocate memory` / `No available hugepages` | `grep HugePages /proc/meminfo`. If total is 0, re-apply the sysctl. If free is low, another DPDK program is running, or there are leftover `/dev/hugepages/rtemap_*` files from a sudo run. |
| `DevX create TIS failed errno=121` | Program was run without permissions. Use `./run` or `dpdk-run`. |
| `Requested device 0000:85:00.x cannot be used` | Same as above, or the card is in use by another DPDK program. |
| `Dependency "libdpdk" not found` | `sudo apt-get install libdpdk-dev` |
| Autocomplete/red squiggles wrong in VS Code | `ninja -C build`, then Ctrl+Shift+P → "clangd: Restart language server". |
| Build errors after moving the project folder | `rm -rf build && meson setup build` |
