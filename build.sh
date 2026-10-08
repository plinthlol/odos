#!/bin/sh
# odos build: Wayland-only terminal. Fetches + builds everything.
# usage: ./build.sh [release]
set -e
cd "$(dirname "$0")"

GHOSTTY_REV="8f0dd3709050b1026f6324368805033197d8b4a5"
VT_A="third_party/ghostty/zig-out/lib/libghostty-vt.a"
RHUN="vendor/rhun"

# ---- rhun sources (our UI/PTY/font/Wayland base) ----
if [ ! -f "$RHUN/src/rhun.inc" ]; then
    echo "odos: fetching rhun sources..."
    git submodule update --init --depth 1 "$RHUN"
fi
test -f "$RHUN/src/rhun.inc" || { echo "odos: $RHUN/src/rhun.inc missing"; exit 1; }

# ---- Zig (system, >= 0.16; never fetched automatically) ----
ZIG=""
if command -v zig >/dev/null 2>&1; then
    zv=$(zig version)
    major=${zv%%.*}; rest=${zv#*.}; minor=${rest%%.*}
    if [ "$major" -gt 0 ] || [ "$minor" -ge 16 ] 2>/dev/null; then
        ZIG=zig
    fi
fi
if [ -z "$ZIG" ]; then
    echo "odos: Zig >= 0.16 required to build libghostty-vt (have: ${zv:-none})"
    echo "odos: install it yourself (pacman -S zig, or https://ziglang.org/download/)"
    exit 1
fi

# ---- ghostty freestanding VT static lib ----
if [ ! -f "$VT_A" ]; then
    if [ ! -d third_party/ghostty/.git ]; then
        echo "odos: cloning ghostty..."
        git clone --depth 1 https://github.com/ghostty-org/ghostty third_party/ghostty
    fi
    if [ "$(git -C third_party/ghostty rev-parse HEAD)" != "$GHOSTTY_REV" ]; then
        (git -C third_party/ghostty fetch --depth 1 origin "$GHOSTTY_REV" \
            && git -C third_party/ghostty checkout -q "$GHOSTTY_REV") \
        || echo "odos: warning: pinned ghostty $GHOSTTY_REV unavailable, using HEAD"
    fi
    echo "odos: building libghostty-vt (freestanding, ReleaseFast)..."
    (cd third_party/ghostty && "$ZIG" build -Demit-lib-vt \
        -Dtarget=x86_64-freestanding -Doptimize=ReleaseFast)
fi
test -f "$VT_A" || { echo "odos: $VT_A missing"; exit 1; }

# ---- odos objects ----
mkdir -p build/obj
ASFLAGS="--64 -I $RHUN/src -I build"
[ "$1" = release ] || ASFLAGS="$ASFLAGS -g"
objs=""
# shellcheck disable=SC2086
for s in $RHUN/src/start.s $RHUN/src/sys.s $RHUN/src/mem.s $RHUN/src/lib.s $RHUN/src/loop.s $RHUN/src/plat/wayland.s $RHUN/src/plat/xkb.s $RHUN/src/plat/keysyms.s $RHUN/src/gfx/canvas.s $RHUN/src/gfx/raster.s $RHUN/src/gfx/font.s $RHUN/src/proc.s $RHUN/src/app/term.s src/odos.s src/vt_math.s src/vt_alloc.s; do
    o=build/obj/$(echo "$s" | sed 's|/|_|g; s|\.s$|.o|')
    if [ ! -f "$o" ] || [ "$s" -nt "$o" ] || [ $RHUN/src/rhun.inc -nt "$o" ] || [ src/odos.s -nt "$o" ]; then
        as $ASFLAGS -o "$o" "$s"
    fi
    objs="$objs $o"
done
LDFLAGS="-static -nostdlib --no-dynamic-linker -z noexecstack"
[ "$1" = release ] && LDFLAGS="$LDFLAGS -s"
# shellcheck disable=SC2086
ld $LDFLAGS -o build/odos $objs "$VT_A"
echo "built build/odos"
