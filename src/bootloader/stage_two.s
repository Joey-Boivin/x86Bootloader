;*******************************************************************************
;*                                                                             *
;*                                S M O L O S                                  *
;*                                                                             *
;*                             Bootloader Stage 2                              *
;*                                                                             *
;* Author: [Joey Boivin]                                                       *
;* Date:   [2024/07/07]                                                        *
;*                                                                             *
;*                                stage_two.s                                  *
;*                                                                             *
;*******************************************************************************

%define VIDEO_INTERRUPT             0x10
%define WRITE_CHARACTER_TELETYPE    0x0E

%define DISK_SERVICE_INTERRUPT      0x13
%define DISK_SERVICE_READ           0x02
%define DISK_SERVICE_RESET          0x00
%define DRIVE_NUMBER                0x00

%define SECTORS_PER_TRACK           18
%define HEADS_PER_CYLINDER          2
%define SECTORS_PER_FAT             9
%define RESERVED_SECTORS            32
%define DIR_ENTRY_COUNT             64
%define FAT_COUNT                   2
%define BYTES_PER_SECTOR            512

[BITS 16]
[ORG 0x7E00]

section .text
stage_two_main:
    xor     ax, ax
    xor     bx, bx
    xor     cx, cx
    xor     dx, dx
    mov     ds, ax
    mov     es, ax
    mov     ss, ax
    push    bp
    mov     bp, sp
    
    push    stage_two_executing
    push    stage_two_header
    push    2
    call    stage_two_print_strings
    add     sp, 6

    call    stage_two_load_root_directory
    test    ax, ax
    jz      .load_root_directory_success
.load_root_directory_failed:
    push    loading_root_directory_failed
    push    stage_two_header
    push    2
    call    stage_two_print_strings
    add     sp, 4
    jmp     stage_two_halt
.load_root_directory_success:
    push    loading_root_directory_success
    push    stage_two_header
    push    2
    call    stage_two_print_strings
    add     sp, 4

    push    kernel_file_name
    push    root_directory
    call    stage_two_find_file
    add     sp, 4
    cmp     ax, -1
    jne     .search_kernel_success
.search_kernel_failed:
    push    search_kernel_file_failed
    push    stage_two_header
    push    2
    call    stage_two_print_strings
    add     sp, 4
    jmp     stage_two_halt
.search_kernel_success:
    mov     [kernel_cluster], ax
    push    search_kernel_file_success
    push    stage_two_header
    push    2
    call    stage_two_print_strings
    add     sp, 4

    push    SECTORS_PER_FAT
    push    file_allocation_table
    call    stage_two_load_file_allocation_table
    add     sp, 4
    test    ax, ax
    jz      .load_fat_success
.load_fat_failed:
    push    load_fat_failed
    push    stage_two_header
    push    2
    call    stage_two_print_strings
    add     sp, 6
    jmp     stage_two_halt
.load_fat_success:
    push    load_fat_success
    push    stage_two_header
    push    2
    call    stage_two_print_strings
    add     sp, 6
    push    word [kernel_cluster],
    push    kernel_segment
    call    stage_two_load_kernel
    test    ax, ax
    jz      .load_kernel_success
    push    load_kernel_failed
    push    stage_two_header
    push    2
    call    stage_two_print_strings
    add     sp, 6
    jmp     stage_two_halt
.load_kernel_success:
    push    load_kernel_success
    push    stage_two_header
    push    2
    call    stage_two_print_strings
    add     sp, 6

    ; Now that everything is loaded into memory, prepare kernel
    mov     dl, 0
    mov     ax, 0
    mov     ds, ax
    mov     es, ax
    jmp     kernel_segment:kernel_load_offset
    
    hlt
stage_two_halt:
    jmp stage_two_halt

; void stage_two_print_strings(char** strings, uint16_t n);
; params[in]
;       strings: strings to print
;       n:       Number of strings to print
stage_two_print_strings:
    push    bp
    mov     bp, sp
    mov     cx, 0
    mov     di, 6
    mov     dx, [bp + 4]
.stage_two_print_strings_begin:
    cmp     cx, dx
    je      .stage_two_print_strings_end
    mov     si, [bp + di]
    add     di, 2
    inc     cx
.stage_two_print_loop:
    lodsb
    test    al, al
    je      .stage_two_print_strings_begin
    mov     bh, 0 ; page is unimportant in this case
    mov     ah, WRITE_CHARACTER_TELETYPE 
    int     VIDEO_INTERRUPT
    jmp     .stage_two_print_loop
