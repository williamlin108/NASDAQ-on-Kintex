# Repo guide for agents

## Documentation map (read this first)

Read only what your task needs, using the "Read when" column. Before writing anything,
find the one file whose "Write here" column matches, and follow its standard. Don't
create new .md files or duplicate content between files: link to the owner instead.

| File | Purpose / audience | Read when | Write here when / standard |
|---|---|---|---|
| `README.md` | Repo front page for humans: layout, doc index, 3-line quick starts | Rarely; this map covers it | The repo layout or a top-level doc changes. Keep it short: links, not content |
| `AGENTS.md` (this file) + `CLAUDE.md` (imports it) | Agent orientation | Always (auto-loaded) | A doc is added, removed, or changes purpose. Keep this map exact |
| `docs/user-guide.md` | **How to use** everything, for the user (all projects) | Answering "how do I…", or before changing any user-visible command, shortcut or behaviour | Anything the user does or sees changes. Second person, task-ordered, copy-pasteable commands, no internals. **Then regenerate the HTML** (see rules) |
| `docs/user-guide.html` | Generated from user-guide.md for the browser | **Never read or edit** (large, derived) | Never by hand: `python3 -I docs/build-user-guide.py` |
| `docs/how-it-works.md` | **Why** it works: drivers, capabilities/`dpdk-run`, hugepages, `eal.conf` parsing, VS Code/F5 internals, tests | Debugging the workflow, or before redesigning it | A mechanism changes. Explanatory, timeless (no dates, no "we did X"), no step-by-step how-to |
| `docs/this-machine.md` | Facts about **this** computer: hardware, PCI/MAC/device names, package versions, files created outside the repo + undo, verification log | You need a concrete value (PCI address, version, path), or before changing system files | System state changes (package, system file, device name) or something is verified. Dated facts; add a verification-log row with the result, including "not tested" |
| `Installation/README.md` | Setting up another computer, for humans | Setting up or repairing a machine | Installer usage or options change. Short, human |
| `Installation/AGENTS.md` + `Installation/CLAUDE.md` (imports it) | Agent procedure and rules for install/verify/new-project, target state | **Before running or changing anything in `Installation/`** (auto-loaded there) | The procedure, target state, or script rules change. Imperative rules |
| `Installation/PITFALLS.md` | Every known problem: symptom → cause → fix, numbered | Before changing scripts/system config, and whenever something fails | You hit a new problem or a fix changes. Keep the format and section; renumber when inserting and fix "pitfall N" references (`grep -rn 'pitfall [0-9]'`) |
| `projects/<name>/AGENTS.md` + `CLAUDE.md` | Pointers for that project | Working in that project (auto-loaded) | Rarely; keep as pointers |
| `projects/<name>/docs/README.md` | That project only: purpose, dated status, next steps, project-specific notes | Working on that project's code | Project status or plans change. No general workflow content (that's user-guide/how-it-works) |

## Rules for docs

- **One owner per fact.** General how-to → user guide; internals → how-it-works;
  this computer's specifics → this-machine; problems → PITFALLS; project state →
  project README. Elsewhere, link.
- **After editing `docs/user-guide.md`:** `python3 -I docs/build-user-guide.py`, check
  that it prints `wrote docs/user-guide.html`, and commit both files together.
- **Only document what was verified.** Say plainly what is untested. Use absolute
  dates (2026-10-28), never "today" or "recently".
- **Paths:** the repo lives at `~/dpdk-projects`; projects at `projects/<name>`. Machine
  values (PCI addresses, device names) belong only in this-machine.md and `eal.conf`.
  Never depend on verbs device names; they changed after a reboot (pitfall 6).
- **After moving or renaming a doc,** check that all relative links still resolve and
  update this map.

## Working rules

- Setup, repair, or changes to `Installation/`: follow `Installation/AGENTS.md`.
- Run DPDK programs with `./run` or `dpdk-run`, never `sudo`. Open a **project folder** in
  VS Code, not the repo root.
- Before finishing script changes: `shellcheck -S warning <script>` and
  `Installation/verify.sh --full` (must end "All checks passed.").
