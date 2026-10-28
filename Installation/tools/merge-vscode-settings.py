#!/usr/bin/env python3
"""Add the DPDK workflow's VS Code user settings that are missing. Never changes a
key the user already has. settings.json is JSONC (comments allowed), so new keys are
inserted as text before the final '}' instead of re-serializing the file.

usage: python3 -I tools/merge-vscode-settings.py [--dry-run] ~/.config/Code/User/settings.json
"""
import json, os, re, shutil, sys

WANTED = {
    # clangd does IntelliSense; cpptools stays installed only for its gdb debugger
    "C_Cpp.intelliSenseEngine": "disabled",
    "clangd.arguments": [
        "--query-driver=/usr/bin/g++,/usr/bin/gcc",
        "--background-index",
        "--completion-style=detailed",
    ],
    # Meson extension shares the CLI build dir (default would be builddir/)
    "mesonbuild.buildFolder": "build",
}


def strip_comments(s):
    """Return s with // and /* */ comments outside strings blanked, keeping every offset."""
    out, i, n, in_str = [], 0, len(s), False
    while i < n:
        c = s[i]
        if in_str:
            out.append(c)
            if c == "\\":
                out.append(s[i + 1]); i += 1
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True; out.append(c)
        elif s.startswith("//", i) or s.startswith("/*", i):
            j = comment_end(s, i)
            out.append(re.sub(r"[^\n]", " ", s[i:j])); i = j; continue
        else:
            out.append(c)
        i += 1
    return "".join(out)


def comment_end(s, i):
    """Return the index just past the comment starting at s[i]."""
    if s.startswith("//", i):
        j = s.find("\n", i)
        return len(s) if j < 0 else j
    j = s.find("*/", i + 2)
    return len(s) if j < 0 else j + 2


def render_block(missing):
    """Format the missing settings as indented JSON lines with a marker comment."""
    lines = ("    " + json.dumps(k) + ": " + json.dumps(v, indent=4).replace("\n", "\n    ")
             for k, v in missing.items())
    return "\n    // Added by dpdk Installation/install.sh\n" + ",\n".join(lines) + "\n"


def insert_settings(text, bare, missing, path):
    """Return text with the missing settings inserted after the last real token."""
    end = bare.rstrip().rfind("}")
    if end < 0:
        sys.exit(f"   ERROR: {path} does not look like a JSON object; add these by hand:\n"
                 f"{json.dumps(missing, indent=4)}")
    prev = bare[:end].rstrip()
    comma = "" if prev.endswith(("{", ",")) else ","
    cut = len(prev)  # keeps any trailing comments after the insertion point
    return text[:cut] + comma + render_block(missing) + text[cut:].lstrip("\n").lstrip(" ")


def check_parses(new, path):
    """Exit without writing if the merged text isn't valid JSONC."""
    try:
        json.loads(re.sub(r",(\s*[}\]])", r"\1", strip_comments(new)))
    except ValueError as e:
        sys.exit(f"   ERROR: merged settings would not parse ({e}); left {path} unchanged")


def write_with_backup(path, new):
    """Write the new settings, keeping the previous file as settings.json.bak-dpdk."""
    if os.path.exists(path):
        shutil.copy2(path, path + ".bak-dpdk")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write(new)


def main():
    dry = "--dry-run" in sys.argv
    path = os.path.expanduser([a for a in sys.argv[1:] if a != "--dry-run"][0])
    text = open(path).read() if os.path.exists(path) else ""
    text = text if text.strip() else "{\n}\n"

    bare = strip_comments(text)
    missing = {k: v for k, v in WANTED.items() if f'"{k}"' not in bare}
    if not missing:
        print(f"   VS Code settings already present in {path}")
        return

    new = insert_settings(text, bare, missing, path)
    check_parses(new, path)
    if dry:
        print(f"   would add {', '.join(missing)} to {path}")
        return
    write_with_backup(path, new)
    print(f"   added {', '.join(missing)} to {path} (backup: settings.json.bak-dpdk)")


if __name__ == "__main__":
    main()
