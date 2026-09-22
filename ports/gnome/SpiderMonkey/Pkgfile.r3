# Maintainer: Brian Madonna <bmadonnaster@gmail.com>
# Depends on: icu rustc which llvm

name=SpiderMonkey
version=140.15.0esr
release=3
source=(https://archive.mozilla.org/pub/firefox/releases/$version/source/firefox-$version.source.tar.xz)

pkg_build () {
    cd "$SRC/firefox-${version%esr}"

    # Rust 1.98 added vendor-specific *-oe-linux-* targets.  ESR140's
    # rust target detector sees both x86_64-unknown-linux-gnu and
    # x86_64-oe-linux-gnu, while config.guess reports x86_64-pc-linux-gnu.
    # Normalize the pc vendor to Rust's generic unknown vendor.
    python3 - <<'PY'
from pathlib import Path

p = Path("build/moz.configure/rust.configure")
s = p.read_text()

old = '        narrowed = [c for c in candidates if c.target.vendor == host_or_target.vendor]'
new = '''        vendor = "unknown" if host_or_target.vendor == "pc" else host_or_target.vendor
        narrowed = [c for c in candidates if c.target.vendor == vendor]'''

count = s.count(old)
if count != 1:
    raise SystemExit(
        f"SpiderMonkey Rust 1.98 compatibility edit expected 1 match, found {count}"
    )

p.write_text(s.replace(old, new, 1))
PY

    mkdir -p obj
    cd obj

    ../js/src/configure --prefix=/usr           \
                        --disable-debug-symbols \
                        --disable-jemalloc      \
                        --enable-readline       \
                        --enable-rust-simd      \
                        --with-intl-api         \
                        --with-system-icu       \
                        --with-system-zlib || return 1

    make || return 1
    DESTDIR="$PKG" make install || return 1

    rm -vf "$PKG/usr/lib/libjs_static.ajs"
    sed -i '/@NSPR_CFLAGS@/d' "$PKG/usr/bin/js140-config"
    sed '$i#define XP_UNIX' -i "$PKG/usr/include/mozjs-140/js-config.h"
}
