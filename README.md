# xterm-delta

Two Debian 12 xterm builds for Core 2 systems, using the existing upstream scroll-lock implementation.

## Build variants

| Variant | Debian source package | Upstream xterm |
|---|---:|---:|
| Bookworm | `379-1` | #379 |
| Current stable | `412-1` | #412 |

Both variants are built on Debian 12 amd64 with:

- `-O2 -march=core2 -mtune=core2`
- `OPT_SCROLL_LOCK=1`
- Xinerama disabled with `--without-xinerama`
- The optional pulldown toolbar disabled with `--disable-toolbar`

xterm does not provide a native tabbed-window interface. Its terminal tab-stop handling remains enabled because it is part of VT terminal emulation; it is not a GUI tabs feature.

## Scrollback viewport

No custom viewport patch is applied. Both upstream source versions already contain the `autoScrollLock` implementation, guarded by `#if OPT_SCROLL_LOCK`. The build explicitly defines that macro as `1`.

To keep the displayed scrollback viewport stationary while TTY output continues, disable scroll-to-bottom and enable automatic scroll lock at runtime:

```sh
xterm -si -xrm 'XTerm*autoScrollLock: true'
```

The `autoScrollLock` resource is otherwise false by default.

## Build

Run as root on Debian 12:

```sh
./scripts/build-debian12.sh all
```

Or build one source version:

```sh
./scripts/build-debian12.sh 379
./scripts/build-debian12.sh 412
```

The script enables Bookworm and sid source-only indexes; it does not enable sid binary repositories. The 412 source is fetched from sid, while its build environment remains Debian 12. Packages are written to `build/out/379/` and `build/out/412/`.

The GitHub Actions workflow builds both variants independently and uploads separate artifacts. A successful package build verifies compilation, not interactive X11 behavior; see [TESTING.md](TESTING.md).
