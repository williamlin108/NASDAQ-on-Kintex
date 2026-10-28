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
DPDK_VERSION=25.11
DPDK_MODE=auto
HUGEPAGES_MB=4096
VSCODE=1
DRY=0

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

step() { printf '\n== %s\n' "$*"; }
info() { printf '   %s\n' "$*"; }
warn() { printf '   WARNING: %s\n' "$*" >&2; }
die()  { printf '   ERROR: %s\n' "$*" >&2; exit 1; }
run()  { if [ "$DRY" = 1 ]; then printf '   would run: %s\n' "$*"; else "$@"; fi; }

# ---------------------------------------------------------------------------
step "Preflight"
[ "$(id -u)" != 0 ] || die "run as your normal user, not root/sudo (installs into ~/.local/bin and your VS Code settings)"
. /etc/os-release
[[ " $ID $ID_LIKE " =~ \ (debian|ubuntu)\  ]] || die "only Debian/Ubuntu are supported (found $ID)"
info "OS: $PRETTY_NAME, kernel $(uname -r), arch $(uname -m)"
[ "$(uname -m)" = x86_64 ] || warn "only tested on x86_64"
command -v sudo >/dev/null || die "sudo is required"

# MLNX_OFED / DOCA replace rdma-core with their own copies; mixing them with distro
# DPDK/rdma-core breaks the mlx5 PMD in confusing ways.
if command -v ofed_info >/dev/null || dpkg -l 2>/dev/null | grep -qE '^ii +(mlnx-ofed|doca-)'; then
	die "MLNX_OFED/DOCA detected. This setup uses the inbox kernel driver + distro rdma-core. Uninstall OFED/DOCA first (or adapt by hand)."
fi

MLX_PCI="$(lspci -D -d 15b3: 2>/dev/null | awk '/Ethernet/{print $1}' || true)"
if [ -n "$MLX_PCI" ]; then
	info "Mellanox/NVIDIA Ethernet ports: $(echo $MLX_PCI)"
else
	warn "no Mellanox/NVIDIA Ethernet device found; installing anyway (dev-only machine)"
fi

# ---------------------------------------------------------------------------
step "Packages"
PKGS=(
	rdma-core ibverbs-providers libibverbs-dev ibverbs-utils infiniband-diags
	meson ninja-build pkg-config python3-pyelftools libnuma-dev libpcap-dev
	build-essential gdb git curl xz-utils pciutils ethtool libcap2-bin mstflint clangd
)
# apt-get update and install run as separate sudo commands on purpose: some sudoers
# rules only allow each one on its own.
run sudo apt-get update

if [ "$DPDK_MODE" = auto ]; then
	cand="$(apt-cache policy libdpdk-dev 2>/dev/null | awk '/Candidate:/{print $2}')"
	if [[ "$cand" == "$DPDK_VERSION"* ]]; then DPDK_MODE=distro; else DPDK_MODE=source; fi
	info "distro libdpdk-dev candidate: ${cand:-none} -> DPDK from $DPDK_MODE"
fi
if [ "$DPDK_MODE" = distro ]; then
	PKGS+=(dpdk dpdk-dev libdpdk-dev)
else
	if dpkg -l dpdk libdpdk-dev 2>/dev/null | grep -q '^ii'; then
		die "distro DPDK packages are installed; remove them before a source build (two DPDKs conflict): sudo apt-get remove dpdk dpdk-dev libdpdk-dev"
	fi
fi
# Skip packages this release doesn't have (e.g. clangd on old releases) instead of failing
AVAIL=()
for p in "${PKGS[@]}"; do
	if apt-cache show "$p" >/dev/null 2>&1; then AVAIL+=("$p"); else warn "package $p not available, skipping"; fi
done
run sudo apt-get install -y "${AVAIL[@]}"

if [ "$DPDK_MODE" = source ]; then
	if [ "$(pkg-config --modversion libdpdk 2>/dev/null || true)" = "$DPDK_VERSION.0" ]; then
		info "DPDK $DPDK_VERSION already installed from source"
	else
		run "$HERE/tools/build-dpdk-from-source.sh"
	fi
fi

