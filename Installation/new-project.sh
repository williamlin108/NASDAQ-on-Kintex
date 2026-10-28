#!/bin/bash
# Create a new DPDK project from template/, with this machine's mlx5 ports filled in.
#
#   ./new-project.sh my-project                # -> ~/dpdk-projects/my-project
#   ./new-project.sh my-project --dir ~/work   # -> ~/work/my-project
#   ./new-project.sh my-project --no-git
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
NAME=""
DIR="$HOME/dpdk-projects"
GIT=1

while [ $# -gt 0 ]; do
	case "$1" in
	--dir) DIR="$2"; shift ;;
	--no-git) GIT=0 ;;
	-h|--help) sed -n '2,7p' "$0"; exit 0 ;;
	-*) echo "unknown option: $1" >&2; exit 2 ;;
	*) NAME="$1" ;;
	esac
	shift
done

[ -n "$NAME" ] || { echo "usage: $0 <name> [--dir DIR] [--no-git]" >&2; exit 2; }
# Name is used as a meson project/executable name and in sed replacements
[[ "$NAME" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]] || { echo "name must match [A-Za-z][A-Za-z0-9_-]*" >&2; exit 2; }
DEST="$DIR/$NAME"
[ ! -e "$DEST" ] || { echo "$DEST already exists" >&2; exit 1; }
pkg-config --exists libdpdk || { echo "libdpdk not found; run install.sh first" >&2; exit 1; }

# mlx5 ports, in PCI order
PORTS=""
NIC_NODE=0
for dev in /sys/bus/pci/drivers/mlx5_core/0000:*; do
	[ -e "$dev" ] || continue
	bdf="$(basename "$dev")"
	PORTS+="-a ${bdf#0000:}"$'\n'
	node="$(cat "$dev/numa_node" 2>/dev/null || echo -1)"
	[ "$node" -ge 0 ] 2>/dev/null && NIC_NODE="$node"
done
if [ -z "$PORTS" ]; then
	echo "warning: no mlx5 ports found; eal.conf gets no -a lines (DPDK will probe every device)" >&2
	PORTS="# (no mlx5 ports found on this machine; add -a <pci-address> lines)"$'\n'
fi

# One --socket-mem/--socket-limit value per NUMA node; memory only on the NIC's node
NODES="$(ls -d /sys/devices/system/node/node[0-9]* 2>/dev/null | wc -l)"
[ "$NODES" -ge 1 ] || NODES=1
MEM=""; LIMIT=""
for ((i = 0; i < NODES; i++)); do
	if [ "$i" = "$NIC_NODE" ]; then m=256; l=1024; else m=0; l=0; fi
	MEM+="${MEM:+,}$m"; LIMIT+="${LIMIT:+,}$l"
done

mkdir -p "$DEST"
cp -r "$HERE/template/." "$DEST/"
mv "$DEST/gitignore" "$DEST/.gitignore"
cd "$DEST"
sed -i "s/__NAME__/$NAME/g" meson.build run .vscode/launch.json
python3 -I - "$PORTS" "$MEM" "$LIMIT" <<'EOF'
import sys
ports, mem, limit = sys.argv[1:]
s = open("eal.conf").read()
s = s.replace("__PORTS__\n", ports).replace("__SOCKET_MEM__", mem).replace("__SOCKET_LIMIT__", limit)
open("eal.conf", "w").write(s)
EOF
if grep -rqn '__[A-Z_]*__' meson.build run eal.conf .vscode; then
	echo "BUG: unreplaced placeholder:" >&2; grep -rn '__[A-Z_]*__' meson.build run eal.conf .vscode >&2; exit 1
fi

meson setup build >/dev/null
ln -s build/compile_commands.json .
ninja -C build >/dev/null

if [ "$GIT" = 1 ]; then
	git init -q
	git add -A
	git commit -q -m "Initial commit from DPDK project template"
fi

echo "Created $DEST"
echo "  ports in eal.conf: $(grep -c '^-a ' eal.conf)   NUMA nodes: $NODES (NIC on node $NIC_NODE)"
echo "  open:  code $DEST    (Ctrl+Shift+B = build & run, F5 = debug)"
echo "  run:   cd $DEST && ./run"
