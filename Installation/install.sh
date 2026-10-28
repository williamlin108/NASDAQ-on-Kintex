#!/bin/bash
# Install DPDK + NVIDIA/Mellanox mlx5 (inbox drivers, no OFED) and the unprivileged
# dev workflow (dpdk-run/dpdk-gdb, hugepages, VS Code) exactly like the reference
# machine. Safe to re-run: every step checks before changing anything.
#
#   ./install.sh                     # everything, DPDK from distro if it is 25.11, else source
#   ./install.sh --dry-run           # print what would be done, change nothing
#   ./install.sh --dpdk source       # force DPDK 25.11 source build (distro|source|auto)
#   ./install.sh --hugepages-mb 1024 # hugepage pool size (default 4096 = 2048 x 2 MB)
#   ./install.sh --no-vscode         # skip VS Code extensions/settings
#
# Run as your normal user (not with sudo); it asks for your password when needed.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/.local/bin"
DPDK_VERSION=25.11
DPDK_MODE=auto
HUGEPAGES_MB=4096
VSCODE=1
DRY=0
MLX_PCI=""

# Print a step heading.
step() { printf '\n== %s\n' "$*"; }
# Print an indented progress line.
info() { printf '   %s\n' "$*"; }
# Print a warning to stderr and continue.
warn() { printf '   WARNING: %s\n' "$*" >&2; }
# Print an error to stderr and stop the install.
die()  { printf '   ERROR: %s\n' "$*" >&2; exit 1; }
# Run a command, or only print it in --dry-run mode.
run()  { if [ "$DRY" = 1 ]; then printf '   would run: %s\n' "$*"; else "$@"; fi; }

# Parse command-line options into the globals above.
parse_args() {
	while [ $# -gt 0 ]; do
		case "$1" in
		--dpdk) DPDK_MODE="$2"; shift ;;
		--hugepages-mb) HUGEPAGES_MB="$2"; shift ;;
		--no-vscode) VSCODE=0 ;;
		--dry-run) DRY=1 ;;
		-h|--help) sed -n '2,13p' "$0"; exit 0 ;;
		*) echo "unknown option: $1" >&2; exit 2 ;;
		esac
		shift
	done
	case "$DPDK_MODE" in auto|distro|source) ;; *) echo "--dpdk must be auto, distro or source" >&2; exit 2 ;; esac
}

# Stop early on an unsupported system and record the machine's mlx5 PCI addresses.
preflight() {
	step "Preflight"
	[ "$(id -u)" != 0 ] || die "run as your normal user, not root/sudo (installs into ~/.local/bin and your VS Code settings)"
	. /etc/os-release
	[[ " $ID $ID_LIKE " =~ \ (debian|ubuntu)\  ]] || die "only Debian/Ubuntu are supported (found $ID)"
	info "OS: $PRETTY_NAME, kernel $(uname -r), arch $(uname -m)"
	[ "$(uname -m)" = x86_64 ] || warn "only tested on x86_64"
	command -v sudo >/dev/null || die "sudo is required"

	# OFED/DOCA replace rdma-core with their own copies and break distro DPDK (pitfall 1)
	if command -v ofed_info >/dev/null || dpkg -l 2>/dev/null | grep -qE '^ii +(mlnx-ofed|doca-)'; then
		die "MLNX_OFED/DOCA detected. This setup uses the inbox kernel driver + distro rdma-core. Uninstall OFED/DOCA first (or adapt by hand)."
	fi

	MLX_PCI="$(lspci -D -d 15b3: 2>/dev/null | awk '/Ethernet/{print $1}' || true)"
	if [ -n "$MLX_PCI" ]; then
		info "Mellanox/NVIDIA Ethernet ports: $(echo $MLX_PCI)"
	else
		warn "no Mellanox/NVIDIA Ethernet device found; installing anyway (dev-only machine)"
	fi
}

# Resolve --dpdk auto to distro or source, depending on the distro's DPDK version.
choose_dpdk_source() {
	[ "$DPDK_MODE" = auto ] || return 0
	local cand
	cand="$(apt-cache policy libdpdk-dev 2>/dev/null | awk '/Candidate:/{print $2}')"
	if [[ "$cand" == "$DPDK_VERSION"* ]]; then DPDK_MODE=distro; else DPDK_MODE=source; fi
	info "distro libdpdk-dev candidate: ${cand:-none} -> DPDK from $DPDK_MODE"
}

# Install the apt packages, skipping any this release doesn't have.
install_packages() {
	step "Packages"
	local pkgs=(
		rdma-core ibverbs-providers libibverbs-dev ibverbs-utils infiniband-diags
		meson ninja-build pkg-config python3-pyelftools libnuma-dev libpcap-dev
		build-essential gdb git curl xz-utils pciutils ethtool libcap2-bin mstflint clangd
		shellcheck python3-markdown
	)
	# Separate sudo commands on purpose: some sudoers rules allow each only on its own (pitfall 23)
	run sudo apt-get update
	choose_dpdk_source
	if [ "$DPDK_MODE" = distro ]; then
		pkgs+=(dpdk dpdk-dev libdpdk-dev)
	elif dpkg -l dpdk libdpdk-dev 2>/dev/null | grep -q '^ii'; then
		die "distro DPDK packages are installed; remove them before a source build (two DPDKs conflict): sudo apt-get remove dpdk dpdk-dev libdpdk-dev"
	fi

	local avail=() p
	for p in "${pkgs[@]}"; do
		if apt-cache show "$p" >/dev/null 2>&1; then avail+=("$p"); else warn "package $p not available, skipping"; fi
	done
	run sudo apt-get install -y "${avail[@]}"
}