# ---------------------------------------------------------------------------
step "Kernel drivers"
if [ -n "$MLX_PCI" ]; then
	for m in mlx5_core mlx5_ib ib_uverbs; do
		if [ -d "/sys/module/$m" ]; then info "$m loaded"; else run sudo modprobe "$m"; fi
	done
	for f in /dev/infiniband/uverbs*; do
		[ -e "$f" ] || { warn "no /dev/infiniband/uverbs* devices (mlx5_ib not bound?)"; break; }
		[ -r "$f" ] && [ -w "$f" ] || warn "$f is not read/writable by $USER (ls -l $f); rdma-core's udev rule normally makes it 0666"
	done
	for pci in $MLX_PCI; do
		drv="$(basename "$(readlink -f "/sys/bus/pci/devices/$pci/driver" 2>/dev/null)" 2>/dev/null || true)"
		[ "$drv" = mlx5_core ] || warn "$pci is bound to '${drv:-nothing}', not mlx5_core. mlx5 must NOT be bound to vfio-pci/uio; rebind with dpdk-devbind.py -b mlx5_core $pci"
	done
fi

# ---------------------------------------------------------------------------
step "Hugepages (${HUGEPAGES_MB} MB of 2 MB pages, persistent)"
PAGES=$((HUGEPAGES_MB / 2))
SYSCTL_FILE=/etc/sysctl.d/80-hugepages.conf
if [ "$(cat "$SYSCTL_FILE" 2>/dev/null)" = "vm.nr_hugepages = $PAGES" ]; then
	info "$SYSCTL_FILE already set to $PAGES pages"
else
	run sudo sh -c "echo 'vm.nr_hugepages = $PAGES' > $SYSCTL_FILE"
fi
run sudo sysctl -q -p "$SYSCTL_FILE"
if [ "$DRY" = 0 ]; then
	got="$(awk '/HugePages_Total/{print $2}' /proc/meminfo)"
	[ "$got" -ge "$PAGES" ] && info "HugePages_Total: $got" ||
		warn "only $got of $PAGES hugepages could be reserved (memory fragmented); a reboot will reserve them all"
fi

# ---------------------------------------------------------------------------
step "dpdk-run / dpdk-gdb / dpdk-caps in ~/.local/bin"
BIN="$HOME/.local/bin"
run mkdir -p "$BIN"
# File capabilities are ignored on nosuid mounts (and unsupported on some network filesystems)
if findmnt -no OPTIONS -T "$BIN" | grep -qw nosuid; then
	die "$BIN is on a nosuid mount; file capabilities won't work there. Edit BIN in install.sh and the dpdk-* scripts."
fi
for f in dpdk-run dpdk-gdb; do
	if cmp -s "$HERE/bin/$f" "$BIN/$f"; then info "$f up to date"; else run install -m 0755 "$HERE/bin/$f" "$BIN/$f"; fi
done
CAPS="cap_net_admin,cap_net_raw,cap_ipc_lock=p"
if cmp -s /usr/sbin/capsh "$BIN/dpdk-caps" && [ "$(/usr/sbin/getcap "$BIN/dpdk-caps" | awk '{print $2}')" = "$CAPS" ]; then
	info "dpdk-caps up to date ($CAPS)"
else
	run sudo install -m 0750 -o "$USER" -g "$(id -gn)" /usr/sbin/capsh "$BIN/dpdk-caps"
	run sudo setcap cap_net_raw,cap_net_admin,cap_ipc_lock+p "$BIN/dpdk-caps"
fi
case ":$PATH:" in *":$BIN:"*) ;; *) warn "$BIN is not on PATH; log out and back in (Ubuntu's ~/.profile adds it once the folder exists)";; esac
run mkdir -p "$HOME/dpdk-projects"

# ---------------------------------------------------------------------------
if [ "$VSCODE" = 1 ]; then
	step "VS Code"
	if flatpak list 2>/dev/null | grep -q com.visualstudio.code; then
		warn "Flatpak VS Code is sandboxed: dpdk-gdb/F5 and ./run from its terminal won't get capabilities. Use the .deb or snap build."
	fi
	if ! command -v code >/dev/null; then
		warn "'code' not found; install VS Code (.deb or snap), then re-run this script"
	else
		have="$(code --list-extensions 2>/dev/null || true)"
		for ext in llvm-vs-code-extensions.vscode-clangd mesonbuild.mesonbuild ms-vscode.cpptools; do
			if grep -qix "$ext" <<<"$have"; then info "extension $ext installed"; else run code --install-extension "$ext"; fi
		done
		SETTINGS="$HOME/.config/Code/User/settings.json"
		if [ "$DRY" = 1 ]; then
			python3 -I "$HERE/tools/merge-vscode-settings.py" --dry-run "$SETTINGS"
		else
			python3 -I "$HERE/tools/merge-vscode-settings.py" "$SETTINGS"
		fi
	fi
fi

# ---------------------------------------------------------------------------
step "Verify"
if [ "$DRY" = 1 ]; then
	info "would run: $HERE/verify.sh"
else
	"$HERE/verify.sh"
fi
