# NASDAQ-on-Kintex

DPDK development on NVIDIA/Mellanox ConnectX NICs (mlx5), starting with replaying
historical NASDAQ TotalView-ITCH data.

```
Installation/     set up a machine: install.sh, verify.sh, new-project.sh, template/
projects/
  itch-replay/    replay ITCH files out of a ConnectX-4 Lx port (DPDK)
```

## New machine

```
git clone git@github.com:williamlin108/NASDAQ-on-Kintex.git ~/dpdk-projects
cd ~/dpdk-projects/Installation
./install.sh          # asks for sudo; see Installation/README.md
./verify.sh --full
```

## Working on a project

Open the **project folder** (not this repo root) in VS Code, so its build/run/debug
config is picked up:

```
code ~/dpdk-projects/projects/itch-replay
```

Ctrl+Shift+B builds and runs, F5 debugs. See `projects/itch-replay/docs/user-guide.md`.

New project: `Installation/new-project.sh <name>` creates `projects/<name>/`.
