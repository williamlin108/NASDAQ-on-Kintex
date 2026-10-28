#!/bin/bash
# Build and install a pinned DPDK release from dpdk.org, for machines whose distro
# ships a different DPDK version than the reference machine (25.11).
#
#   tools/build-dpdk-from-source.sh              # build + sudo install to /usr/local
#   tools/build-dpdk-from-source.sh --no-install # build only (for testing)
#
# Do not also have the distro dpdk/libdpdk-dev packages installed: two DPDKs on one
# machine mix headers, libraries and PMD plugin directories (pitfall 5).
set -euo pipefail

VERSION=25.11
SHA256=52e90d2a531ef3ded0283bd91abc94980698f1f6471fa09658a0217cf6609526
TARBALL="dpdk-$VERSION.tar.xz"
PREFIX=/usr/local
WORKDIR="${XDG_CACHE_HOME:-$HOME/.cache}/dpdk-src"
INSTALL=1

# Print an error and exit.
die() { echo "ERROR: $*" >&2; exit 1; }

# Parse command-line options into the globals above.
parse_args() {
	while [ $# -gt 0 ]; do
		case "$1" in
		--no-install) INSTALL=0 ;;
		--workdir) WORKDIR="$2"; shift ;;
		--prefix) PREFIX="$2"; shift ;;
		*) echo "unknown option: $1" >&2; exit 2 ;;
		esac
		shift
	done
}

# Download the release tarball (once), check its pinned SHA-256, and unpack a fresh copy.
fetch_source() {
	mkdir -p "$WORKDIR"
	cd "$WORKDIR"
	if [ ! -f "$TARBALL" ]; then
		echo "== downloading $TARBALL"
		curl -fL --retry 3 -o "$TARBALL.part" "https://fast.dpdk.org/rel/$TARBALL"
		mv "$TARBALL.part" "$TARBALL"
	fi
	echo "$SHA256  $TARBALL" | sha256sum -c -
	rm -rf "dpdk-$VERSION"
	tar xf "$TARBALL"
	cd "dpdk-$VERSION"
}

# Stop DPDK's mlx5 build from linking mstflint's libmtcr_ul.a, which fails (pitfall 4).
disable_mtcr_lookup() {
	# Ubuntu's DPDK package is built without it too. There is no meson option for this,
	# so edit the one line, and fail loudly if a future release changes it.
	local line="lib = cc.find_library('mtcr_ul', required:false)"
	local file=drivers/common/mlx5/linux/meson.build
	grep -qF "$line" "$file" || die "mtcr_ul lookup not found in $file; update this script"
	sed -i "s|$line|lib = dependency('', required: false)  # mtcr_ul disabled by build-dpdk-from-source.sh|" "$file"
}

# Configure and compile DPDK with testpmd, failing if the mlx5 driver wasn't configured.
build_dpdk() {
	# Only testpmd is needed from the apps; skip tests/examples/docs to cut build time
	meson setup build --prefix="$PREFIX" --buildtype=release \
		-Denable_apps=test-pmd -Dtests=false -Dexamples= -Denable_docs=false
	# mlx5 is only built when libibverbs-dev (rdma-core) is installed
	meson introspect build --targets | grep -q '"rte_net_mlx5"' ||
		die "mlx5 driver not configured; is libibverbs-dev installed?"
	ninja -C build
}

# Install the build system-wide (sudo), or just report where it is with --no-install.
install_dpdk() {
	if [ "$INSTALL" = 0 ]; then
		echo "== built (not installed) in $WORKDIR/dpdk-$VERSION/build"
		return
	fi
	sudo meson install -C build --quiet
	sudo ldconfig
	echo "== installed DPDK $VERSION to $PREFIX"
	pkg-config --modversion libdpdk
}

main() {
	parse_args "$@"
	fetch_source
	disable_mtcr_lookup
	build_dpdk
	install_dpdk
}

main "$@"
