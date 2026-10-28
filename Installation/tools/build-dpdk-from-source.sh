#!/bin/bash
# Build and install a pinned DPDK release from dpdk.org, for machines whose distro
# ships a different DPDK version than the reference machine (25.11).
#
#   tools/build-dpdk-from-source.sh              # build + sudo install to /usr/local
#   tools/build-dpdk-from-source.sh --no-install # build only (for testing)
#
# Do not also have the distro dpdk/libdpdk-dev packages installed: two DPDKs on one
# machine mix headers, libraries and PMD plugin directories.
set -euo pipefail

VERSION=25.11
SHA256=52e90d2a531ef3ded0283bd91abc94980698f1f6471fa09658a0217cf6609526
PREFIX=/usr/local
WORKDIR="${XDG_CACHE_HOME:-$HOME/.cache}/dpdk-src"
INSTALL=1

while [ $# -gt 0 ]; do
	case "$1" in
	--no-install) INSTALL=0 ;;
	--workdir) WORKDIR="$2"; shift ;;
	--prefix) PREFIX="$2"; shift ;;
	*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
	shift
done

TARBALL="dpdk-$VERSION.tar.xz"
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

# The mstflint package installs a static libmtcr_ul.a that DPDK's mlx5 build picks up
# automatically and then fails to link (undefined std::ostringstream etc.). Ubuntu's
# DPDK package is built without it, so disable the lookup to match. There is no meson
# option for this; fail loudly if a future release changes the line.
MTCR_LINE="lib = cc.find_library('mtcr_ul', required:false)"
MTCR_FILE=drivers/common/mlx5/linux/meson.build
grep -qF "$MTCR_LINE" "$MTCR_FILE" || { echo "ERROR: mtcr_ul lookup not found in $MTCR_FILE; update this script" >&2; exit 1; }
sed -i "s|$MTCR_LINE|lib = dependency('', required: false)  # mtcr_ul disabled by build-dpdk-from-source.sh|" "$MTCR_FILE"

# Only testpmd is needed from the apps; skip tests/examples/docs to cut build time.
# mlx5 is built automatically when libibverbs-dev (rdma-core) is installed.
meson setup build --prefix="$PREFIX" --buildtype=release \
	-Denable_apps=test-pmd -Dtests=false -Dexamples= -Denable_docs=false
if ! meson introspect build --targets | grep -q '"rte_net_mlx5"'; then
	echo "ERROR: mlx5 driver not configured; is libibverbs-dev installed?" >&2
	exit 1
fi
ninja -C build

if [ "$INSTALL" = 1 ]; then
	sudo meson install -C build --quiet
	sudo ldconfig
	echo "== installed DPDK $VERSION to $PREFIX"
	pkg-config --modversion libdpdk
else
	echo "== built (not installed) in $WORKDIR/dpdk-$VERSION/build"
fi
