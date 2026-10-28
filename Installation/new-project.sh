#!/bin/bash
# Create a new DPDK project from template/, with this machine's mlx5 ports filled in.
#
#   ./new-project.sh my-project                # -> <repo>/projects/my-project
#   ./new-project.sh my-project --dir ~/work   # -> ~/work/my-project
#   ./new-project.sh my-project --no-git       # never git init
#
# Inside an existing git repo (the default projects/ folder is), the project is just
# added to that repo; outside one, a new repo is created with an initial commit.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
NAME=""
DIR="$(dirname "$HERE")/projects"
GIT=1
DEST=""
PORTS=""      # "-a <pci>" lines for eal.conf
NIC_NODE=0    # NUMA node the NICs are on
NODES=1       # number of NUMA nodes
IN_REPO=0     # 1 if DEST is inside an existing git repo

# Print an error and exit with the given status.
die() { echo "$2" >&2; exit "$1"; }

# Parse arguments and validate the project name and destination.
parse_args() {
	while [ $# -gt 0 ]; do
		case "$1" in
		--dir) DIR="$2"; shift ;;
		--no-git) GIT=0 ;;
		-h|--help) sed -n '2,10p' "$0"; exit 0 ;;
		-*) die 2 "unknown option: $1" ;;
		*) NAME="$1" ;;
		esac
		shift
	done
	[ -n "$NAME" ] || die 2 "usage: $0 <name> [--dir DIR] [--no-git]"
	# The name becomes the meson project/executable name and a sed replacement
	[[ "$NAME" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]] || die 2 "name must match [A-Za-z][A-Za-z0-9_-]*"
	DEST="$DIR/$NAME"
	[ ! -e "$DEST" ] || die 1 "$DEST already exists"
	pkg-config --exists libdpdk || die 1 "libdpdk not found; run install.sh first"
}

# Find this machine's mlx5 ports (PCI order) and the NUMA node they're attached to.
detect_ports() {
	local dev bdf node
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
	NODES="$(ls -d /sys/devices/system/node/node[0-9]* 2>/dev/null | wc -l)"
	[ "$NODES" -ge 1 ] || NODES=1
}

# Print a comma-separated per-NUMA-node list: the given value on the NIC's node, 0 elsewhere.
per_node_list() {
	local value="$1" out="" i
	for ((i = 0; i < NODES; i++)); do
		if [ "$i" = "$NIC_NODE" ]; then out+="${out:+,}$value"; else out+="${out:+,}0"; fi
	done
	echo "$out"
}

# Copy the template into DEST and fill in every placeholder.
create_from_template() {
	mkdir -p "$DEST"
	cp -r "$HERE/template/." "$DEST/"
	mv "$DEST/gitignore" "$DEST/.gitignore"
	cd "$DEST"
	sed -i "s/__NAME__/$NAME/g" meson.build run .vscode/launch.json
	python3 -I - "$PORTS" "$(per_node_list 256)" "$(per_node_list 1024)" <<'EOF'
import sys
ports, mem, limit = sys.argv[1:]
s = open("eal.conf").read()
s = s.replace("__PORTS__\n", ports).replace("__SOCKET_MEM__", mem).replace("__SOCKET_LIMIT__", limit)
open("eal.conf", "w").write(s)
EOF
	if grep -rqn '__[A-Z_]*__' meson.build run eal.conf .vscode; then
		grep -rn '__[A-Z_]*__' meson.build run eal.conf .vscode >&2
		die 1 "BUG: unreplaced template placeholder (above)"
	fi
}

# Configure and build the project, and link compile_commands.json for clangd.
build_project() {
	meson setup build >/dev/null
	ln -s build/compile_commands.json .
	ninja -C build >/dev/null
}

# Start a git repo with an initial commit, unless DEST is already inside one.
init_git() {
	if git -C "$DEST" rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
	   [ "$(git -C "$DEST" rev-parse --show-toplevel)" != "$DEST" ]; then
		IN_REPO=1
	fi
	[ "$GIT" = 1 ] && [ "$IN_REPO" = 0 ] || return 0
	git init -q
	git add -A
	git commit -q -m "Initial commit from DPDK project template"
}

# Print where the project is and how to open, run and commit it.
print_summary() {
	echo "Created $DEST"
	echo "  ports in eal.conf: $(grep -c '^-a ' eal.conf)   NUMA nodes: $NODES (NIC on node $NIC_NODE)"
	echo "  open:  code $DEST    (Ctrl+Shift+B = build & run, F5 = debug)"
	echo "  run:   cd $DEST && ./run"
	if [ "$IN_REPO" = 1 ]; then
		echo "  git:   part of $(git rev-parse --show-toplevel); commit when ready (git add $NAME)"
	fi
}

main() {
	parse_args "$@"
	detect_ports
	create_from_template
	build_project
	init_git
	print_summary
}

main "$@"
