# metaconcord native module

Serverside binary module giving the Lua addon host information the sandbox
cannot reach. It touches no engine internals, only the Lua state.

The addon works without it. A server missing the module still relays chat,
status, bans, rcon and the console; it loses stats, the addon list and gserv.

## API

Exposed as the global `metaconcord_native`, re-homed by `init.lua` as
`metaconcord.native`.

| Function | Returns |
|---|---|
| `Version()` | module version string |
| `Stats()` | `{cpu, memUsed, memMax, netRx, netTx}`, or `nil, err`. `cpu` is a percentage of one core since the previous call, so the first call reads 0. |

## Building

```sh
./build.sh
```

Builds both architectures in a container and writes `gmsv_metaconcord_linux.dll`
and `gmsv_metaconcord_linux64.dll` into `../lua/bin/`, which is where the addon
ships them.

The container is not optional. Building on a modern distro versions
`dlopen`/`dlsym` at `GLIBC_2.34`, so the module fails to load on anything older
than Debian 12 / Ubuntu 22.04. AlmaLinux 8 is glibc 2.28.

Check the floor after any dependency change:

```sh
objdump -T ../lua/bin/gmsv_metaconcord_linux.dll | grep -o 'GLIBC_[0-9.]*' | sort -V -u | tail -1
```

Requires docker. For a local build without one, `cargo build --release --target
i686-unknown-linux-gnu` works but produces a binary the servers may reject.

## Tests

```sh
cargo test                                  # parsing and a live /proc sample
cargo test --release -- --ignored --nocapture   # print a sample to compare by eye
```
