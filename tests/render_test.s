# render test: offscreen 800x600, same fill sequence as app_render, assert pixels
.include "rhun.inc"

.bss
.p2align 3
pixels: .quad 0

.text
# minimal cstr_copy for sys.s
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

FN main
    PROLOGUE 16
    mov edi, 800*600*4
    call mem_alloc
    mov [rip + pixels], rax
    mov rdi, rax
    mov esi, 800
    mov edx, 600
    mov ecx, 800
    call gfx_set_target
    # replicate app_render fills
    xor edi, edi
    xor esi, esi
    mov edx, 800
    mov ecx, 600
    mov r8d, 0xff16181d
    call gfx_fill
    lea edi, [400 - 70]
    lea esi, [300 - 20]
    mov edx, 70
    mov ecx, 9
    mov r8d, 0xff8fa3bf
    call gfx_fill
    lea edi, [400 - 70]
    lea esi, [300 + 11]
    mov edx, 70
    mov ecx, 9
    mov r8d, 0xff8fa3bf
    call gfx_fill
    mov edi, 400
    lea esi, [300 - 20]
    mov edx, 26
    mov ecx, 40
    mov r8d, 0xff8fa3bf
    call gfx_fill
    lea edi, [400 + 26]
    lea esi, [300 - 7]
    mov edx, 14
    mov ecx, 14
    mov r8d, 0xffe8e4d8
    call gfx_fill
    # asserts
    mov rax, [rip + pixels]
    cmp dword ptr [rax + (10*800+10)*4], 0xff16181d
    jne 9f
    cmp dword ptr [rax + ((300-16)*800+(400-35))*4], 0xff8fa3bf
    jne 9f
    cmp dword ptr [rax + (300*800+400+30)*4], 0xffe8e4d8
    jne 9f
    xor eax, eax
    EPILOGUE
9:  mov eax, 1
    EPILOGUE
