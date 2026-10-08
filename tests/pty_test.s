# headless phase-1 test: spawn shell, echo marker, pump, dump grid, render offscreen
.include "rhun.inc"

.bss
.p2align 3
dump_sb: .zero SB_SIZE

.text
FN main
    PROLOGUE 16
    call init_theme
    call font_init
    test eax, eax
    jnz 1f
    lea rdi, [rip + .Le_font]
    call die
1:  mov dword ptr [rip + o_cols], 80
    mov dword ptr [rip + o_rows], 24
    call spawn_shell
    test eax, eax
    jnz 2f
    lea rdi, [rip + .Le_shell]
    call die
2:  lea rsi, [rip + .Lcmd]
    mov rdx, .Lcmd_end - .Lcmd
    call o_send
    mov ebx, 10
3:  mov edi, 200
    call loop_poll
    dec ebx
    jnz 3b
    # dump the grid to stdout for the harness to grep
    mov rdi, [rip + o_term]
    lea rsi, [rip + dump_sb]
    call term_dump
    mov edi, 1
    mov rsi, [rip + dump_sb + SB_ptr]
    mov rdx, [rip + dump_sb + SB_len]
    call write_all
    # offscreen render exercises resize + glyph paths without a compositor
    mov edi, 800*600*4
    call mem_alloc
    mov rdi, rax
    mov esi, 800
    mov edx, 600
    mov ecx, 800
    call gfx_set_target
    call app_render
    xor eax, eax
    EPILOGUE

.section .rodata
.Le_font: .asciz "odos-test: no font"
.Le_shell: .asciz "odos-test: no shell"
.Lcmd: .ascii "echo odos-phase1-ok\n"
.Lcmd_end:
.text
