# odos phase 1: Wayland terminal — pty + term.s VT + font grid
#   main: theme, font, wl_connect, spawn /bin/sh, loop
#   render: term.s cells -> gfx_fill + face_glyph/gfx_mask
# Reg discipline: rbx=term, r12=row across calls (callee-saved);
#   col lives in [rsp+48] because face_glyph's slow path uses r14.
.include "rhun.inc"

.equ O_COLS0, 80
.equ O_ROWS0, 24
.equ O_SB, 1000
.equ O_PX, 16
.equ RBUF_SZ, 65536

.bss
.p2align 3
.globl o_term, o_cols, o_rows, o_fd
o_term: .quad 0
o_env: .quad 0
o_face: .zero FACE_SIZE
o_font: .quad 0
o_wbuf: .zero SB_SIZE
o_clip_sb: .zero SB_SIZE
o_cfgbuf: .quad 0
rbuf: .zero 65536
# g_key_base comes from term.s
.globl g_theme
g_theme: .zero 4 * T_COUNT
o_fd: .long 0
o_pid: .long 0
o_cols: .long 0
o_rows: .long 0
o_ok: .long 0                  # font ready
o_mx: .long 0                  # last pointer, px
o_my: .long 0
o_btn: .long 0                 # left held
o_sel: .long 0                 # selection live
o_ax: .long 0                  # anchor, term coords
o_ay: .long 0
o_bx: .long 0                  # current end, term coords
o_by: .long 0
o_srem: .quad 0                # wheel remainder, px
o_cfgpath: .zero 4096

.data
.p2align 2
.globl cfg_decorations
cfg_decorations: .long 0
.globl o_px, o_sbnum, o_shell
o_px: .long 16
o_sbnum: .long 1000
o_shell: .quad 0

.text

# entry called by start.s _start (after sys_init)
.ifndef ODOS_TEST
FN main
    PROLOGUE 16
    call init_theme
    call config_load
    call font_init
    test eax, eax
    jnz 1f
    lea rdi, [rip + .Lno_font]
    call die
1:  mov dword ptr [rip + o_cols], O_COLS0
    mov dword ptr [rip + o_rows], O_ROWS0
    call wl_connect
    test eax, eax
    jnz 2f
    lea rdi, [rip + .Lno_wl]
    call die
2:  call spawn_shell
    test eax, eax
    jnz 3f
    lea rdi, [rip + .Lno_shell]
    call die
3:  lea rdi, [rip + .Ltitle]
    call wl_open_window
    mov dword ptr [rip + g_dirty], 1
    call loop_run
    xor eax, eax
    EPILOGUE
.endif

.section .rodata
.Ltitle: .asciz "odos"
.Lno_wl: .asciz "odos: no Wayland display found"
.Lno_font: .asciz "odos: no monospace font found (tried ../assets/fonts and assets/fonts)"
.Lno_shell: .asciz "odos: cannot start a shell"
.Lshell_env: .asciz "SHELL"
.Lsh: .asciz "/bin/sh"
.Lfont1: .asciz "../assets/fonts/IosevkaFixed-Regular.ttf"
.Lfont2: .asciz "assets/fonts/IosevkaFixed-Regular.ttf"
.Lenv_term: .asciz "TERM=xterm-256color"
.Lenv_color: .asciz "COLORTERM=truecolor"
.Lenv_prog: .asciz "TERM_PROGRAM=odos"
.Lcfg_env: .asciz "ODOS_CONF"
.Lcfg_home: .asciz "HOME"
.Lcfg_suffix: .asciz "/.config/odos/config"
.p2align 3
odos_env_extras: .quad .Lenv_term, .Lenv_color, .Lenv_prog, 0
.text

# config_load(): ODOS_CONF or $HOME/.config/odos/config; px/scrollback/shell/bg/fg
FN config_load
    PROLOGUE 16
    lea rdi, [rip + .Lcfg_env]
    call getenv
    test rax, rax
    jz 1f
    cmp byte ptr [rax], 0
    jne 2f
1:  lea rdi, [rip + .Lcfg_home]
    call getenv
    test rax, rax
    jz 9f
    lea rdi, [rip + o_cfgpath]
    mov rsi, rax
    call cstr_copy
    mov rdi, rax
    lea rsi, [rip + .Lcfg_suffix]
    call cstr_copy
    lea rdi, [rip + o_cfgpath]
2:  mov rbx, rdi
    call file_read_all
    test rax, rax
    jz 9f
    mov [rip + o_cfgbuf], rax
    mov r12, rax                  # p
    add rdx, rax
    mov r13, rdx                  # end
3:  cmp r12, r13
    jae 9f
    mov r14, r12                  # line start
4:  cmp r12, r13
    jae 5f
    cmp byte ptr [r12], 10
    je 5f
    inc r12
    jmp 4b
5:  mov r15, r12                  # line end
    cmp r12, r13
    jae 6f
    inc r12                       # past \n
6:  # trim leading blanks
    cmp r14, r15
    jae 3b
    mov al, [r14]
    cmp al, ' '
    je 7f
    cmp al, 9
    je 7f
    cmp al, '#'
    je 3b
    jmp 8f
