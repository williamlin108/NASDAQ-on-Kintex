#!/bin/bash
# Check that this machine matches the reference DPDK/mlx5 setup. Read-only, except
# --full, which builds a throwaway project in a temp dir and deletes it afterwards.
#
#   ./verify.sh          # system checks + probe the mlx5 ports with testpmd
#   ./verify.sh --full   # also: new-project.sh, ./run, and a headless F5 debug session
#
# Exit code = number of FAILs.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/.local/bin"
EXPECT_DPDK=25.11
FULL=0
FAILS=0
MLX_PCI=""

# Print a passed check.
pass() { printf 'PASS  %s\n' "$*"; }
# Print a non-fatal warning.
warn() { printf 'WARN  %s\n' "$*"; }
# Print a failed check and count it.
fail() { printf 'FAIL  %s\n' "$*"; FAILS=$((FAILS + 1)); }

# Check the DPDK version, its mlx5 driver, testpmd, and that only one DPDK is installed.
check_dpdk() {
	local v libdir n
	if v="$(pkg-config --modversion libdpdk 2>/dev/null)"; then
		[[ "$v" == "$EXPECT_DPDK"* ]] && pass "DPDK $v" || warn "DPDK $v (reference machine has $EXPECT_DPDK; API/behaviour may differ)"
		libdir="$(pkg-config --variable=libdir libdpdk)"
		ls "$libdir"/librte_net_mlx5.so* >/dev/null 2>&1 && pass "mlx5 PMD present in $libdir" || fail "librte_net_mlx5 missing in $libdir (DPDK built without rdma-core?)"
	else
		fail "libdpdk not found by pkg-config (run install.sh)"
	fi
	command -v dpdk-testpmd >/dev/null && pass "dpdk-testpmd on PATH" || fail "dpdk-testpmd not on PATH"
	n="$(dpkg -l dpdk libdpdk-dev 2>/dev/null | grep -c '^ii' || true)"
	if [ "$n" -gt 0 ] && [ -e /usr/local/lib/x86_64-linux-gnu/pkgconfig/libdpdk.pc ]; then
		fail "both distro DPDK packages and a /usr/local source build are installed; remove one"
	fi
}

# Check each mlx5 port's kernel driver, verbs device, device permissions and firmware.
check_nic() {
	command -v ofed_info >/dev/null && fail "MLNX_OFED detected (ofed_info); this setup expects inbox drivers + distro rdma-core"
	MLX_PCI="$(lspci -D -d 15b3: 2>/dev/null | awk '/Ethernet/{print $1}')"
	if [ -z "$MLX_PCI" ]; then
		warn "no Mellanox/NVIDIA Ethernet ports; skipping hardware checks"
		return
	fi
	local pci drv ib f fw
	for pci in $MLX_PCI; do
		drv="$(basename "$(readlink -f "/sys/bus/pci/devices/$pci/driver" 2>/dev/null)" 2>/dev/null)"
		[ "$drv" = mlx5_core ] && pass "$pci bound to mlx5_core" || fail "$pci bound to '${drv:-nothing}' (must be mlx5_core, never vfio-pci)"
		# Verbs names change after reboot (pitfall 6), so look the device up by PCI address
		ib="$(ls "/sys/bus/pci/devices/$pci/infiniband" 2>/dev/null | head -1)"
		[ -n "$ib" ] && pass "$pci verbs device: $ib" || fail "$pci has no verbs device (mlx5_ib/ib_uverbs not loaded?)"
		fw="$(ethtool -i "$(ls "/sys/bus/pci/devices/$pci/net" 2>/dev/null | head -1)" 2>/dev/null | awk '/firmware-version/{print $2}')"
		[ -z "$fw" ] || pass "$pci firmware $fw"
	done
	for f in /dev/infiniband/uverbs*; do
		[ -r "$f" ] && [ -w "$f" ] && pass "$f read/writable" || fail "$f not read/writable by $USER"
	done
}

# Check the hugepage pool, its persistence, and leftover files from sudo runs.
check_hugepages() {
	local total free
	total="$(awk '/HugePages_Total/{print $2}' /proc/meminfo)"
	free="$(awk '/HugePages_Free/{print $2}' /proc/meminfo)"
	[ "$total" -gt 0 ] && pass "hugepages: $free free of $total x 2 MB" || fail "no hugepages reserved"
	[ -f /etc/sysctl.d/80-hugepages.conf ] && pass "hugepages persistent ($(cat /etc/sysctl.d/80-hugepages.conf))" || warn "hugepages not persistent (no /etc/sysctl.d/80-hugepages.conf)"
	if ls /dev/hugepages/rtemap_* >/dev/null 2>&1; then
		warn "leftover /dev/hugepages/rtemap_* files from a sudo run without --in-memory (sudo rm them, or reboot)"
	fi
}

