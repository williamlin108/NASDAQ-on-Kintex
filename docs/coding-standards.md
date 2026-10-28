# Coding standards

Rules for all code in this repo: C/C++ in `projects/`, shell and Python in
`Installation/` and `docs/`. They apply to code written by people and agents alike.
**Agents: follow every rule here for any code you write or change.**

## Functions

- **Every function gets a one-sentence summary** directly above it, saying *what* it
  does, not how:
  - C: `/* ... */`
  - shell: `# ...`
  - Python: a docstring

  A second sentence is fine only for something critical (a pitfall, an ownership
  rule). If one sentence can't describe it, the function does too much: split it.
- **Small, single-purpose functions.** Aim for under ~40 lines and at most 3 levels of
  nesting; past that, extract a named helper.
- **`main` stays high level:** a readable sequence of calls to named steps (parse
  config, init, run, clean up) with no detailed logic inline.
- **Scripts have the same shape:** functions first, then `main "$@"` (shell) or
  `main()` (Python) at the bottom. Only thin wrappers of a few straight-line commands
  (`Installation/bin/dpdk-run`, a project's `run`) may skip functions.

## Comments

- **Every file starts with a short header:** what it is for, plus usage for scripts.
- **Comments inside functions explain *why*:** a constraint, a non-obvious choice, or a
  known problem ("see pitfall N" for `Installation/PITFALLS.md`). Never restate what
  the code already says.

## Errors

- **Check every DPDK return value** (many are `warn_unused_result`).
- **Fail with a message naming what failed** (`rte_exit` in setup code, `die` in
  scripts). Never skip a failure silently.

## Per language

| Language | Rules |
|---|---|
| C / C++ | Tabs, DPDK/kernel style as in the template; meson `warning_level=2`; **zero warnings** |
| Shell | bash, `set -euo pipefail` (or `-uo` when counting failures), shellcheck-clean at `-S warning`, absolute paths for tools whose location varies (`/usr/sbin/getcap`, `$HOME/.local/bin/dpdk-run`) |
| Python | Run as `python3 -I`; standard library only (plus python3-markdown in `docs/`) |

## Reference examples

These files show the expected shape; copy their structure:

- C: `Installation/template/src/main.c`
- Shell: `Installation/install.sh`
- Python: `Installation/tools/test-f5.py`

## Before finishing a change

- C: the project builds with no warnings (`ninja -C build`).
- Shell: `shellcheck -S warning <script>`.
- Anything in `Installation/` or a project's run/debug setup: `Installation/verify.sh --full`
  ends with "All checks passed."

## Changing these standards

Edit this file. Existing code doesn't have to be rewritten at once, but any code you
touch should be brought up to the current standards.