7:  inc r14
    jmp 6b
8:  # find '='
    mov rax, r14
9:  cmp rax, r15
    jae 3b
    cmp byte ptr [rax], '='
    je 10f
    inc rax
    jmp 9b
10: mov rbx, rax                  # eq
    # trim key end
    cmp rbx, r14
    je 3b                         # empty key
11: cmp byte ptr [rbx - 1], ' '
    jne 12f
    dec rbx
    cmp rbx, r14
    ja 11b
    jmp 3b
12: mov rsi, rbx
    sub rsi, r14                  # key len
    lea rax, [rbx + 1]            # val start
13: cmp rax, r15
    jae 14f
    mov cl, [rax]
    cmp cl, ' '
    je 15f
    cmp cl, 9
    je 15f
    jmp 14f
15: inc rax
    jmp 13b
14: mov rdi, rax                  # val
    mov rcx, r15
    sub rcx, rax                  # val len
16: test rcx, rcx
    jz 3b
    dec rcx
    mov dl, [rax + rcx]
    cmp dl, ' '
    je 16b
    cmp dl, 9
    je 16b
    inc rcx
    jmp 17f
17: mov rdx, rcx                  # val len
    mov rbx, rax                  # val ptr
    # match the key
    cmp rsi, 2
    jne 18f
    cmp byte ptr [r14], 'p'
    jne 19f
    cmp byte ptr [r14 + 1], 'x'
    jne 3b
    mov rdi, rbx
    mov rsi, rdx
    call parse_u64
    cmp eax, 8
    jb 3b
    cmp eax, 64
    ja 3b
    mov [rip + o_px], eax
    jmp 3b
19: cmp byte ptr [r14], 'b'
    jne 20f
    cmp byte ptr [r14 + 1], 'g'
    jne 3b
    mov rdi, rbx
    mov rsi, rdx
    cmp rdx, 6
    jne 3b
    call parse_hex
    or eax, 0xff000000
    mov [rip + g_theme + 4*T_BG], eax
    jmp 3b
20: cmp byte ptr [r14], 'f'
    jne 3b
    cmp byte ptr [r14 + 1], 'g'
    jne 3b
    mov rdi, rbx
    mov rsi, rdx
    cmp rdx, 6
    jne 3b
    call parse_hex
    or eax, 0xff000000
    mov [rip + g_theme + 4*T_FG], eax
    jmp 3b
18: cmp rsi, 5
    jne 21f
    mov rdi, r14
    lea rsi, [rip + .Lk_shell]
    mov rdx, 5
    call memeq
    test eax, eax
    jz 3b
    mov rdi, rbx
    mov rsi, rdx
    call mem_dup
    mov [rip + o_shell], rax
    jmp 3b
21: cmp rsi, 10
    jne 3b
    mov rdi, r14
    lea rsi, [rip + .Lk_sb]
    mov rdx, 10
    call memeq
    test eax, eax
    jz 3b
    mov rdi, rbx
    mov rsi, rdx
    call parse_u64
    cmp eax, 100000
    ja 3b
    mov [rip + o_sbnum], eax
    jmp 3b
9:  EPILOGUE

.section .rodata
.Lk_shell: .ascii "shell"
.Lk_sb: .ascii "scrollback"
.text

# init_theme(): minimal dark palette for the VT grid
FN init_theme
    mov dword ptr [rip + g_theme + 4*T_BG], 0xff16181d
    mov dword ptr [rip + g_theme + 4*T_FG], 0xffe8e4d8
    mov dword ptr [rip + g_theme + 4*T_CURSOR], 0xffe8e4d8
    mov dword ptr [rip + g_theme + 4*T_SELECTION], 0xff3d4455
    mov dword ptr [rip + g_theme + 4*(T_TERM+0)], 0xff000000
    mov dword ptr [rip + g_theme + 4*(T_TERM+1)], 0xffcd0000
    mov dword ptr [rip + g_theme + 4*(T_TERM+2)], 0xff00cd00
    mov dword ptr [rip + g_theme + 4*(T_TERM+3)], 0xffcdcd00
    mov dword ptr [rip + g_theme + 4*(T_TERM+4)], 0xff0000cd
    mov dword ptr [rip + g_theme + 4*(T_TERM+5)], 0xffcd00cd
    mov dword ptr [rip + g_theme + 4*(T_TERM+6)], 0xff00cdcd
    mov dword ptr [rip + g_theme + 4*(T_TERM+7)], 0xffe5e5e5
    mov dword ptr [rip + g_theme + 4*(T_TERM+8)], 0xff7f7f7f
    mov dword ptr [rip + g_theme + 4*(T_TERM+9)], 0xffff0000
    mov dword ptr [rip + g_theme + 4*(T_TERM+10)], 0xff00ff00
    mov dword ptr [rip + g_theme + 4*(T_TERM+11)], 0xffffff00
    mov dword ptr [rip + g_theme + 4*(T_TERM+12)], 0xff5c5cff
    mov dword ptr [rip + g_theme + 4*(T_TERM+13)], 0xffff00ff
    mov dword ptr [rip + g_theme + 4*(T_TERM+14)], 0xff00ffff
    mov dword ptr [rip + g_theme + 4*(T_TERM+15)], 0xffffffff
    ret

