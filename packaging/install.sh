#!/bin/sh
# Install odin-skel into ~/.local/bin (override with ODIN_SKEL_INSTALL_DIR).
#
#   curl -fsSL https://raw.githubusercontent.com/enerqi/odin-lang-skeleton/master/packaging/install.sh | sh
#
# Deliberately POSIX sh and deliberately small: it downloads one release archive, checks it against
# the published SHA256SUMS, and copies one binary into a directory that is already on PATH on most
# systems. It does not edit shell profiles - it tells you what to add if the directory is missing
# from PATH, and leaves your dotfiles alone.
#
# Environment:
#   ODIN_SKEL_VERSION       version to install (default: the latest release)
#   ODIN_SKEL_INSTALL_DIR   where to put the binary (default: ~/.local/bin)

set -eu

REPO="enerqi/odin-lang-skeleton"
BIN="odin-skel"
INSTALL_DIR="${ODIN_SKEL_INSTALL_DIR:-$HOME/.local/bin}"

die() {
	echo "install.sh: $*" >&2
	exit 1
}

need() {
	command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

# --- what are we running on -------------------------------------------------------------------
os="$(uname -s)"
arch="$(uname -m)"

case "$os" in
	Linux)  os_part="linux" ;;
	Darwin) os_part="macos" ;;
	*)      die "unsupported operating system: $os. On Windows use scoop, or download from https://github.com/$REPO/releases/latest" ;;
esac

case "$arch" in
	x86_64 | amd64)  arch_part="x86_64" ;;
	arm64 | aarch64) arch_part="arm64" ;;
	*)               die "unsupported architecture: $arch" ;;
esac

# Only the combinations the release workflow actually builds. Linux arm64 is not published, so say
# so plainly rather than 404ing on a download.
target="${os_part}-${arch_part}"
case "$target" in
	linux-x86_64 | macos-arm64 | macos-x86_64) ;;
	*) die "no published build for $target. Build from source: https://github.com/$REPO" ;;
esac

asset="${BIN}-${target}.tar.gz"

# --- which version ----------------------------------------------------------------------------
need tar
if command -v curl >/dev/null 2>&1; then
	fetch() { curl -fsSL "$1" -o "$2"; }
	fetch_stdout() { curl -fsSL "$1"; }
elif command -v wget >/dev/null 2>&1; then
	fetch() { wget -qO "$2" "$1"; }
	fetch_stdout() { wget -qO- "$1"; }
else
	die "need curl or wget"
fi

version="${ODIN_SKEL_VERSION:-}"
if [ -z "$version" ]; then
	# Resolve the latest tag without needing jq.
	version="$(fetch_stdout "https://api.github.com/repos/$REPO/releases/latest" \
		| sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
		| head -n 1)"
	[ -n "$version" ] || die "could not determine the latest version; set ODIN_SKEL_VERSION"
fi

base="https://github.com/$REPO/releases/download/$version"
echo "installing $BIN $version ($target) into $INSTALL_DIR"

# --- download and verify ------------------------------------------------------------------------
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM

fetch "$base/$asset" "$work/$asset" || die "download failed: $base/$asset"

# The checksum file is published alongside the archives. Skipping verification would defeat the
# point of publishing it, but a missing file should not be fatal on an older release that predates
# it - warn and continue rather than refusing to install.
if fetch "$base/SHA256SUMS" "$work/SHA256SUMS" 2>/dev/null; then
	if command -v sha256sum >/dev/null 2>&1; then
		actual="$(sha256sum "$work/$asset" | cut -d' ' -f1)"
	elif command -v shasum >/dev/null 2>&1; then
		actual="$(shasum -a 256 "$work/$asset" | cut -d' ' -f1)"
	else
		actual=""
		echo "warning: no sha256sum or shasum available; skipping checksum verification" >&2
	fi

	if [ -n "$actual" ]; then
		expected="$(grep " \*\{0,1\}$asset\$" "$work/SHA256SUMS" | cut -d' ' -f1 | head -n 1)"
		[ -n "$expected" ] || die "$asset is not listed in SHA256SUMS"
		[ "$actual" = "$expected" ] || die "checksum mismatch for $asset
  expected $expected
  actual   $actual"
		echo "checksum ok"
	fi
else
	echo "warning: no SHA256SUMS published for $version; skipping verification" >&2
fi

# --- install --------------------------------------------------------------------------------------
tar xzf "$work/$asset" -C "$work"
[ -f "$work/$BIN" ] || die "archive did not contain $BIN"

mkdir -p "$INSTALL_DIR"
# Copy then move, so an in-use binary is replaced atomically rather than truncated mid-write.
cp "$work/$BIN" "$INSTALL_DIR/.$BIN.new"
chmod +x "$INSTALL_DIR/.$BIN.new"
mv "$INSTALL_DIR/.$BIN.new" "$INSTALL_DIR/$BIN"

echo "installed $INSTALL_DIR/$BIN"

# --- PATH ------------------------------------------------------------------------------------------
case ":$PATH:" in
	*":$INSTALL_DIR:"*)
		"$INSTALL_DIR/$BIN" version
		echo "run '$BIN help' to get started"
		;;
	*)
		echo
		echo "$INSTALL_DIR is not on your PATH. Add it to your shell profile:"
		echo
		echo "    export PATH=\"\$PATH:$INSTALL_DIR\""
		echo
		echo "or run it directly: $INSTALL_DIR/$BIN help"
		;;
esac
