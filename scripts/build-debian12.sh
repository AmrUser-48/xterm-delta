#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "$(readlink -f "$0")")/.." && pwd)"
BUILD="$ROOT/build"
WORK="$BUILD/work"
OUT="$BUILD/out"
LOGS="$BUILD/logs"
JOBS="$(nproc)"

rm -rf "$WORK" "$OUT" "$LOGS"
mkdir -p "$WORK" "$OUT" "$LOGS"
exec > >(tee "$LOGS/build.log") 2>&1

fail() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
trap 'status=$?; printf "\nBUILD FAILED at line %s (exit %s)\n" "$LINENO" "$status" >&2' ERR

. /etc/os-release
[[ "$VERSION_ID" == "12" ]] || fail "Must build in Debian 12, found $PRETTY_NAME"

cat >/etc/apt/sources.list.d/bookworm-src.list <<'EOF'
deb-src http://deb.debian.org/debian bookworm main
EOF

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
    build-essential ca-certificates curl devscripts dpkg-dev equivs \
    fakeroot git lintian python3 quilt
apt-get build-dep -y xterm

apt-cache policy xterm | tee "$LOGS/stock-xterm-policy.txt"
STOCK_CANDIDATE="$(apt-cache policy xterm | awk '/Candidate:/ {print $2; exit}')"
[[ -n "$STOCK_CANDIDATE" && "$STOCK_CANDIDATE" != '(none)' ]] || fail 'Bookworm xterm candidate unavailable'

check_configure_flags() {
    source="$1"
    help="$2"
    shift 2
    cd "$source"
    ./configure --help >"$help" 2>&1
    for flag in "$@"; do
        grep -Fq -- "$flag" "$help" || fail "$(basename "$source"): configure lacks $flag"
    done
}

append_configure_flags() {
    source="$1"
    shift
    python3 - "$source/debian/rules" "$@" <<'PY'
import re, sys
from pathlib import Path
path = Path(sys.argv[1])
flags = sys.argv[2:]
lines = path.read_text().splitlines(keepends=True)
rule = next((i for i, s in enumerate(lines) if re.match(r"^override_dh_auto_configure\s*:", s)), None)
if rule is None:
    raise SystemExit("debian/rules has no override_dh_auto_configure target")
stop = next((i for i in range(rule + 1, len(lines))
             if lines[i] and not lines[i][0].isspace()
             and re.match(r"^[A-Za-z0-9_.%/-]+\s*:", lines[i])), len(lines))
cmd = next((i for i in range(rule + 1, stop) if re.search(r"\bdh_auto_configure\b", lines[i])), None)
if cmd is None:
    raise SystemExit("override_dh_auto_configure has no dh_auto_configure command")
end = cmd
while lines[end].rstrip().endswith("\\"):
    end += 1
    if end >= stop:
        raise SystemExit("unterminated configure continuation")
block = "".join(lines[cmd:end + 1])
missing = [flag for flag in flags if flag not in block]
if missing:
    lines[end] = lines[end].rstrip("\r\n").rstrip() + " \\\n"
    lines[end + 1:end + 1] = [
        "\t" + flag + (" \\\n" if n + 1 < len(missing) else "\n")
        for n, flag in enumerate(missing)
    ]
    path.write_text("".join(lines))
    print("Added:", " ".join(missing))
else:
    print("All requested flags are already present")
PY
}

# Track A: Debian Bookworm xterm +custom1.
mkdir -p "$WORK/track-a"
cd "$WORK/track-a"
apt-get source xterm
A_SOURCE="$(find "$WORK/track-a" -mindepth 1 -maxdepth 1 -type d -name 'xterm-*' -print -quit)"
[[ -n "$A_SOURCE" && -f "$A_SOURCE/debian/rules" && -f "$A_SOURCE/configure" ]] || fail 'Track A source tree incomplete'
printf 'Track A source: %s\n' "$(cd "$A_SOURCE" && dpkg-parsechangelog -S Version)"
cat "$A_SOURCE/debian/rules" | tee "$LOGS/track-a-rules.before"
cp -a "$A_SOURCE/debian" "$WORK/debian-template"