# font_init() -> 1 with o_face ready, 0 without a font file
FN font_init
    PROLOGUE 16
    lea rdi, [rip + .Lfont1]
    call file_read_all
    test rax, rax
    jnz 1f
    lea rdi, [rip + .Lfont2]
    call file_read_all
    test rax, rax
    jz 9f
1:  mov r12, rax
    mov r13, rdx
    mov rdi, rax
    mov rsi, rdx
    call font_load
    test rax, rax
    jz 9f
    mov [rip + o_font], rax
    lea rdi, [rip + o_face]
    mov rsi, [rip + o_font]
    mov edx, [rip + o_px]
    call face_init
    mov eax, [rip + o_face + FACE_cellw]
    test eax, eax
    jz 9f
    mov eax, [rip + o_face + FACE_lineh]
    test eax, eax
    jz 9f
    mov dword ptr [rip + o_ok], 1
    mov eax, 1
    EPILOGUE
9:  xor eax, eax
    EPILOGUE

# spawn_shell() -> 1 with o_term/o_fd live, 0 on failure
FN spawn_shell
    PROLOGUE 64
    mov rax, [rip + o_shell]
    test rax, rax
    jnz 22f
    lea rdi, [rip + .Lshell_env]
    call getenv
    mov rdi, rax
    test rax, rax
    jz 21f
    cmp byte ptr [rax], 0
    jne 2f
21: lea rdi, [rip + .Lsh]
2:  call proc_which
    test rax, rax
    jz 9f
    jmp 23f
22: mov rdi, rax
    call proc_which
    test rax, rax
    jz 9f
23: mov r12, rax
    mov [rsp], rax
    mov qword ptr [rsp + 8], 0
    cmp qword ptr [rip + o_env], 0
    jne 1f
    lea rdi, [rip + odos_env_extras]
    call env_make
    mov [rip + o_env], rax
1:  mov edi, [rip + o_cols]
    mov esi, [rip + o_rows]
    call pty_open
    test eax, eax
    js 8f
    mov r13d, eax
    mov r14d, edx
    lea rdi, [rsp]
    mov rsi, [rip + o_env]
    xor edx, edx
    mov ecx, r14d
    mov r8d, r14d
    mov r9d, r14d
    push 1
    push 1
    call proc_spawn
    add rsp, 16
    mov r15, rax
    mov edi, r14d
    SYS SYS_close
    test r15, r15
    jle 7f
    mov [rip + o_pid], r15d
    mov [rip + o_fd], r13d
    mov edi, [rip + o_cols]
    mov esi, [rip + o_rows]
    mov edx, [rip + o_sbnum]
    call term_new
    mov [rip + o_term], rax
    lea rdi, [rip + o_wbuf]
    call sb_clear
    mov edi, r13d
    mov esi, POLLIN
    lea rdx, [rip + on_pty]
    xor ecx, ecx
    call watch_add
    mov rdi, r12
    call mem_free
    mov dword ptr [rip + g_dirty], 1
    mov eax, 1
    EPILOGUE
7:  mov edi, r13d
    SYS SYS_close
8:  mov rdi, r12
    call mem_free
9:  xor eax, eax
    EPILOGUE

# on_pty(fd, revents, ctx): shell output -> term_feed; replies -> pty
FN on_pty
    PROLOGUE 0
    mov ebx, edi
    mov r12d, esi
    test r12d, POLLOUT
    jz 1f
    call o_flush
1:  mov r13d, 16
2:  mov edi, ebx
    lea rsi, [rip + rbuf]
    mov edx, RBUF_SZ
    SYS SYS_read
    cmp rax, -EINTR
    je 2b
    cmp rax, -EAGAIN
    je 3f
    test rax, rax
    jle 4f
    mov rdi, [rip + o_term]
    lea rsi, [rip + rbuf]
    mov rdx, rax
    call term_feed
    dec r13d
    jnz 2b
3:  call o_replies
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE
# the shell went away: reap, drop the session, start a new one
4:  mov edi, ebx
    call watch_remove
    mov edi, ebx
    SYS SYS_close
    mov edi, [rip + o_pid]
    mov esi, 1
    call proc_wait
    mov rdi, [rip + o_term]
    test rdi, rdi
    jz 5f
    call term_free
    mov qword ptr [rip + o_term], 0
5:  call spawn_shell
    test eax, eax
    jnz 6f
    mov dword ptr [rip + g_quit], 1
6:  EPILOGUE

# o_replies(): emulator answers in TM_out -> the program
FN o_replies
    PROLOGUE 0
    mov rax, [rip + o_term]
    mov rdx, [rax + TM_out + SB_len]
    test rdx, rdx
    jz 1f
    mov rsi, [rax + TM_out + SB_ptr]
    call o_send
    mov rax, [rip + o_term]
    lea rdi, [rax + TM_out]
    call sb_clear
1:  EPILOGUE

