# xterm-delta

Debian 12 xterm builds with a stationary scrollback viewport during live TTY output.

## Two independent source builds

| Variant | Debian source package | Upstream xterm | Purpose |
|---|---:|---:|---|
| Bookworm baseline | `379-1` | Patch #379 | Debian 12's packaged xterm |
| Current stable | `412-1` | Patch #412 | Current stable xterm, built on Debian 12 |

The 379 build starts from the Bookworm Debian source package and preserves its Debian packaging and patch series. The 412 build starts from Debian's 412-1 source package (the Debian packaging of upstream xterm 412); it is compiled in the same Debian 12 environment. Each source version has its own viewport patch under `patches/`.

The fix addresses the original issue: when `scrollTtyOutput` is disabled and the user scrolls into history, streaming output must not move the rows currently being read. The normal screen's saved-lines FIFO continues to receive output. The viewport remains anchored until the FIFO evicts rows above it; only then does the view advance and repaint.

## Core 2 build

Debian's standard build and hardening flags are retained, with these architecture flags appended:

```text
-O2 -march=core2 -mtune=core2
```

There is no `-march=native`. The packages target Debian 12 amd64.

Run as root on Debian 12:

```sh
./scripts/build-debian12.sh all
```

Or build one variant:

```sh
./scripts/build-debian12.sh 379
./scripts/build-debian12.sh 412
```

The script enables Bookworm and sid **source-only** indexes; it does not enable sid binary repositories. The 412 source is fetched from sid, while build dependencies are resolved from Bookworm's xterm 379 build-dependency set plus the additional X11 development headers required by 412. It adds the matching viewport patch as a quilt patch and builds with `dpkg-buildpackage`. Packages and build metadata are placed under `build/out/379/` and `build/out/412/`.

## Viewport behavior

- Keeps historical rows stationary during continuous output with `-si`.
- Uses the actual scroll amount, including multi-line batches.
- Updates saved-lines and scrollbar state using xterm's existing accounting.
- Excludes the alternate screen and scroll operations that do not save complete lines.
- Adjusts selection coordinates only when the FIFO evicts rows above the current view.
- Repaints only when eviction makes the former top rows unavailable.

See [info.txt](info.txt) for the technical specification and [TESTING.md](TESTING.md) for runtime checks.