check_configure_flags "$A_SOURCE" "$LOGS/track-a-configure-help.txt" \
    --without-xinerama --disable-tek4014 --disable-vt52 \
    --disable-sixel-graphics --disable-print-graphics --disable-session-mgt \
    --disable-tcap-fkeys --disable-tcap-query --disable-sun-fkeys \
    --disable-paste64 --disable-exec-selection
append_configure_flags "$A_SOURCE" \
    --without-xinerama --disable-tek4014 --disable-vt52 \
    --disable-sixel-graphics --disable-print-graphics --disable-session-mgt \
    --disable-tcap-fkeys --disable-tcap-query --disable-sun-fkeys \
    --disable-paste64 --disable-exec-selection
cp "$A_SOURCE/debian/rules" "$LOGS/track-a-rules.after"

export DEBFULLNAME="xterm package build"
export DEBEMAIL="builder@localhost"
(
    cd "$A_SOURCE"
    dch --local +custom1 --distribution bookworm --force-distribution \
        'Trim optional terminal features; keep scroll-lock support.'
    DEB_CFLAGS_MAINT_APPEND="-O2 -march=core2 -mtune=core2" \
        dpkg-buildpackage -us -uc -b -j"$JOBS"
)
A_VERSION="$(cd "$A_SOURCE" && dpkg-parsechangelog -S Version)"
A_DEB="$(find "$WORK/track-a" -maxdepth 1 -type f -name "xterm_"$A_VERSION"_*.deb" -print -quit)"
[[ -n "$A_DEB" ]] || fail "Track A xterm package missing"
cp "$A_DEB" "$OUT/"
printf 'TRACK A PACKAGE: %s\n' "$(basename "$A_DEB")"

# Track B: newest upstream tag, packaged below /opt/xterm-latest.
cd "$WORK"
LATEST_TAG="$(git ls-remote --tags --refs https://github.com/ThomasDickey/xterm-snapshots.git 'refs/tags/xterm-[0-9]*' \
    | awk '{sub("refs/tags/", "", $2); print $2}' \
    | grep -E '^xterm-[0-9]+$' | sort -V | tail -n 1)"
[[ -n "$LATEST_TAG" ]] || fail 'Could not determine newest upstream xterm tag'
LATEST_VERSION="$(printf '%s' "$LATEST_TAG" | sed 's/^xterm-//')"
printf 'Track B upstream tag: %s\n' "$LATEST_TAG"
curl -fL --retry 3 \
    "https://github.com/ThomasDickey/xterm-snapshots/archive/refs/tags/$LATEST_TAG.tar.gz" \
    -o "$WORK/$LATEST_TAG.tar.gz"
B_SOURCE="$WORK/xterm-latest"
mkdir -p "$B_SOURCE"
tar -xzf "$WORK/$LATEST_TAG.tar.gz" --strip-components=1 -C "$B_SOURCE"
[[ -f "$B_SOURCE/configure" ]] || fail "Upstream archive $LATEST_TAG incomplete"
cp -a "$WORK/debian-template" "$B_SOURCE/debian"

cd "$B_SOURCE"
cat debian/rules | tee "$LOGS/track-b-rules.before"
if [[ -s debian/patches/series ]]; then
    export QUILT_PATCHES=debian/patches
    : >"$LOGS/track-b-dropped-patches.txt"
    while ! quilt push -a >"$LOGS/track-b-quilt.log" 2>&1; do
        cat "$LOGS/track-b-quilt.log"
        FAILED_PATCH="$(sed -n 's/^Applying patch //p' "$LOGS/track-b-quilt.log" | tail -n 1)"
        [[ -n "$FAILED_PATCH" ]] || fail 'quilt failed without identifying the incompatible patch'
        quilt pop -a >/dev/null 2>&1 || true
        grep -Fvx "$FAILED_PATCH" debian/patches/series >debian/patches/series.new || true
        cmp -s debian/patches/series debian/patches/series.new && fail "Could not drop $FAILED_PATCH"
        mv debian/patches/series.new debian/patches/series
        printf '%s\n' "$FAILED_PATCH" | tee -a "$LOGS/track-b-dropped-patches.txt"
    done
    cat "$LOGS/track-b-quilt.log"
