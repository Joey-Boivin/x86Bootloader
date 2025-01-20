%define VIDEO_INTERRUPT             0x10
%define WRITE_CHARACTER_TELETYPE    0x0E

BITS 16
ORG 0x0
section .text
kmain:
    push    text
    push    1
    call    kprint
    add     sp, 4
.stop:
    jmp .stop


; void kprint(char** strings, uint16_t n);
; params[in]
;       strings: strings to print
;       n:       Number of strings to print
kprint:
    push    bp
    mov     bp, sp
    push    bx
    mov     cx, 0
    mov     di, 6
    mov     dx, [bp + 4]
.print_strings_begin:
    cmp     cx, dx
    je      .print_strings_end
    mov     si, [bp + di]
    add     di, 2
    inc     cx
.print_loop:
    lodsb
    test    al, al
    je      .print_strings_begin
    mov     bh, 0 ; page is unimportant in this case
    mov     ah, WRITE_CHARACTER_TELETYPE 
    int     VIDEO_INTERRUPT
    jmp     .print_loop
.print_strings_end:
    pop     bx
    mov     sp, bp
    pop     bp
    ret

section .bss

section .data

text: db "Kernel loaded into memoryasddasdasdasdsdadasdasd", 0x0A, 0x0D, 0x00