# o_send(ptr, len): bytes for the program, buffering on EAGAIN
FN o_send
    PROLOGUE 0
    mov r12, rsi
    mov r13, rdx
    cmp qword ptr [rip + o_wbuf + SB_len], 0
    jne 5f
1:  test r13, r13
    jz 9f
    mov edi, [rip + o_fd]
    mov rsi, r12
    mov rdx, r13
    SYS SYS_write
    cmp rax, -EINTR
    je 1b
    cmp rax, -EAGAIN
    je 4f
    test rax, rax
    js 9f
    add r12, rax
    sub r13, rax
    jmp 1b
4:  mov edi, [rip + o_fd]
    mov esi, POLLIN | POLLOUT
    call watch_set_events
5:  lea rdi, [rip + o_wbuf]
    mov rsi, r12
    mov rdx, r13
    call sb_push
9:  EPILOGUE

# o_flush(): POLLOUT drained the pty, write what waited
FN o_flush
    PROLOGUE 0
    mov ebx, [rip + o_fd]
1:  mov r13, [rip + o_wbuf + SB_len]
    test r13, r13
    jz 3f
    mov edi, ebx
    mov rsi, [rip + o_wbuf + SB_ptr]
    mov rdx, r13
    SYS SYS_write
    cmp rax, -EINTR
    je 1b
    test rax, rax
    jle 9f
    mov r12, rax
    mov rdi, [rip + o_wbuf + SB_ptr]
    lea rsi, [rdi + r12]
    mov rdx, r13
    sub rdx, r12
    call memmove
    sub qword ptr [rip + o_wbuf + SB_len], r12
    jmp 1b
3:  mov edi, ebx
    mov esi, POLLIN
    call watch_set_events
9:  EPILOGUE

# ---- app hooks required by loop.s / wayland.s ----

FN app_timeout
    mov eax, -1
    ret

FN app_tick
    ret

FN app_on_close
    mov dword ptr [rip + g_quit], 1
    ret

FN app_on_resize
    mov dword ptr [rip + g_dirty], 1
    ret

FN app_on_motion
    mov [rip + o_mx], edi
    mov [rip + o_my], esi
    cmp dword ptr [rip + o_btn], 0
    je 2f
    # drag the selection end
    call o_grid_xy
    mov rax, [rip + o_term]
    test rax, rax
    jz 2f
    sub edx, [rax + TM_view]
    mov [rip + o_bx], ecx
    mov [rip + o_by], edx
    mov dword ptr [rip + g_dirty], 1
    ret
2:  # motion reports for app mouse mode (1002/1003)
    mov rax, [rip + o_term]
    test rax, rax
    jz 9f
    cmp dword ptr [rax + TM_mouse], 0
    je 9f
    call o_grid_xy
    mov rdi, [rip + o_term]
    mov esi, 3
    mov edx, 2
    call term_mouse
    test eax, eax
    jz 9f
    mov rax, [rip + o_term]
    mov rdx, [rax + TM_out + SB_len]
    test rdx, rdx
    jz 9f
    mov rsi, [rax + TM_out + SB_ptr]
    call o_send
    mov rax, [rip + o_term]
    lea rdi, [rax + TM_out]
    call sb_clear
9:  ret

# o_grid_xy(x, y) -> ecx col, edx row (clamped to >= 0)
o_grid_xy:
    mov ecx, [rip + o_face + FACE_cellw]
    test ecx, ecx
    jz 1f
    mov eax, edi
    xor edx, edx
    div ecx
    mov ecx, eax
    mov eax, esi
    xor edx, edx
    div dword ptr [rip + o_face + FACE_lineh]
    mov edx, eax
    ret
1:  xor ecx, ecx
    xor edx, edx
    ret

# app_on_button(btn, pressed, mods); pressed: 1 down, 0 up
FN app_on_button
    PROLOGUE 0
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    mov edi, [rip + o_mx]
    mov esi, [rip + o_my]
    call o_grid_xy
    mov r15d, ecx
    mov ebx, edx
    mov rax, [rip + o_term]
    test rax, rax
    jz 9f
    # programs with mouse mode get the event first
    cmp r12d, BTN_LEFT
    je 1f
    cmp r12d, BTN_MIDDLE
    je 2f
    cmp r12d, BTN_RIGHT
    jne 9f
    mov r12d, 2
    jmp 3f
1:  xor r12d, r12d
    jmp 3f
2:  mov r12d, 1
3:  mov rdi, [rip + o_term]
    mov esi, r12d
    test r13d, r13d
    jz 4f
    xor edx, edx
    jmp 5f
4:  mov edx, 1
5:  mov ecx, r15d
    mov r8d, ebx
    mov r9d, r14d
    call term_mouse
    test eax, eax
    jz 6f
    mov rax, [rip + o_term]
    mov rdx, [rax + TM_out + SB_len]
    test rdx, rdx
    jz 8f
    mov rsi, [rax + TM_out + SB_ptr]
    call o_send
    mov rax, [rip + o_term]
    lea rdi, [rax + TM_out]
    call sb_clear
8:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE
6:  # local selection with the left button
    cmp r12d, 0
    jne 9f
    mov rax, [rip + o_term]
    test r13d, r13d
    jz 7f
    sub ebx, [rax + TM_view]
    mov [rip + o_ax], r15d
    mov [rip + o_ay], ebx
    mov [rip + o_bx], r15d
    mov [rip + o_by], ebx
    mov dword ptr [rip + o_btn], 1
    mov dword ptr [rip + o_sel], 1
    jmp 8b
7:  mov dword ptr [rip + o_btn], 0
    cmp dword ptr [rip + o_sel], 0
    je 8f
    call o_copy_sel
    jmp 8b
9:  EPILOGUE

FN app_on_pointer_leave
    ret

# app_on_scroll(dx, dy, mods): wheel to the program, else the scrollback
FN app_on_scroll
    PROLOGUE 0
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    mov rax, [rip + o_term]
    test rax, rax
    jz 9f
    cmp dword ptr [rax + TM_mouse], 0
    je 2f
    mov edi, [rip + o_mx]
    mov esi, [rip + o_my]
    call o_grid_xy
    mov r15d, ecx
    mov ebx, edx
    cmp r13d, 0
    jge 1f
    mov r12d, 64
    jmp 3f
1:  mov r12d, 65
3:  mov rdi, [rip + o_term]
    mov esi, r12d
    xor edx, edx
    mov ecx, r15d
    mov r8d, ebx
    mov r9d, r14d
    call term_mouse
    test eax, eax
    jz 2f
    mov rax, [rip + o_term]
    mov rdx, [rax + TM_out + SB_len]
    test rdx, rdx
    jz 4f
    mov rsi, [rax + TM_out + SB_ptr]
    call o_send
    mov rax, [rip + o_term]
    lea rdi, [rax + TM_out]
    call sb_clear
4:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE
2:  # local pager: accumulate sub-row deltas, 60px per row
    mov rax, [rip + o_srem]
    add rax, r13
    mov [rip + o_srem], rax
    cqo
    mov ecx, 60
    idiv rcx
    test rax, rax
    jz 9f
    mov rcx, rax
    imul rax, rcx, 60
    sub [rip + o_srem], rax
    neg ecx
    mov edi, ecx
    call view_scroll
9:  EPILOGUE

# view_scroll(delta rows): +back, -forward, clamped to the ring
FN view_scroll
    mov rax, [rip + o_term]
    test rax, rax
    jz 9f
    mov ecx, [rax + TM_view]
    add ecx, edi
    jns 1f
    xor ecx, ecx
1:  cmp ecx, [rax + TM_sblen]
    jle 2f
    mov ecx, [rax + TM_sblen]
2:  mov [rax + TM_view], ecx
    mov dword ptr [rip + g_dirty], 1
9:  ret

FN app_on_focus
    mov dword ptr [rip + g_dirty], 1
    ret

# app_on_paste(ptr, len): clipboard text into the program
FN app_on_paste
    PROLOGUE 0
    mov rax, [rip + o_term]
    test rax, rax
    jz 9f
    mov rdi, rax
    call term_paste
    mov rax, [rip + o_term]
    mov rdx, [rax + TM_out + SB_len]
    test rdx, rdx
    jz 9f
    mov rsi, [rax + TM_out + SB_ptr]
    call o_send
    mov rax, [rip + o_term]
    lea rdi, [rax + TM_out]
    call sb_clear
    mov dword ptr [rip + g_dirty], 1
9:  EPILOGUE

# app_on_key(keysym, unicode, mods)
FN app_on_key
    PROLOGUE 0
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    # Shift+PageUp/PageDown: the scrollback pager
    test r14d, MOD_SHIFT
    jz 1f
    cmp r12d, KEY_PAGEUP
    jne 2f
    mov edi, [rip + o_rows]
    call view_scroll
    EPILOGUE
2:  cmp r12d, KEY_PAGEDOWN
    jne 1f
    mov edi, [rip + o_rows]
    neg edi
    call view_scroll
    EPILOGUE
1:  # Ctrl+Shift+C/V: copy/paste
    mov eax, r14d
    and eax, MOD_CTRL | MOD_SHIFT
    cmp eax, MOD_CTRL | MOD_SHIFT
    jne 3f
    cmp r12d, 'C'
    je 4f
    cmp r12d, 'c'
    je 4f
    cmp r12d, 'V'
    je 5f
    cmp r12d, 'v'
    jne 3f
5:  cmp qword ptr [rip + g_plat + P_clip_get], 0
    je 6f
    PCALL P_clip_get
6:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE
4:  call o_copy_sel
    mov dword ptr [rip + g_dirty], 1
    EPILOGUE
3:  mov rdi, [rip + o_term]
    test rdi, rdi
    jz 7f
    mov esi, r12d
    mov edx, r13d
    mov ecx, r14d
    call term_key
    test eax, eax
    jz 7f
    mov rax, [rip + o_term]
    mov rdx, [rax + TM_out + SB_len]
    test rdx, rdx
    jz 8f
    mov rsi, [rax + TM_out + SB_ptr]
    call o_send
8:  mov rax, [rip + o_term]
    lea rdi, [rax + TM_out]
    call sb_clear
7:  mov dword ptr [rip + g_dirty], 1
    EPILOGUE

