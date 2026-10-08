#include <stdio.h>
#include <stddef.h>
#include <ghostty/vt.h>
#include <ghostty/vt/terminal.h>
#include <ghostty/vt/render.h>
#include <ghostty/vt/style.h>
#include <ghostty/vt/key/event.h>
#include <ghostty/vt/mouse/event.h>

#define SZ(t) printf("SIZE %s %zu\n", #t, sizeof(t))
#define OFF(t, f) printf("OFF %s %s %zu\n", #t, #f, offsetof(t, f))
#define E(v) printf("ENUM %s %d\n", #v, (int)(v))

int main(void) {
    SZ(GhosttyStyle); OFF(GhosttyStyle, size); OFF(GhosttyStyle, fg_color);
    OFF(GhosttyStyle, bg_color); OFF(GhosttyStyle, underline_color);
    OFF(GhosttyStyle, bold); OFF(GhosttyStyle, italic); OFF(GhosttyStyle, faint);
    OFF(GhosttyStyle, blink); OFF(GhosttyStyle, inverse); OFF(GhosttyStyle, invisible);
    OFF(GhosttyStyle, strikethrough); OFF(GhosttyStyle, overline); OFF(GhosttyStyle, underline);
    SZ(GhosttyStyleColor); OFF(GhosttyStyleColor, tag); OFF(GhosttyStyleColor, value);
    SZ(GhosttyColorRgb); OFF(GhosttyColorRgb, r); OFF(GhosttyColorRgb, g); OFF(GhosttyColorRgb, b);
    SZ(GhosttyString); OFF(GhosttyString, ptr); OFF(GhosttyString, len);
    SZ(GhosttyBuffer); OFF(GhosttyBuffer, ptr); OFF(GhosttyBuffer, cap); OFF(GhosttyBuffer, len);
    SZ(GhosttyAllocator); OFF(GhosttyAllocator, ctx); OFF(GhosttyAllocator, vtable);
    SZ(GhosttyAllocatorVtable);
    SZ(GhosttyTerminalScrollViewport);
    OFF(GhosttyTerminalScrollViewport, tag); OFF(GhosttyTerminalScrollViewport, value);
    E(GHOSTTY_KEY_ESCAPE); E(GHOSTTY_KEY_ENTER); E(GHOSTTY_KEY_TAB);
    E(GHOSTTY_KEY_BACKSPACE); E(GHOSTTY_KEY_INSERT); E(GHOSTTY_KEY_DELETE);
    E(GHOSTTY_KEY_ARROW_RIGHT); E(GHOSTTY_KEY_ARROW_LEFT); E(GHOSTTY_KEY_ARROW_DOWN);
    E(GHOSTTY_KEY_ARROW_UP); E(GHOSTTY_KEY_PAGE_DOWN); E(GHOSTTY_KEY_PAGE_UP);
    E(GHOSTTY_KEY_HOME); E(GHOSTTY_KEY_END); E(GHOSTTY_KEY_CAPS_LOCK);
    E(GHOSTTY_KEY_F1); E(GHOSTTY_KEY_F2); E(GHOSTTY_KEY_F3); E(GHOSTTY_KEY_F4);
    E(GHOSTTY_KEY_F5); E(GHOSTTY_KEY_F6); E(GHOSTTY_KEY_F7); E(GHOSTTY_KEY_F8);
    E(GHOSTTY_KEY_F9); E(GHOSTTY_KEY_F10); E(GHOSTTY_KEY_F11); E(GHOSTTY_KEY_F12);
    E(GHOSTTY_KEY_NUMPAD_0); E(GHOSTTY_KEY_NUMPAD_1); E(GHOSTTY_KEY_NUMPAD_2);
    E(GHOSTTY_KEY_NUMPAD_3); E(GHOSTTY_KEY_NUMPAD_4); E(GHOSTTY_KEY_NUMPAD_5);
    E(GHOSTTY_KEY_NUMPAD_6); E(GHOSTTY_KEY_NUMPAD_7); E(GHOSTTY_KEY_NUMPAD_8);
    E(GHOSTTY_KEY_NUMPAD_9); E(GHOSTTY_KEY_NUMPAD_DECIMAL); E(GHOSTTY_KEY_NUMPAD_ENTER);
    E(GHOSTTY_KEY_NUM_LOCK); E(GHOSTTY_KEY_PRINT_SCREEN); E(GHOSTTY_KEY_PAUSE);
    E(GHOSTTY_KEY_CONTEXT_MENU); E(GHOSTTY_KEY_UNIDENTIFIED);
    E(GHOSTTY_TERMINAL_CURSOR_STYLE_BAR); E(GHOSTTY_TERMINAL_CURSOR_STYLE_BLOCK);
    E(GHOSTTY_TERMINAL_CURSOR_STYLE_UNDERLINE);
    return 0;
}
