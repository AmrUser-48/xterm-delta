#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$REPO_DIR/build}"
JOBS="${JOBS:-2}"

if [[ "$EUID" -ne 0 ]]; then
    printf '%s\n' "Run this build script as root on Debian 12." >&2
    exit 1
fi

case "${1:-all}" in
    379|412|all) ;;
    *)
        printf '%s\n' "Usage: $0 [379|412|all]" >&2
        exit 2
        ;;
esac

# Binary build dependencies still come from the host's configured Debian 12
# repositories; this file adds source indexes for both exact source versions.
cat >/etc/apt/sources.list.d/xterm-delta-src.sources <<'EOF'
Types: deb-src
URIs: https://deb.debian.org/debian
Suites: bookworm bookworm-updates sid
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
    build-essential ca-certificates devscripts dpkg-dev fakeroot quilt

build_variant() {
    local variant="$1"
    local package_version="$2"
    local work_dir="$BUILD_DIR/work/$variant"
    local source_root="$work_dir/source"
    local source_dir
    local output_dir="$BUILD_DIR/out/$variant"

    mkdir -p "$source_root" "$output_dir"
    cd "$source_root"

    apt-get build-dep -y --no-install-recommends "xterm=$package_version"
    apt-get source "xterm=$package_version"

    source_dir="$(find "$source_root" -mindepth 1 -maxdepth 1 -type d -name 'xterm-*' -print -quit)"
    if [[ -z "$source_dir" || ! -f "$source_dir/util.c" ]]; then
        printf 'Could not locate unpacked xterm source for %s\n' "$package_version" >&2
        return 1
    fi

    cd "$source_dir"
    quilt new 99-xterm-delta-scrollback-viewport.patch
    quilt add util.c
    patch --batch --forward -p1 < "$REPO_DIR/patches/xterm-$variant-scrollback-viewport.patch"
    quilt refresh

    dch --local +core2 --distribution bookworm --force-distribution \
        "Build with Core 2 compiler flags and pinned scrollback viewport."

    DEB_CFLAGS_MAINT_APPEND="-O2 -march=core2 -mtune=core2" \
        dpkg-buildpackage -b -us -uc -j"$JOBS"

    find "$source_root" -maxdepth 1 -type f \
        \( -name '*.deb' -o -name '*.buildinfo' \) \
        -exec cp -t "$output_dir" {} +

    if ! compgen -G "$output_dir/*.deb" >/dev/null; then
        printf 'No Debian package was produced for xterm %s\n' "$package_version" >&2
        return 1
    fi
    printf 'Built xterm %s packages in %s\n' "$package_version" "$output_dir"
}

case "${1:-all}" in
    379) build_variant 379 379-1 ;;
    412) build_variant 412 412-1 ;;
    all)
        build_variant 379 379-1
        build_variant 412 412-1
        ;;
esac