# o_copy_sel(): the live selection -> the Wayland clipboard
FN o_copy_sel
    PROLOGUE 0
    cmp dword ptr [rip + o_sel], 0
    je 9f
    mov rax, [rip + o_term]
    test rax, rax
    jz 9f
    # order the ends row-major
    mov ecx, [rip + o_ay]
    mov edx, [rip + o_ax]
    mov r8d, [rip + o_by]
    mov r9d, [rip + o_bx]
    cmp ecx, r8d
    jg 1f
    jl 2f
    cmp edx, r9d
    jle 2f
1:  xchg ecx, r8d
    xchg edx, r9d
2:  lea rdi, [rip + o_clip_sb]
    call sb_clear
    mov rdi, [rip + o_term]
    lea rsi, [rip + o_clip_sb]
    call term_text
    cmp qword ptr [rip + o_clip_sb + SB_len], 0
    je 9f
    cmp qword ptr [rip + g_plat + P_clip_set], 0
    je 9f
    mov rdi, [rip + o_clip_sb + SB_ptr]
    mov rsi, [rip + o_clip_sb + SB_len]
    PCALL P_clip_set
9:  EPILOGUE

# o_selected(trow, col) -> 1 inside the live selection (leaf: r8/r12-r15 kept)
FN o_selected
    xor eax, eax
    cmp dword ptr [rip + o_sel], 0
    je 9f
    mov ecx, [rip + o_ay]
    mov edx, [rip + o_ax]
    mov r10d, [rip + o_by]
    mov r11d, [rip + o_bx]
    cmp ecx, r10d
    jg 1f
    jl 2f
    cmp edx, r11d
    jle 2f
1:  xchg ecx, r10d
    xchg edx, r11d
2:  cmp edi, ecx
    jl 9f
    cmp edi, r10d
    jg 9f
    cmp edi, ecx
    jne 3f
    cmp esi, edx
    jl 9f
3:  cmp edi, r10d
    jne 4f
    cmp esi, r11d
    jg 9f
4:  mov eax, 1
9:  ret

# Frame layout: [rsp+0]=W [rsp+4]=H [rsp+8]=tcw [rsp+12]=tlh [rsp+16]=asc
#   [rsp+20]=cols [rsp+24]=rows [rsp+28]=y [rsp+32]=cap [rsp+36]=x
#   [rsp+40]=fg [rsp+44]=cursor-fg [rsp+48]=col
FN app_render
    PROLOGUE 80
    mov eax, [rip + g_cv + CV_w]
    mov [rsp], eax
    mov ebx, [rip + g_cv + CV_h]
    mov [rsp + 4], ebx
    xor edi, edi
    xor esi, esi
    mov edx, eax
    mov ecx, ebx
    mov r8d, [rip + g_theme + 4*T_BG]
    call gfx_fill
    mov rbx, [rip + o_term]
    test rbx, rbx
    jz .Lr_done
    cmp dword ptr [rip + o_ok], 0
    je .Lr_done
    mov eax, [rip + o_face + FACE_cellw]
    test eax, eax
    jle .Lr_done
    mov [rsp + 8], eax
    mov eax, [rip + o_face + FACE_lineh]
    test eax, eax
    jle .Lr_done
    mov [rsp + 12], eax
    mov eax, [rip + o_face + FACE_ascent]
    mov [rsp + 16], eax
    mov eax, [rsp]
    xor edx, edx
    div dword ptr [rsp + 8]
    cmp eax, 2
    jge 1f
    mov eax, 2
1:  mov [rsp + 20], eax
    mov eax, [rsp + 4]
    xor edx, edx
    div dword ptr [rsp + 12]
    test eax, eax
    jnz 2f
    mov eax, 1
2:  mov [rsp + 24], eax
    mov ecx, [rip + o_rows]
    cmp eax, ecx
    jne 3f
    mov eax, [rsp + 20]
    cmp eax, [rip + o_cols]
    je 4f
3:  mov eax, [rsp + 20]
    mov [rip + o_cols], eax
    mov eax, [rsp + 24]
    mov [rip + o_rows], eax
    mov rdi, rbx
    mov esi, [rip + o_cols]
    mov edx, [rip + o_rows]
    call term_resize
    mov edi, [rip + o_fd]
    mov esi, [rip + o_cols]
    mov edx, [rip + o_rows]
    mov ecx, [rsp]
    mov r8d, [rsp + 4]
    call pty_resize
4:  mov eax, [rbx + TM_view]
    mov [rsp + 52], eax           # view
    xor r12d, r12d
.Lr_row:
    cmp r12d, [rsp + 24]
    jae .Lr_cursor
    mov eax, r12d
    imul eax, [rsp + 12]
    mov [rsp + 28], eax
    mov eax, r12d
    sub eax, [rsp + 52]
    mov [rsp + 56], eax           # term row
    mov rdi, rbx
    mov esi, eax
    call term_row
    test rax, rax
    jz .Lr_next
    mov r13, rax
    mov eax, [r13 + LN_cap]
    mov [rsp + 32], eax
    mov dword ptr [rsp + 48], 0
