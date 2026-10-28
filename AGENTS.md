# Repo guide for agents

- Machine setup / repair: `Installation/AGENTS.md` (read `Installation/PITFALLS.md` too).
- How the workflow works internally: `docs/how-it-works.md`. Machine facts and installed files: `docs/this-machine.md`.
- User-facing guide: `docs/user-guide.md`. `docs/user-guide.html` is generated from it:
  after editing the .md, run `python3 -I docs/build-user-guide.py` and commit both.
- Project work: each `projects/<name>/` has its own `AGENTS.md`/`CLAUDE.md` and `docs/README.md`.
- Keep docs in their place: general how-to in `docs/user-guide.md`, internals in
  `docs/how-it-works.md`, this computer's specifics in `docs/this-machine.md`,
  problems in `Installation/PITFALLS.md`, project status in `projects/<name>/docs/`.