.stage_two_print_strings_end:
    mov     sp, bp
    pop     bp
    ret

; void stage_two_lba_to_chs(struct chs* c, uint16_t lba);
; params[in]
;       c: pointer to a struct of 3 bytes (c, h, s)
;       lba: Logical block address of disk
stage_two_lba_to_chs:
    push    bp
    mov     bp, sp
    push    bx

    ; Temp = LBA / (Sectors per Track)
    ; Sector = (LBA % (Sectors per Track)) + 1
    ; Head = Temp % (Number of Heads)
    ; Cylinder = Temp / (Number of Heads)
    ; bp + 4 : address of struct
    ; bp + 6: lba
    mov     ax, [bp + 6] ;store lba in ax
    xor     dx, dx
    mov     cx, SECTORS_PER_TRACK
    div     word cx ; lba/sectors per track. result in eax remainder in dx 
    inc     dx
    mov     bx, [bp + 4]
    mov     [bx + 0], dl

    ; C = (LBA / sectors per track) / heads per cylinder
    ; H = (LBA / sectors per track) % heads per cylinder 
    xor     dx, dx
    mov     cx, HEADS_PER_CYLINDER
    div     word cx
    mov     [bx + 1], dl
    mov     [bx + 2], al

    pop     bx
    mov     sp, bp
    pop     bp
    ret

; int stage_two_read_disk(uint16_t address, uint16_t lba, uint16_t n);
; params[in]
;       address: start address to load in RAM
;       lba: logical block address on the disk
;       n: number of 512 bytes sectors to load in RAM
; params[out]
;       error code in eax
stage_two_read_disk:
    push    bp
    mov     bp, sp
    push    bx
    mov     di, 3

    sub     sp, 4
    mov     dx, [bp + 6]
    push    dx ; lba
    lea     dx, [bp - 5]
    push    dx  ; chs struct pointer
    call    stage_two_lba_to_chs
    add     sp, 4
    lea     si, [bp - 5] ; chs struct was filled by lba_to_chs
.read_disk_begin:
    mov     ch, byte [si + 2]
    mov     bl, byte [si + 2]
    shr     bl, 2
    and     bl, 0xc0
    mov     dl, byte [si]
    or      dl, bl
    mov     cl, dl
    mov     dl, DRIVE_NUMBER
    mov     dh, byte [si + 1]
    mov     bx, [bp + 4]
    mov     ah, DISK_SERVICE_READ
    mov     al, byte [bp + 8]
    int     DISK_SERVICE_INTERRUPT
    jc     .read_disk_retry
    mov     ax, 0
    jmp     .disk_read_end
.read_disk_retry:
    test    di, di
    jz      .disk_read_end
    dec     di
.disk_reset:
    push    ax
    mov     ax, DISK_SERVICE_RESET
    int     DISK_SERVICE_INTERRUPT
    pop     ax
    jnc     .read_disk_begin
    mov     ax, -1
.disk_read_end:
    pop     bx
    mov     sp, bp
    pop     bp
    ret

; int stage_two_load_root_directory(void)
; params[out]
;       error code in eax. 0 if no errors
stage_two_load_root_directory:
    push    bp
    mov     bp, sp
    push    bx

    xor     bx, bx
    mov     ax, SECTORS_PER_FAT
    mov     bl, FAT_COUNT
    mul     bx
    add     ax, RESERVED_SECTORS ; lba of root now in ax
    push    ax ; save result
    mov     ax, DIR_ENTRY_COUNT
    shl     ax, 5 ; multiply by 32 because each dir entry is 32 bytes in fat 12
    xor     dx, dx
    mov     bx, BYTES_PER_SECTOR
    div     word bx ;= 32 * number of entries / bytes per sector
    test    dx, dx
    jz      .load_root_directory
    ; Round up number of sectors
    inc     ax
.load_root_directory:
    xor     cx, cx
    mov     cx, ax
    pop     ax
    push    cx ;n sectors
    push    ax ;lba
    push    root_directory
    call    stage_two_read_disk
    add     sp, 6
    
    pop     bx
    mov     sp, bp
    pop     bp
    ret

; int stage_two_find_file(uint8_t* directory_buffer, char* file_name)
; params[in]
;       directory_buffer: directory buffer in which the file name is searched
;       file_name: file to search. must be an 11 bytes name
; params[out]
;       eax is -1 on error or not found, else contains the start sector for the file
stage_two_find_file:
    push    bp
    mov     bp, sp
    push    bx

    mov     di, [bp + 4]
    xor     bx, bx
