#!/usr/bin/env python3
"""Add the DPDK workflow's VS Code user settings that are missing. Never changes a
key the user already has. settings.json is JSONC (comments allowed), so new keys are
inserted as text before the final '}' instead of re-serializing the file.

usage: python3 -I tools/merge-vscode-settings.py [--dry-run] ~/.config/Code/User/settings.json
"""
import json, os, re, shutil, sys

dry = "--dry-run" in sys.argv
path = os.path.expanduser([a for a in sys.argv[1:] if a != "--dry-run"][0])

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

text = open(path).read() if os.path.exists(path) else ""
if not text.strip():
    text = "{\n}\n"

# Strip // and /* */ comments (outside strings) only to locate keys and the last token
def strip_comments(s):
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
        elif s.startswith("//", i):
            j = s.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i)); i = j; continue
        elif s.startswith("/*", i):
            j = s.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append(re.sub(r"[^\n]", " ", s[i:j])); i = j; continue
        else:
            out.append(c)
        i += 1
    return "".join(out)

bare = strip_comments(text)
missing = {k: v for k, v in WANTED.items() if f'"{k}"' not in bare}
if not missing:
    print(f"   VS Code settings already present in {path}")
    sys.exit(0)

end = bare.rstrip().rfind("}")
if end < 0:
    sys.exit(f"   ERROR: {path} does not look like a JSON object; add these by hand:\n{json.dumps(missing, indent=4)}")
prev = bare[:end].rstrip()
needs_comma = not (prev.endswith("{") or prev.endswith(","))

block = "\n    // Added by dpdk Installation/install.sh\n" + ",\n".join(
    "    " + json.dumps(k) + ": " + json.dumps(v, indent=4).replace("\n", "\n    ") for k, v in missing.items()
) + "\n"
# Insert right after the last real token (keeps any trailing comments in place)
cut = len(prev)
new = text[:cut] + ("," if needs_comma else "") + block + text[cut:].lstrip("\n").lstrip(" ")

# Sanity check before writing: result must parse once comments/trailing commas are removed
try:
    json.loads(re.sub(r",(\s*[}\]])", r"\1", strip_comments(new)))
except ValueError as e:
    sys.exit(f"   ERROR: merged settings would not parse ({e}); left {path} unchanged")

if dry:
    print(f"   would add {', '.join(missing)} to {path}")
    sys.exit(0)
if os.path.exists(path):
    shutil.copy2(path, path + ".bak-dpdk")
os.makedirs(os.path.dirname(path), exist_ok=True)
open(path, "w").write(new)
print(f"   added {', '.join(missing)} to {path} (backup: settings.json.bak-dpdk)")