.Lr_col:
    mov r14d, [rsp + 48]
    cmp r14d, [rsp + 20]
    jae .Lr_next
    mov eax, r14d
    imul eax, [rsp + 8]
    mov [rsp + 36], eax
    cmp r14d, [rsp + 32]
    jae .Lr_col_next
    lea r15, [r13 + LN_HDR]
    imul eax, r14d, CELL_SIZE
    add r15, rax
    mov rdi, r15
    call odos_cell_colors
    mov [rsp + 40], eax
    mov r8d, edx
    mov rdi, [rsp + 56]
    mov esi, [rsp + 48]
    call o_selected
    test eax, eax
    jz 1f
    mov r8d, [rip + g_theme + 4*T_SELECTION]
1:  mov edi, [rsp + 36]
    mov esi, [rsp + 28]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    call gfx_fill
    mov r8d, [r15]
    test r8d, A_HIDDEN | A_WIDE2
    jnz .Lr_col_next
    test r8d, A_UNDER | A_STRIKE
    jz 5f
    mov r9d, [rsp + 40]
    test r8d, A_UNDER
    jz 6f
    mov edi, [rsp + 36]
    mov esi, [rsp + 28]
    add esi, [rsp + 12]
    sub esi, 4
    mov edx, [rsp + 8]
    mov ecx, 2
    mov r8d, r9d
    call gfx_fill
6:  test r8d, A_STRIKE
    jz 5f
    mov edi, [rsp + 36]
    mov esi, [rsp + 28]
    mov eax, [rsp + 12]
    shr eax, 1
    add esi, eax
    mov edx, [rsp + 8]
    mov ecx, 2
    mov r8d, r9d
    call gfx_fill
5:  mov r8d, [r15]
    and r8d, CP_MASK
    cmp r8d, ' '
    jbe .Lr_col_next
    lea rdi, [rip + o_face]
    mov esi, r8d
    call face_glyph
    test rax, rax
    jz .Lr_col_next
    mov r10, [rax + GL_bits]
    test r10, r10
    jz .Lr_col_next
    movzx ecx, word ptr [rax + GL_w]
    movzx r8d, word ptr [rax + GL_h]
    movsx edi, word ptr [rax + GL_left]
    add edi, [rsp + 36]
    mov esi, [rsp + 28]
    add esi, [rsp + 16]
    movsx r9d, word ptr [rax + GL_top]
    sub esi, r9d
    mov rdx, r10
    mov r9d, [rsp + 40]
    call gfx_mask
    mov r8d, [r15]
    test r8d, A_BOLD
    jz .Lr_col_next
    mov esi, [r15]
    and esi, CP_MASK
    lea rdi, [rip + o_face]
    call face_glyph
    test rax, rax
    jz .Lr_col_next
    mov r10, [rax + GL_bits]
    test r10, r10
    jz .Lr_col_next
    movzx ecx, word ptr [rax + GL_w]
    movzx r8d, word ptr [rax + GL_h]
    movsx edi, word ptr [rax + GL_left]
    add edi, [rsp + 36]
    inc edi
    mov esi, [rsp + 28]
    add esi, [rsp + 16]
    movsx r9d, word ptr [rax + GL_top]
    sub esi, r9d
    mov rdx, r10
    mov r9d, [rsp + 40]
    call gfx_mask
.Lr_col_next:
    inc dword ptr [rsp + 48]
    jmp .Lr_col
.Lr_next:
    inc r12d
    jmp .Lr_row
.Lr_cursor:
    mov eax, [rbx + TM_modes]
    test eax, TMM_HIDE
    jnz .Lr_done
    cmp dword ptr [rbx + TM_view], 0
    jne .Lr_done
    mov r12d, [rbx + TM_cx]
    cmp r12d, [rsp + 20]
    jae .Lr_done
    mov r13d, [rbx + TM_cy]
    cmp r13d, [rsp + 24]
    jae .Lr_done
    mov eax, r12d
    imul eax, [rsp + 8]
    mov [rsp + 36], eax
    mov eax, r13d
    imul eax, [rsp + 12]
    mov [rsp + 28], eax
    mov edi, [rsp + 36]
    mov esi, [rsp + 28]
    mov edx, [rsp + 8]
    mov ecx, [rsp + 12]
    mov r8d, [rip + g_theme + 4*T_CURSOR]
    call gfx_fill
    mov rdi, rbx
    mov esi, r13d
    call term_row
    test rax, rax
    jz .Lr_done
    mov r13, rax
    cmp r12d, [r13 + LN_cap]
    jae .Lr_done
    imul eax, r12d, CELL_SIZE
    lea r15, [r13 + LN_HDR]
    add r15, rax
    mov r8d, [r15]
    test r8d, A_HIDDEN | A_WIDE2
    jnz .Lr_done
    and r8d, CP_MASK
    cmp r8d, ' '
    jbe .Lr_done
    mov rdi, r15
    call odos_cell_colors
    mov [rsp + 44], edx
    mov esi, [r15]
    and esi, CP_MASK
    lea rdi, [rip + o_face]
    call face_glyph
    test rax, rax
    jz .Lr_done
    mov r10, [rax + GL_bits]
    test r10, r10
    jz .Lr_done
    movzx ecx, word ptr [rax + GL_w]
    movzx r8d, word ptr [rax + GL_h]
    movsx edi, word ptr [rax + GL_left]
    add edi, [rsp + 36]
    mov esi, [rsp + 28]
    add esi, [rsp + 16]
    movsx r9d, word ptr [rax + GL_top]
    sub esi, r9d
    mov rdx, r10
    mov r9d, [rsp + 44]
    call gfx_mask
