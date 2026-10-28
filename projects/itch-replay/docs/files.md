# Files and scripts created during setup

Nothing here is temporary. All of it is still in use.

| Path | What | Undo |
|---|---|---|
| `~/dpdk-projects/` | Git repo (github.com/williamlin108/NASDAQ-on-Kintex): `Installation/` + `projects/` | — |
| `~/dpdk-projects/Installation/` | Installation kit (install.sh, verify.sh, new-project.sh, template) | — |
| `~/dpdk-projects/projects/itch-replay/` | This project (meson.build, src/main.c, eal.conf, run, .gitignore, .vscode/tasks.json, .vscode/launch.json, CLAUDE.md, AGENTS.md, docs/) | delete folder |
| `~/.local/bin/dpdk-run` | Launcher script granting ambient caps (see workflow.md); uses absolute paths so it works without `~/.local/bin` on PATH | `rm` |
| `~/.local/bin/dpdk-gdb` | gdb wrapped in dpdk-run; VS Code `miDebuggerPath` for F5 | `rm` |
| `~/.local/bin/dpdk-caps` | capsh copy with file caps `cap_net_admin,cap_net_raw,cap_ipc_lock=p` | `rm` (removes the caps too) |
| `~/.config/Code/User/settings.json` | Added `mesonbuild.buildFolder: "build"` (+ user enabled `mesonbuild.downloadLanguageServer`) | delete those lines |
| `/etc/sysctl.d/80-hugepages.conf` | Persistent hugepage reservation, `vm.nr_hugepages = 2048` | `sudo rm`, reboot |
| apt packages | See setup.md | `sudo apt-get remove ...` |

No other scratch scripts or temp files were left behind.
