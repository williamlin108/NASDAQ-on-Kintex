# itch-replay docs

Replay historical NASDAQ TotalView-ITCH 5.0 files out of a Mellanox ConnectX-4 Lx
using DPDK's mlx5 driver. This folder records how the machine and project were set
up, so a person or agent can pick up without redoing discovery.

| File | Contents |
|---|---|
| [user-guide.md](user-guide.md) | **Start here (humans):** commands, VS Code shortcuts, new projects, non-default system behavior, troubleshooting |
| [setup.md](setup.md) | Hardware, installed packages and versions, system-level configuration |
| [workflow.md](workflow.md) | Building, running without sudo, VS Code / clangd integration |
| [files.md](files.md) | Every file and script created outside a normal checkout, and how to undo each |
| [status.md](status.md) | What works, what's untested, open items and next steps |

Machine setup is reproducible with the installation kit in `~/dpdk-projects/Installation`
(`install.sh`, `verify.sh`, `new-project.sh`, plus AGENTS.md and PITFALLS.md for agents).

Last updated: 2026-10-27.
