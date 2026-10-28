# DPDK + Mellanox (mlx5) installation

Sets up a computer for DPDK development on NVIDIA/Mellanox ConnectX network cards,
the same way as the original machine (Ubuntu 26.04, DPDK 25.11, ConnectX-4 Lx), so
projects behave identically everywhere.

## On a new computer

```
git clone git@github.com:williamlin108/NASDAQ-on-Kintex.git ~/dpdk-projects
cd ~/dpdk-projects/Installation
./install.sh --dry-run     # see what it will do (changes nothing)
./install.sh               # do it; asks for your sudo password
./verify.sh --full         # should end with "All checks passed."
```

Then make a project:

```
./new-project.sh my-project            # -> ~/dpdk-projects/projects/my-project
code ~/dpdk-projects/projects/my-project
```

In VS Code: **Ctrl+Shift+B** builds and runs, **F5** debugs. No sudo needed for either.
Open the **project folder** (`projects/my-project`), not the repo root `~/dpdk-projects`:
the shortcuts live in each project's `.vscode/`, which VS Code only reads from the
folder you opened.

## What `install.sh` does

| Step | Details |
|---|---|
| Checks | Debian/Ubuntu only; refuses if NVIDIA's MLNX_OFED/DOCA is installed (not needed, and conflicts) |
| Packages | rdma-core, meson/ninja, gdb, clangd, build tools, mstflint |
| DPDK 25.11 | From the distro if it ships 25.11 (Ubuntu 26.04 does), otherwise built from source (about 1 minute on 20 cores, longer on smaller machines) |
| Drivers | Makes sure the inbox mlx5 kernel drivers are loaded and the cards **not** bound to vfio |
| Hugepages | Reserves 4 GB permanently (`--hugepages-mb 1024` for 1 GB) |
| No-sudo running | Installs `dpdk-run`, `dpdk-gdb` and `dpdk-caps` into `~/.local/bin` |
| VS Code | Installs the clangd, C++ (debugger) and Meson extensions; adds the needed settings without changing yours |

It's safe to run again at any time. It only changes what's missing.

## Options

```
./install.sh --dpdk source       # always build DPDK 25.11 from source
./install.sh --hugepages-mb 1024 # smaller hugepage reserve
./install.sh --no-vscode         # skip VS Code setup
./verify.sh                      # quick check (no project build)
```

## Something broke?

Run `./verify.sh`. Each `FAIL` line says what's wrong. [PITFALLS.md](PITFALLS.md)
lists every problem found while building this setup, with fixes.

## Using an AI agent

Tell it: *"Read ~/dpdk-projects/Installation/AGENTS.md and set up this machine."*
[AGENTS.md](AGENTS.md) has the full context, the procedure, and the rules that avoid
known pitfalls. The installer needs your sudo password, so the agent will ask you to
run `./install.sh` yourself (in Claude Code: `! ./install.sh`).

## Files

- `install.sh`, `verify.sh`, `new-project.sh`: the three commands you use
- `template/`: what every new project starts from
- `bin/`: the `dpdk-run` / `dpdk-gdb` launchers
- `tools/`: DPDK source build, VS Code settings merge, headless F5 test
