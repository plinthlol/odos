# vt_alloc: GhosttyAllocator over mem_alloc/mem_free for libghostty-vt (freestanding)
# GhosttyAllocator { ctx:8, vtable:8 }; vtable { alloc, resize, remap, free }.
# Zig alignment is log2: align the payload, stash the base at [ptr-8].
.include "rhun.inc"

.bss
.p2align 3
.globl g_ghost_alloc
g_ghost_alloc: .zero 16

.section .rodata
.p2align 3
vt_vtable:
    .quad vt_alloc_fn
    .quad vt_resize_fn
    .quad vt_remap_fn
    .quad vt_free_fn

.text

# vt_alloc_init(): publish g_ghost_alloc for the C API (call once)
FN vt_alloc_init
    mov qword ptr [rip + g_ghost_alloc], 0
    lea rax, [rip + vt_vtable]
    mov [rip + g_ghost_alloc + 8], rax
    ret

# vt_alloc_fn(ctx, len, align_log2, ret_addr) -> ptr
FN vt_alloc_fn
    PROLOGUE 0
    mov r12, rsi                       # len
    movzx ecx, dl                      # align bits
    cmp ecx, 20
    jbe 1f
    mov ecx, 20
1:  mov r13d, 1
    shl r13, cl                        # a = 1 << align
    lea rdi, [r12 + 16]
    add rdi, r13
    call mem_alloc
    test rax, rax
    jz 9f
    lea rcx, [rax + 16]
    add rcx, r13
    dec rcx
    dec r13
    not r13                            # mask = ~(a - 1)
    and rcx, r13                       # aligned payload
    mov [rcx - 8], rax                # stash base
    mov rax, rcx
9:  EPILOGUE

# vt_resize_fn(ctx, mem, memlen, align, newlen, ret) -> 1 in place, else 0
FN vt_resize_fn
    cmp r8, rdx
    jbe 1f
    xor eax, eax
    ret
1:  mov eax, 1
    ret

# vt_remap_fn(ctx, mem, memlen, align, newlen, ret) -> relocated copy or 0
FN vt_remap_fn
    PROLOGUE 16
    mov [rsp], rdi                     # ctx
    mov [rsp + 8], rsi                 # old mem
    mov r12, rdx                       # old len
    mov r13b, cl                       # align
    mov r14, r8                        # new len
    mov rsi, r8
    movzx edx, r13b
    xor ecx, ecx
    call vt_alloc_fn
    test rax, rax
    jz 9f
    mov r15, rax                       # new mem
    mov rdi, rax
    mov rsi, [rsp + 8]
    mov rdx, r12
    cmp rdx, r14
    cmova rdx, r14
    call memcpy
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    mov rdx, r12
    movzx ecx, r13b
    xor r8d, r8d
    xor r9d, r9d
    call vt_free_fn
    mov rax, r15
9:  EPILOGUE

# vt_free_fn(ctx, mem, memlen, align, ret)
FN vt_free_fn
    PROLOGUE 0
    test rsi, rsi
    jz 9f
    mov rdi, [rsi - 8]
    call mem_free
9:  EPILOGUE
