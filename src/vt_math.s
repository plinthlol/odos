# vt_math: freestanding libm + compiler_rt symbols needed by libghostty-vt.a
# SysV: doubles in xmm0, floats in xmm0 low. All leaf functions.
.include "rhun.inc"

.section .rodata
.p2align 3
.Llog2e: .double 1.4426950408889634
.Lln2: .double 0.6931471805599453
.Lhalf: .double 0.5
.Lc2: .double 0.5
.Lc3: .double 0.16666666666666666
.Lc4: .double 0.041666666666666664
.Lc5: .double 0.008333333333333333
.Lc6: .double 0.001388888888888889
.Lc7: .double 0.0001984126984126984
.Lt3: .double 0.3333333333333333
.Lt5: .double 0.2
.Lt7: .double 0.14285714285714285
.Lt9: .double 0.1111111111111111
.Lt11: .double 0.09090909090909091
.Lt13: .double 0.07692307692307693
.Lsqrt2: .double 1.4142135623730951
.Lone: .double 1.0
.Lposinf_bits: .quad 0x7ff0000000000000
.Lneginf_bits: .quad 0xfff0000000000000
.Lnan_bits: .quad 0x7ff8000000000000
.Labsmask: .quad 0x7fffffffffffffff
.Lbig: .quad 0x4330000000000000
.Lneg64: .quad 0x3bf0000000000000
.Lexp_hi: .double 709.782712893384
.Lexp_lo: .double -745.1332191019412
.Lm_bias: .quad 0x3ff0000000000000
.Lm_f128exp: .quad 0x7fff000000000000
.Lm_f128one: .quad 0x0001000000000000
.Lm_dbit52: .quad 0x0010000000000000
.Lm_xbit63: .quad 0x8000000000000000

.text

# double ceil(x)
FN ceil
    movq rax, xmm0
    mov rcx, rax
    and rcx, [rip + .Labsmask]
    cmp rcx, [rip + .Lbig]
    jae 2f
    cvttsd2si rax, xmm0
    cvtsi2sd xmm1, rax
    ucomisd xmm1, xmm0
    jp 2f
    jae 1f
    add rax, 1
    cvtsi2sd xmm0, rax
    ret
1:  movq xmm0, xmm1
2:  ret

# double trunc(x)
FN trunc
    movq rax, xmm0
    mov rcx, rax
    and rcx, [rip + .Labsmask]
    cmp rcx, [rip + .Lbig]
    jae 1f
    cvttsd2si rax, xmm0
    cvtsi2sd xmm0, rax
1:  ret

# float truncf(x)
FN truncf
    cvttss2si eax, xmm0
    cvtsi2ss xmm0, eax
    ret

# double round(x): half away from zero
FN round
    ucomisd xmm0, xmm0
    jp 2f
    movq rax, xmm0
    mov rcx, rax
    and rcx, [rip + .Labsmask]
    cmp rcx, [rip + .Lbig]
    jae 2f
    xorpd xmm1, xmm1
    ucomisd xmm0, xmm1
    jb 1f
    addsd xmm0, [rip + .Lhalf]
    cvttsd2si rax, xmm0
    cvtsi2sd xmm0, rax
    ret
1:  subsd xmm0, [rip + .Lhalf]
    cvttsd2si rax, xmm0
    cvtsi2sd xmm0, rax
2:  ret

# double exp(x)
FN exp
    ucomisd xmm0, xmm0
    jp .Lexp_nan
    ucomisd xmm0, [rip + .Lexp_hi]
    ja .Lexp_inf
    ucomisd xmm0, [rip + .Lexp_lo]
    jb .Lexp_zero
    movq rax, xmm0
    addsd xmm0, [rip + .Lhalf]
    cvttsd2si rcx, xmm0
    cvtsi2sd xmm1, rcx
    mulsd xmm1, [rip + .Lln2]
    movq xmm0, rax
    subsd xmm0, xmm1
    cmp rcx, 1023
    jg .Lexp_inf
    cmp rcx, -1074
    jl .Lexp_zero
    movsd xmm2, [rip + .Lc7]
    mulsd xmm2, xmm0
    addsd xmm2, [rip + .Lc6]
    mulsd xmm2, xmm0
    addsd xmm2, [rip + .Lc5]
    mulsd xmm2, xmm0
    addsd xmm2, [rip + .Lc4]
    mulsd xmm2, xmm0
    addsd xmm2, [rip + .Lc3]
    mulsd xmm2, xmm0
    addsd xmm2, [rip + .Lc2]
    mulsd xmm2, xmm0
    addsd xmm2, [rip + .Lone]
    mulsd xmm2, xmm0
    addsd xmm2, [rip + .Lone]
    cmp rcx, -1022
    jge 1f
    add rcx, 64
    mov rax, rcx
    add rax, 1023
    shl rax, 52
    movq xmm1, rax
    mulsd xmm2, xmm1
    mov rax, [rip + .Lneg64]
    movq xmm1, rax
    mulsd xmm2, xmm1
    movsd xmm0, xmm2
    ret
1:  mov rax, rcx
    add rax, 1023
    shl rax, 52
    movq xmm1, rax
    mulsd xmm2, xmm1
    movsd xmm0, xmm2
    ret
.Lexp_nan:
    mov rax, [rip + .Lnan_bits]
    movq xmm0, rax
    ret
.Lexp_inf:
    mov rax, [rip + .Lposinf_bits]
    movq xmm0, rax
    ret
.Lexp_zero:
    xorpd xmm0, xmm0
    ret

