#!/usr/bin/env bash
# Builds both server modules in a container old enough for the game hosts.
#
# Building on a modern distro versions dlopen/dlsym at GLIBC_2.34, so the module
# will not load on anything older than Debian 12 / Ubuntu 22.04. AlmaLinux 8 is
# glibc 2.28, which keeps those symbols in libdl and covers any host still
# running 32-bit srcds.
set -euo pipefail

IMAGE=almalinux:8
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/../lua/bin"

docker run --rm -v "$HERE:/src" -v "metaconcord-cargo:/root/.cargo" -v "metaconcord-rustup:/root/.rustup" \
	-e "HOST_UID=$(id -u)" -e "HOST_GID=$(id -g)" -w /src "$IMAGE" bash -euo pipefail -c '
	dnf -q -y install gcc glibc-devel glibc-devel.i686 libgcc.i686 >/dev/null
	# rustup keeps its toolchains in ~/.rustup and only the launchers in
	# ~/.cargo, so both are cached or the second run finds no toolchain
	if [ ! -d /root/.rustup/toolchains ]; then
		curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain nightly >/dev/null
	fi
	export PATH=/root/.cargo/bin:$PATH
	rustup -q default nightly
	rustup -q target add i686-unknown-linux-gnu x86_64-unknown-linux-gnu
	cargo build --release --target i686-unknown-linux-gnu
	cargo build --release --target x86_64-unknown-linux-gnu
	# the build runs as root, so hand target/ back or the host cannot clean it
	chown -R "$HOST_UID:$HOST_GID" /src/target
'

mkdir -p "$OUT"
cp "$HERE/target/i686-unknown-linux-gnu/release/libmetaconcord.so"   "$OUT/gmsv_metaconcord_linux.dll"
cp "$HERE/target/x86_64-unknown-linux-gnu/release/libmetaconcord.so" "$OUT/gmsv_metaconcord_linux64.dll"

for f in "$OUT/gmsv_metaconcord_linux.dll" "$OUT/gmsv_metaconcord_linux64.dll"; do
	printf '%s\n  %s\n  max glibc: %s\n  exports:   %s\n' \
		"$(basename "$f")" \
		"$(file -b "$f" | cut -d, -f1-2)" \
		"$(objdump -T "$f" | grep -o 'GLIBC_[0-9.]*' | sort -V -u | tail -1)" \
		"$(nm -D --defined-only "$f" | awk '{printf "%s ", $3}')"
done