fi

python3 - "$B_SOURCE" "$LATEST_VERSION" <<'PY'
import re, sys
from pathlib import Path
root = Path(sys.argv[1])
version = sys.argv[2]
d = root / "debian"
control = d / "control"
text = control.read_text()
text, ns = re.subn(r"(?m)^Source:\s*xterm\s*$", "Source: xterm-latest", text, count=1)
text, np = re.subn(r"(?m)^Package:\s*xterm\s*$", "Package: xterm-latest", text, count=1)
if ns != 1 or np != 1:
    raise SystemExit(f"Expected one Source and Package stanza for xterm; found {ns}/{np}")
control.write_text(text)

for p in list(d.glob("xterm.*")):
    p.rename(p.with_name("xterm-latest" + p.name[len("xterm"):]))

rules = d / "rules"
text = rules.read_text().replace("debian/xterm", "debian/xterm-latest")
text = re.sub(r"(?<![A-Za-z0-9_-])-pxterm(?![A-Za-z0-9_-])", "-pxterm-latest", text)
text = text.replace("/etc/X11/app-defaults", "/opt/xterm-latest/lib/X11/app-defaults")
text = text.replace("/usr/share/icons", "/opt/xterm-latest/share/icons")
text = text.replace("/usr/share/pixmaps", "/opt/xterm-latest/share/pixmaps")
text = text.replace("/usr/share/applications", "/opt/xterm-latest/share/applications")
rules.write_text(text)

for p in d.glob("xterm-latest.*"):
    if not p.is_file() or p.suffix not in {".install", ".links", ".manpages", ".dirs"}:
        continue
    output = []
    for line in p.read_text().splitlines():
        stripped = line.lstrip()
        lead = line[:len(line) - len(stripped)]
        if not stripped or stripped.startswith("#"):
            output.append(line)
            continue
        for old, new in (
            ("etc/X11/app-defaults/", "opt/xterm-latest/lib/X11/app-defaults/"),
            ("usr/bin/", "opt/xterm-latest/bin/"),
            ("usr/share/man/", "opt/xterm-latest/share/man/"),
            ("usr/share/icons/", "opt/xterm-latest/share/icons/"),
            ("usr/share/pixmaps/", "opt/xterm-latest/share/pixmaps/"),
            ("usr/share/applications/", "opt/xterm-latest/share/applications/"),
            ("usr/share/terminfo/", "opt/xterm-latest/share/terminfo/"),
        ):
            if stripped.startswith(old):
                stripped = new + stripped[len(old):]
                break
        output.append(lead + stripped)
    p.write_text("\n".join(output) + "\n")

for name in ("xterm-latest.links", "xterm-latest.menu"):
    p = d / name
    if p.exists():
        p.unlink()

(d / "changelog").write_text(
    f"xterm-latest ({version}-0custom1) bookworm; urgency=medium\n\n"
    f"  * Package upstream xterm-{version} beside Debian's xterm.\n"
    f"  * Install the upstream build below /opt/xterm-latest.\n\n"
    " -- xterm package build <builder@localhost>  "
    "Sat, 21 Nov 2026 00:00:00 +0000\n"
)
PY

check_configure_flags "$B_SOURCE" "$LOGS/track-b-configure-help.txt" \
    --without-xinerama --disable-tek4014 --disable-vt52 \
    --disable-sixel-graphics --disable-print-graphics --disable-session-mgt \
    --disable-tcap-fkeys --disable-tcap-query --disable-sun-fkeys \
    --disable-paste64 --disable-exec-selection \
    --prefix --exec-prefix --mandir --with-app-defaults --with-icondir --with-pixmapdir