# float expf(x)
FN expf
    cvtss2sd xmm0, xmm0
    call exp
    cvtsd2ss xmm0, xmm0
    ret

# double log(x)
FN log
    movq rax, xmm0
    mov rcx, rax
    shl rcx, 1
    shr rcx, 53
    cmp ecx, 0x7ff
    je .Llog_special
    mov rcx, rax
    and rcx, [rip + .Labsmask]
    jz .Llog_ninf
    test rax, rax
    js .Llog_nan
    mov rcx, rax
    shr rcx, 52
    sub rcx, 1023
    shl rax, 12
    shr rax, 12
    or rax, [rip + .Lm_bias]
    movq xmm0, rax
    ucomisd xmm0, [rip + .Lsqrt2]
    jbe 2f
    mulsd xmm0, [rip + .Lhalf]
    inc rcx
2:  movsd xmm1, xmm0
    subsd xmm1, [rip + .Lone]
    addsd xmm0, [rip + .Lone]
    divsd xmm1, xmm0
    movsd xmm0, xmm1
    mulsd xmm0, xmm0
    movsd xmm2, [rip + .Lt13]
    mulsd xmm2, xmm0
    addsd xmm2, [rip + .Lt11]
    mulsd xmm2, xmm0
    addsd xmm2, [rip + .Lt9]
    mulsd xmm2, xmm0
    addsd xmm2, [rip + .Lt7]
    mulsd xmm2, xmm0
    addsd xmm2, [rip + .Lt5]
    mulsd xmm2, xmm0
    addsd xmm2, [rip + .Lt3]
    mulsd xmm2, xmm0
    addsd xmm2, [rip + .Lone]
    mulsd xmm2, xmm1
    addsd xmm2, xmm2
    cvtsi2sd xmm1, rcx
    mulsd xmm1, [rip + .Lln2]
    addsd xmm2, xmm1
    movsd xmm0, xmm2
    ret
.Llog_special:
    mov rcx, rax
    shl rcx, 12
    test rcx, rcx
    jnz .Llog_nan
    test rax, rax
    js .Llog_nan
    jmp .Llog_inf
.Llog_ninf:
    mov rax, [rip + .Lneginf_bits]
    movq xmm0, rax
    ret
.Llog_nan:
    mov rax, [rip + .Lnan_bits]
    movq xmm0, rax
    ret
.Llog_inf:
    mov rax, [rip + .Lposinf_bits]
    movq xmm0, rax
    ret

# float logf(x)
FN logf
    cvtss2sd xmm0, xmm0
    call log
    cvtsd2ss xmm0, xmm0
    ret

# __udivti3(a_lo=rdi, a_hi=rsi, b_lo=rdx, b_hi=rcx) -> q in rax(rdx hi)
FN __udivti3
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    xor r10d, r10d
    xor r11d, r11d
    xor ebx, ebx
    xor r8d, r8d
    mov ecx, 128
1:  shl r12, 1
    rcl r13, 1
    rcl r8, 1
    rcl rbx, 1
    shl r11, 1
    rcl r10, 1
    cmp rbx, r15
    jb 2f
    ja 3f
    cmp r8, r14
    jb 2f
3:  sub r8, r14
    sbb rbx, r15
    or r11, 1
2:  dec ecx
    jnz 1b
    mov rax, r11
    mov rdx, r10
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# __extenddftf2(double xmm0) -> f128 in rax(lo):rdx(hi)
FN __extenddftf2
    movq rax, xmm0
    mov rdx, rax
    shr rdx, 63
    mov rcx, rax
    shl rcx, 1
    shr rcx, 53
    and ecx, 0x7ff
    shl rax, 12
    shr rax, 12
    cmp ecx, 0x7ff
    je 2f
    test ecx, ecx
    jnz 1f
    test rax, rax
    jz 3f
    mov ecx, 1
4:  bt rax, 52
    jc 5f
    shl rax, 1
    dec ecx
    jmp 4b
5:  shl rax, 12
    shr rax, 12
1:  sub ecx, 1023
    add ecx, 16383
    mov r8, rax
    shr r8, 4
    or r8, [rip + .Lm_f128one]
    shl rax, 60
    shl rdx, 63
    mov rsi, rcx
    shl rsi, 48
    or rdx, rsi
    or rdx, r8
    ret
2:  mov r8, rax
    shr r8, 4
    shl rax, 60
    shl rdx, 63
    or rdx, [rip + .Lm_f128exp]
    or rdx, r8
    ret
3:  shl rdx, 63
    xor eax, eax
    ret

# __extendxftf2(80-bit long double in rdi(mantissa):rsi(exp/sign low 16)) -> f128
FN __extendxftf2
    mov rax, rdi
    mov ecx, esi
    and ecx, 0x7fff
    mov edx, esi
    shr edx, 15
    and edx, 1
    cmp ecx, 0x7fff
    je 2f
    test ecx, ecx
    jnz 1f
    test rax, rax
    jz 3f
    xor ecx, ecx
4:  bt rax, 63
    jc 5f
    shl rax, 1
    dec ecx
    jmp 4b
5:  jmp 1f
1:  mov r8, rax
    shr r8, 16
    shl rax, 48
    shl rdx, 63
    mov rsi, rcx
    shl rsi, 48
    or rdx, rsi
    or rdx, r8
    ret
2:  mov r8, rax
    shr r8, 16
    shl rax, 48
    mov rdx, 0x7fff000000000000
    or rdx, r8
    ret
3:  shl rdx, 63
    xor eax, eax
    ret