# Build and install DPDK from source when the distro doesn't ship the pinned version.
install_dpdk_from_source() {
	[ "$DPDK_MODE" = source ] || return 0
	if [ "$(pkg-config --modversion libdpdk 2>/dev/null || true)" = "$DPDK_VERSION.0" ]; then
		info "DPDK $DPDK_VERSION already installed from source"
	else
		run "$HERE/tools/build-dpdk-from-source.sh"
	fi
}

# Make sure the mlx5 kernel modules are loaded and the ports are usable by DPDK.
check_kernel_drivers() {
	step "Kernel drivers"
	[ -n "$MLX_PCI" ] || return 0
	local m f pci drv
	for m in mlx5_core mlx5_ib ib_uverbs; do
		if [ -d "/sys/module/$m" ]; then info "$m loaded"; else run sudo modprobe "$m"; fi
	done
	for f in /dev/infiniband/uverbs*; do
		[ -e "$f" ] || { warn "no /dev/infiniband/uverbs* devices (mlx5_ib not bound?)"; break; }
		[ -r "$f" ] && [ -w "$f" ] || warn "$f is not read/writable by $USER (ls -l $f); rdma-core's udev rule normally makes it 0666"
	done
	# mlx5 is bifurcated and must stay on mlx5_core, never vfio-pci (pitfall 2)
	for pci in $MLX_PCI; do
		drv="$(basename "$(readlink -f "/sys/bus/pci/devices/$pci/driver" 2>/dev/null)" 2>/dev/null || true)"
		[ "$drv" = mlx5_core ] || warn "$pci is bound to '${drv:-nothing}', not mlx5_core. mlx5 must NOT be bound to vfio-pci/uio; rebind with dpdk-devbind.py -b mlx5_core $pci"
	done
}

# Reserve the hugepage pool now and at every boot via /etc/sysctl.d.
configure_hugepages() {
	step "Hugepages (${HUGEPAGES_MB} MB of 2 MB pages, persistent)"
	local pages=$((HUGEPAGES_MB / 2)) file=/etc/sysctl.d/80-hugepages.conf got
	if [ "$(cat "$file" 2>/dev/null)" = "vm.nr_hugepages = $pages" ]; then
		info "$file already set to $pages pages"
	else
		run sudo sh -c "echo 'vm.nr_hugepages = $pages' > $file"
	fi
	run sudo sysctl -q -p "$file"
	[ "$DRY" = 0 ] || return 0
	got="$(awk '/HugePages_Total/{print $2}' /proc/meminfo)"
	if [ "$got" -ge "$pages" ]; then
		info "HugePages_Total: $got"
	else
		warn "only $got of $pages hugepages could be reserved (memory fragmented); a reboot will reserve them all"
	fi
}

# Install dpdk-run/dpdk-gdb and the capability-holding dpdk-caps into ~/.local/bin.
install_launchers() {
	step "dpdk-run / dpdk-gdb / dpdk-caps in ~/.local/bin"
	run mkdir -p "$BIN"
	# File capabilities are ignored on nosuid mounts (pitfall 9)
	if findmnt -no OPTIONS -T "$BIN" | grep -qw nosuid; then
		die "$BIN is on a nosuid mount; file capabilities won't work there. Edit BIN in install.sh and the dpdk-* scripts."
	fi
	local f caps="cap_net_admin,cap_net_raw,cap_ipc_lock=p"
	for f in dpdk-run dpdk-gdb; do
		if cmp -s "$HERE/bin/$f" "$BIN/$f"; then info "$f up to date"; else run install -m 0755 "$HERE/bin/$f" "$BIN/$f"; fi
	done
	if cmp -s /usr/sbin/capsh "$BIN/dpdk-caps" && [ "$(/usr/sbin/getcap "$BIN/dpdk-caps" | awk '{print $2}')" = "$caps" ]; then
		info "dpdk-caps up to date ($caps)"
	else
		run sudo install -m 0750 -o "$USER" -g "$(id -gn)" /usr/sbin/capsh "$BIN/dpdk-caps"
		run sudo setcap cap_net_raw,cap_net_admin,cap_ipc_lock+p "$BIN/dpdk-caps"
	fi
	case ":$PATH:" in *":$BIN:"*) ;; *) warn "$BIN is not on PATH; log out and back in (Ubuntu's ~/.profile adds it once the folder exists)";; esac
}

# Install the VS Code extensions and add any missing user settings.
configure_vscode() {
	[ "$VSCODE" = 1 ] || return 0
	step "VS Code"
	if flatpak list 2>/dev/null | grep -q com.visualstudio.code; then
		warn "Flatpak VS Code is sandboxed: dpdk-gdb/F5 and ./run from its terminal won't get capabilities. Use the .deb or snap build."
	fi
	if ! command -v code >/dev/null; then
		warn "'code' not found; install VS Code (.deb or snap), then re-run this script"
		return 0
	fi
	local have ext dry_flag=()
	have="$(code --list-extensions 2>/dev/null || true)"
	for ext in llvm-vs-code-extensions.vscode-clangd mesonbuild.mesonbuild ms-vscode.cpptools; do
		if grep -qix "$ext" <<<"$have"; then info "extension $ext installed"; else run code --install-extension "$ext"; fi
	done
	[ "$DRY" = 1 ] && dry_flag=(--dry-run)
	python3 -I "$HERE/tools/merge-vscode-settings.py" "${dry_flag[@]}" "$HOME/.config/Code/User/settings.json"
}

# Run verify.sh to confirm the result.
verify() {
	step "Verify"
	if [ "$DRY" = 1 ]; then info "would run: $HERE/verify.sh"; else "$HERE/verify.sh"; fi
}

main() {
	parse_args "$@"
	preflight
	install_packages
	install_dpdk_from_source
	check_kernel_drivers
	configure_hugepages
	install_launchers
	configure_vscode
	verify
}

main "$@"