.search_loop:
    mov     si, [bp + 6]
    mov     cx, 11
    push    di
    repe    cmpsb
    pop     di
    je      .search_found
    add     di, 32 ;go to next dir entry which is 32 bytes further
    inc     bx
    cmp     bx, DIR_ENTRY_COUNT
    jl      .search_loop
    mov     ax, -1 ; error: not found
    jmp     .search_end
.search_found:
    mov     ax, [di + 26] ; cluster number is at offset 26
.search_end:
    pop     bx
    mov     sp, bp
    pop     bp
    ret

; int stage_two_load_file_allocation_table(uint8_t* fat_buffer, uint16_t n)
; params[in]
;       fat1_buffer: buffer for the first fat
;       n: size of fat in sector(s)
; params[out]
;       error code in eax. 0 if no errors
stage_two_load_file_allocation_table:
    push    bp
    mov     bp, sp
    push    bx

    mov     ax, [bp + 6] ;n
    mov     bx, [bp + 4] ; fat_buffer

    push    ax
    push    RESERVED_SECTORS
    push    bx
    call    stage_two_read_disk
    add     sp, 6

    pop     bx
    mov     sp, bp
    pop     bp
    ret

; int stage_two_load_kernel(uint8_t* fat, uint8_t* kaddress, uint16_t first_cluster)
; params[in]
;       fat: pointer to file allocation table
;       kaddress: address where the kernel should be loaded
;       first_cluster: first cluster of the kernel
; params[out]
;       error code in eax. 0 if no errors
stage_two_load_kernel:
    push    bp
    mov     bp, sp
    push    bx

.load_kernel_loop:
    mov     ax, [bp + 6] ; first_cluster
    add     ax, 52 ; data starts at sector 54, and first cluster is always 2. TODO: magic number

    mov     bx, [bp + 4]
    mov     es, bx ;int 13 is es:bx
    mov     bx, kernel_load_offset
    
    push    1
    push    ax
    push    bx ; load one sector at a time
    call    stage_two_read_disk
    add     sp, 6
    test    ax, ax
    jz      .load_kernel_end

    add     bx, BYTES_PER_SECTOR
    mov     ax, [bp + 6]
    ;get next location
    mov     cx, 3 ;cluster * 1.5
    mul     cx
    mov     cx, 2
    div     cx
    mov     si, file_allocation_table
    add     si, ax
    mov     ax, [ds:si] ;TODO
    
    or      dx, dx
    jz      .even
.odd:
    shr     ax, 4
    jmp     .next_cluster
.even:
    and     ax, 0x0fff
.next_cluster:
    cmp     ax, 0x0ff8
    jae     .load_kernel_end
    mov     [bp + 6], ax
.load_kernel_end:
    pop     bx
    mov     sp, bp
    pop     bp
    ret

section .bss
file_allocation_table: resb SECTORS_PER_FAT * BYTES_PER_SECTOR
root_directory: resb DIR_ENTRY_COUNT * 32
kblock: resb 8 * 64

section .data
kernel_file_name:                   db "KMAIN   BIN"
kernel_cluster:                     dw 0
kernel_segment:                     equ 0x2000
kernel_load_offset                  equ 0
stage_two_header:                   db "[STAGE TWO]:  ", 0x00
stage_two_executing:                db "Executing", 0x0A, 0x0D, 0x00
loading_root_directory:             db "Loading root directory", 0x0A, 0x0D, 0x00
loading_root_directory_success:     db "Loading root directory success", 0x0A, 0x0D, 0x00
loading_root_directory_failed:      db "Loading root directory failed", 0x0A, 0x0D, 0x00
search_kernel_file_success:         db "Kernel file found",  0x0A, 0x0D, 0x00
search_kernel_file_failed:          db "Kernel file not found", 0x0A, 0x0D, 0x00
load_fat_success:                   db "Loading file alocation table sucess", 0x0A, 0x0D, 0x00
load_fat_failed:                    db "Loading file alocation table failed", 0x0A, 0x0D, 0x00
load_kernel_success:                db "Kernel loaded", 0x0A, 0x0D, 0x00
load_kernel_failed:                 db "Kernel load failed", 0x0A, 0x0D, 0x00
executing_message                   db "Executing stage two", 0x0A, 0x0D, 0x00

; There are 31 free reserved sectors left (1 is taken by the first stage bootloader)
; 31 sectors * 512 bytes/sector is 15872 bytes
times 15872-($-$$) db 0x00
