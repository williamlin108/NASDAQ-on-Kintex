# Files and scripts created during setup

Nothing here is temporary. All of it is still in use.

| Path | What | Undo |
|---|---|---|
| `~/dpdk-projects/` | Parent folder for all DPDK projects | — |
| `~/dpdk-projects/itch-replay/` | This project (meson.build, src/main.c, eal.conf, run, .gitignore, .vscode/tasks.json, CLAUDE.md, AGENTS.md, docs/) | delete folder |
| `~/.local/bin/dpdk-run` | Launcher script granting ambient caps (see workflow.md) | `rm` |
| `~/.local/bin/dpdk-caps` | capsh copy with file caps `cap_net_admin,cap_net_raw,cap_ipc_lock=p` | `rm` (removes the caps too) |
| `~/.config/Code/User/settings.json` | Added `mesonbuild.buildFolder: "build"` (+ user enabled `mesonbuild.downloadLanguageServer`) | delete those lines |
| `/etc/sysctl.d/80-hugepages.conf` | Persistent hugepage reservation, `vm.nr_hugepages = 2048` | `sudo rm`, reboot |
| apt packages | See setup.md | `sudo apt-get remove ...` |

No other scratch scripts or temp files were left behind.