.Lr_done:
    EPILOGUE

# odos_cell_colors(cell) -> eax fg argb, edx bg argb
FN odos_cell_colors
    push rbx
    push r12
    mov rbx, rdi
    mov edi, [rbx + 8]
    mov esi, [rip + g_theme + 4*T_BG]
    call odos_tcolor
    mov r12d, eax
    mov edi, [rbx + 4]
    mov esi, [rip + g_theme + 4*T_FG]
    call odos_tcolor
    mov ecx, [rbx]
    test ecx, A_INVERSE
    jz 1f
    xchg eax, r12d
1:  test ecx, A_DIM
    jz 2f
    mov edi, eax
    mov esi, r12d
    mov edx, 100
    call color_mix
2:  mov edx, r12d
    pop r12
    pop rbx
    ret

# odos_tcolor(value, default) -> argb (mirrors termview tcolor)
FN odos_tcolor
    mov eax, edi
    shr eax, 24
    jz 8f
    cmp eax, 1
    jne 7f
    movzx edi, dil
    cmp edi, 16
    jae 1f
    lea rax, [rip + g_theme]
    mov eax, [rax + rdi*4 + 4*T_TERM]
    ret
1:  cmp edi, 232
    jae 2f
    sub edi, 16
    mov eax, edi
    xor edx, edx
    mov ecx, 36
    div ecx
    mov r8d, edx
    call odos_cube
    mov r9d, eax
    mov eax, r8d
    xor edx, edx
    mov ecx, 6
    div ecx
    mov r8d, edx
    call odos_cube
    shl r9d, 8
    or r9d, eax
    mov eax, r8d
    call odos_cube
    shl r9d, 8
    or eax, r9d
    or eax, 0xff000000
    ret
2:  sub edi, 232
    imul eax, edi, 10
    add eax, 8
    imul eax, eax, 0x010101
    or eax, 0xff000000
    ret
7:  mov eax, edi
    or eax, 0xff000000
    ret
8:  mov eax, esi
    ret

FN odos_cube
    test eax, eax
    jz 1f
    imul eax, eax, 40
    add eax, 55
1:  ret

# cp_width(cp): 1, or 2 for East-Asian wide ranges (mirrors doc.s)
FN cp_width
    mov eax, 1
    cmp edi, 0x1100
    jb 9f
    lea rsi, [rip + wide_ranges]
1:  mov ecx, [rsi]
    test ecx, ecx
    jz 9f
    cmp edi, ecx
    jb 2f
    cmp edi, [rsi + 4]
    ja 2f
    mov eax, 2
    ret
2:  add rsi, 8
    jmp 1b
9:  ret

.section .rodata
wide_ranges:
    .long 0x1100, 0x115f, 0x2e80, 0x303e, 0x3041, 0x33ff, 0x3400, 0x4dbf, 0x4e00, 0x9fff
    .long 0xa000, 0xa4cf, 0xac00, 0xd7a3, 0xf900, 0xfaff, 0xfe30, 0xfe4f, 0xff00, 0xff60
    .long 0xffe0, 0xffe6, 0x1f300, 0x1f64f, 0x1f900, 0x1f9ff, 0x20000, 0x3fffd, 0x1f680, 0x1f6ff
    .long 0x1fa70, 0x1faff, 0x231a, 0x231b, 0x26a1, 0x26a1, 0x2705, 0x2705, 0x2728, 0x2728
    .long 0x274c, 0x274c, 0x2b50, 0x2b50, 0, 0
.text

# ---- minimal shims for wayland.s deps ----

# cstr_copy(dst, src) -> ptr to dst NUL
FN cstr_copy
1:  mov al, [rsi]
    mov [rdi], al
    test al, al
    jz 2f
    inc rdi
    inc rsi
    jmp 1b
2:  mov rax, rdi
    ret

# str_ieq_cstr(ptr, len, cstr) -> 1 if equal ignoring ascii case
FN str_ieq_cstr
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, rdx
    call strlen
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, rax
    call str_ieq
    pop r13
    pop r12
    pop rbx
    ret

# cursor theme disabled: empty cursor, never crashes
FN xcursor_size
    mov eax, 24
    ret

FN xcursor_load
    xor eax, eax
    ret

FN xcursor_builtin
    push rbx
    mov rbx, rdx
    mov qword ptr [rbx + XC_file], 0
    mov qword ptr [rbx + XC_pixels], 0
    mov dword ptr [rbx + XC_w], 0
    mov dword ptr [rbx + XC_h], 0
    mov dword ptr [rbx + XC_xhot], 0
    mov dword ptr [rbx + XC_yhot], 0
    xor eax, eax
    pop rbx
    ret
