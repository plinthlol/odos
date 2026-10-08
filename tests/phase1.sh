#!/bin/sh
# headless phase-1 test: pty + echo + offscreen render, no compositor needed
set -e
cd "$(dirname "$0")/.."
RHUN="vendor/rhun"
mkdir -p build/obj
objs=""
# shellcheck disable=SC2086
for s in $RHUN/src/start.s $RHUN/src/sys.s $RHUN/src/mem.s $RHUN/src/lib.s $RHUN/src/loop.s $RHUN/src/plat/wayland.s $RHUN/src/plat/xkb.s $RHUN/src/plat/keysyms.s $RHUN/src/gfx/canvas.s $RHUN/src/gfx/raster.s $RHUN/src/gfx/font.s $RHUN/src/proc.s $RHUN/src/app/term.s; do
    o=build/obj/$(echo "$s" | sed 's|/|_|g; s|\.s$|.o|')
    if [ ! -f "$o" ] || [ "$s" -nt "$o" ] || [ $RHUN/src/rhun.inc -nt "$o" ]; then
        as --64 -I $RHUN/src -g -o "$o" "$s"
    fi
    objs="$objs $o"
done
as --64 -I $RHUN/src -g --defsym ODOS_TEST=1 -o build/obj/odos_test.o src/odos.s
as --64 -I $RHUN/src -g -o build/obj/pty_test.o tests/pty_test.s
objs="$objs build/obj/odos_test.o build/obj/pty_test.o"
# shellcheck disable=SC2086
ld -static -nostdlib --no-dynamic-linker -z noexecstack -o build/pty_test $objs
out=$(./build/pty_test 2>&1)
echo "$out" | tail -30
echo "$out" | grep -q "odos-phase1-ok" && echo "PTY ECHO OK" || { echo "PTY ECHO FAIL"; exit 1; }
echo "$out" | grep -q "cursor" && echo "DUMP OK" || { echo "DUMP FAIL"; exit 1; }
echo "ALL PHASE-1 HEADLESS TESTS PASS"