# Check dpdk-run/dpdk-gdb match the kit and dpdk-caps holds the right capabilities.
check_launchers() {
	local f caps
	for f in dpdk-run dpdk-gdb; do
		if [ ! -x "$BIN/$f" ]; then
			fail "$BIN/$f missing"
		elif cmp -s "$HERE/bin/$f" "$BIN/$f"; then
			pass "$f installed"
		else
			warn "$BIN/$f differs from Installation/bin/$f"
		fi
	done
	caps="$(/usr/sbin/getcap "$BIN/dpdk-caps" 2>/dev/null | awk '{print $2}')"
	[ "$caps" = "cap_net_admin,cap_net_raw,cap_ipc_lock=p" ] && pass "dpdk-caps has $caps" || fail "dpdk-caps missing or wrong caps ('$caps')"
	case ":$PATH:" in *":$BIN:"*) pass "$BIN on PATH" ;; *) warn "$BIN not on PATH (log out/in)" ;; esac
}

# Open every mlx5 port with testpmd through dpdk-run to prove DPDK works without sudo.
probe_ports() {
	[ -n "$MLX_PCI" ] && [ -x "$BIN/dpdk-caps" ] && command -v dpdk-testpmd >/dev/null || return 0
	local allow=() pci out ports want
	for pci in $MLX_PCI; do allow+=(-a "${pci#0000:}"); done
	out="$(printf 'quit\n' | timeout 60 "$BIN/dpdk-run" dpdk-testpmd -l 0-1 --in-memory "${allow[@]}" -- -i --total-num-mbufs=4096 2>&1)"
	ports="$(grep -cE '^Port [0-9]+: ([0-9A-F]{2}:){5}' <<<"$out")"
	want="$(wc -w <<<"$MLX_PCI")"
	if [ "$ports" = "$want" ]; then
		pass "testpmd via dpdk-run opened $ports/$want mlx5 ports without sudo"
	else
		fail "testpmd via dpdk-run opened $ports/$want ports. Last lines:"
		grep -E 'TIS|cannot|rror|fail' <<<"$out" | head -5 | sed 's/^/        /'
	fi
}

# Check the VS Code extensions and the Meson build-folder setting.
check_vscode() {
	if ! command -v code >/dev/null; then
		warn "VS Code ('code') not found"
		return
	fi
	local exts ext
	exts="$(code --list-extensions 2>/dev/null)"
	for ext in llvm-vs-code-extensions.vscode-clangd mesonbuild.mesonbuild ms-vscode.cpptools; do
		grep -qix "$ext" <<<"$exts" && pass "VS Code extension $ext" || warn "VS Code extension $ext not installed"
	done
	if grep -q '"mesonbuild.buildFolder"' "$HOME/.config/Code/User/settings.json" 2>/dev/null; then
		pass "VS Code mesonbuild.buildFolder set"
	else
		warn "VS Code mesonbuild.buildFolder not set (Meson extension will use builddir/)"
	fi
}

# Run a project's ./run and a headless F5 session, and check both reach the ports.
check_project_runs() {
	local dir="$1" out f5
	out="$(cd "$dir" && ./run 2>&1)"
	grep -q '^port 0:' <<<"$out" && pass "./run probed ports" || fail "./run failed: $(tail -2 <<<"$out")"
	command -v code >/dev/null || return 0
	f5="$(timeout 180 python3 -I "$HERE/tools/test-f5.py" "$dir" 2>&1)"
	if grep -q '^PASS' <<<"$f5"; then
		pass "F5 debug session (headless, via VS Code's C++ debug adapter)"
	else
		fail "F5 debug session: $(grep -E '^FAIL' <<<"$f5" | head -1)"
	fi
}

# Create a throwaway project with new-project.sh, test it, and delete it.
check_full_workflow() {
	local tmp
	tmp="$(mktemp -d)"
	if "$HERE/new-project.sh" verify-probe --dir "$tmp" --no-git >/dev/null 2>"$tmp/err"; then
		pass "new-project.sh created and built a project"
		check_project_runs "$tmp/verify-probe"
	else
		fail "new-project.sh: $(tail -2 "$tmp/err")"
	fi
	rm -rf "$tmp"
}

main() {
	[ "${1:-}" = --full ] && FULL=1
	check_dpdk
	check_nic
	check_hugepages
	check_launchers
	probe_ports
	check_vscode
	[ "$FULL" = 0 ] || check_full_workflow

	echo
	[ "$FAILS" = 0 ] && echo "All checks passed." || echo "$FAILS check(s) failed."
	exit "$FAILS"
}

main "$@"
