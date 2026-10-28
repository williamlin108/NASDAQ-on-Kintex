# NASDAQ-on-Kintex

DPDK development on NVIDIA/Mellanox ConnectX NICs (mlx5), starting with replaying
historical NASDAQ TotalView-ITCH data. Cloned to `~/dpdk-projects`.

```
docs/             how to use everything (start with the user guide)
Installation/     set up a machine: install.sh, verify.sh, new-project.sh, template/
projects/
  itch-replay/    replay ITCH files out of a ConnectX-4 Lx port (DPDK)
```

## Documentation

| Read | For |
|---|---|
| **[docs/user-guide.html](docs/user-guide.html)** (open in a browser) or [user-guide.md](docs/user-guide.md) | Opening, building, running, debugging, new projects, troubleshooting |
| [docs/coding-standards.md](docs/coding-standards.md) | Coding rules for all code here (people and agents) |
| [docs/how-it-works.md](docs/how-it-works.md) | Why it's set up this way: drivers, running without sudo, VS Code/F5 internals |
| [docs/this-machine.md](docs/this-machine.md) | This computer's hardware, versions, every installed file and how to undo it |
| [Installation/README.md](Installation/README.md) | Setting up another computer |
| [Installation/PITFALLS.md](Installation/PITFALLS.md) | Every known problem, its cause and fix |
| `projects/<name>/docs/` | Project status and next steps |

Open the guide: `xdg-open ~/dpdk-projects/docs/user-guide.html`

## Working on a project

Open the **project folder** (not this repo root) in VS Code, so its build/run/debug
config is picked up:

```
code ~/dpdk-projects/projects/itch-replay
```

Ctrl+Shift+B builds and runs, F5 debugs. New project: `Installation/new-project.sh <name>`.

## New machine

```
git clone git@github.com:williamlin108/NASDAQ-on-Kintex.git ~/dpdk-projects
cd ~/dpdk-projects/Installation
./install.sh          # asks for sudo; see Installation/README.md
./verify.sh --full
```