append_configure_flags "$B_SOURCE" \
    --without-xinerama --disable-tek4014 --disable-vt52 \
    --disable-sixel-graphics --disable-print-graphics --disable-session-mgt \
    --disable-tcap-fkeys --disable-tcap-query --disable-sun-fkeys \
    --disable-paste64 --disable-exec-selection \
    --prefix=/opt/xterm-latest --exec-prefix=/opt/xterm-latest \
    --mandir=/opt/xterm-latest/share/man \
    --with-app-defaults=/opt/xterm-latest/lib/X11/app-defaults \
    --with-icondir=/opt/xterm-latest/share/icons \
    --with-pixmapdir=/opt/xterm-latest/share/pixmaps
cp debian/rules "$LOGS/track-b-rules.after"

DEB_CFLAGS_MAINT_APPEND="-O2 -march=core2 -mtune=core2" \
    dpkg-buildpackage -us -uc -b -j"$JOBS"
B_VERSION="$(dpkg-parsechangelog -S Version)"
B_DEB="$(find "$WORK" -maxdepth 2 -type f -name "xterm-latest_"$B_VERSION"_*.deb" -print -quit)"
[[ -n "$B_DEB" ]] || fail "Track B xterm-latest package missing"
cp "$B_DEB" "$OUT/"
printf 'TRACK B PACKAGE: %s\n' "$(basename "$B_DEB")"

A_DEB_OUT="$(find "$OUT" -maxdepth 1 -type f -name 'xterm_*.deb' -print -quit)"
B_DEB_OUT="$(find "$OUT" -maxdepth 1 -type f -name 'xterm-latest_*.deb' -print -quit)"
[[ -n "$A_DEB_OUT" && -n "$B_DEB_OUT" ]] || fail 'Expected both Debian packages in build/out'

dpkg-deb -f "$A_DEB_OUT" Package Version Architecture | tee "$LOGS/track-a-package-info.txt"
dpkg-deb -f "$B_DEB_OUT" Package Version Architecture | tee "$LOGS/track-b-package-info.txt"
dpkg-deb -c "$A_DEB_OUT" >"$LOGS/track-a-files.txt"
dpkg-deb -c "$B_DEB_OUT" >"$LOGS/track-b-files.txt"
awk '$1 !~ /^d/ {print $6}' "$LOGS/track-a-files.txt" | sort -u >"$LOGS/track-a-paths.txt"
awk '$1 !~ /^d/ {print $6}' "$LOGS/track-b-files.txt" | sort -u >"$LOGS/track-b-paths.txt"
comm -12 "$LOGS/track-a-paths.txt" "$LOGS/track-b-paths.txt" >"$LOGS/package-path-overlaps.txt"
if [[ -s "$LOGS/package-path-overlaps.txt" ]]; then
    cat "$LOGS/package-path-overlaps.txt"
    fail 'Packages contain overlapping file paths'
fi

grep -q './opt/xterm-latest/bin/xterm' "$LOGS/track-b-files.txt" || fail 'Track B executable is not under /opt/xterm-latest/bin'
grep -q '^Package: xterm$' "$LOGS/track-a-package-info.txt" || fail 'Track A package name is not xterm'
grep -q '^Package: xterm-latest$' "$LOGS/track-b-package-info.txt" || fail 'Track B package name is not xterm-latest'

mkdir -p "$WORK/test-a" "$WORK/test-b"
dpkg-deb -x "$A_DEB_OUT" "$WORK/test-a"
dpkg-deb -x "$B_DEB_OUT" "$WORK/test-b"
"$WORK/test-a/usr/bin/xterm" -version 2>&1 | tee "$LOGS/track-a-version.txt"
"$WORK/test-b/opt/xterm-latest/bin/xterm" -version 2>&1 | tee "$LOGS/track-b-version.txt"

for package in "$A_DEB_OUT" "$B_DEB_OUT"; do
    printf '\n===== lintian: %s =====\n' "$(basename "$package")"
    lintian "$package" 2>&1 | tee -a "$LOGS/lintian.txt" || true
done

printf '\nSUCCESS: built and verified both packages\n'
find "$OUT" -maxdepth 1 -type f -name '*.deb' -printf '%f %s bytes\n' | sort
