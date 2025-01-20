;*******************************************************************************
;*                                                                             *
;*                                S M O L O S                                  *
;*                                                                             *
;*                             Bootloader Stage 1                              *
;*                                                                             *
;* This file contains the stage one bootloader code for SmolOS. It contains    *
;* the FAT12 header. Its only true role is to load the next four sectors of    *
;* the disk where the second stage bootloader is located.                      *
;*                                                                             *
;* Author: [Joey Boivin]                                                       *
;* Date:   [2024/07/07]                                                        *
;*                                                                             *
;*                                stage_one.s                                  *
;*                                                                             *
;*******************************************************************************


%define FIRST_STAGE_ADDRESS         0x7C00
%define SECOND_STAGE_ADDRESS        0x7E00  ; FIRST_STAGE_ADDRESS + 1 sector
%define SECOND_STAGE_SECTOR_COUNT   0x02
%define SECOND_STAGE_CYLINDER       0x00
%define SECOND_STAGE_SECTOR         0x02    ; Sector | ((cylinder >> 2) & 0xC0);
%define SECOND_STAGE_HEAD           0x00

%define LOAD_SECOND_STAGE_ATTEMPS   0x03

%define VIDEO_INTERRUPT             0x10
%define WRITE_CHARACTER_TELETYPE    0x0E

%define DISK_SERVICE_INTERRUPT      0x13
%define DISK_SERVICE_READ           0x02
%define DISK_SERVICE_RESET          0x00

%define BOOTABLE_PARTITION_SIGNATURE 0xAA55


[global bl_main]
[bits 16]
[org FIRST_STAGE_ADDRESS]

; FAT 12 HEADER
jmp short stage_one_main
nop

; BIOS PARAMETER BLOCK SECTION (BPB)
bpb_oem_identifier:         db 'FreeDOS '
bpb_bytes_per_sector:       dw 512
bpb_sectors_per_cluster:    db 1
bpb_reserved_sectors:       dw 32 ; sector 1: first stage bootloader and sector 2-3 second stage bootloader
bpb_fat:                    db 2
bpb_root_dir_entries:       dw 64
bpb_total_sectors:          dw 2880
bpb_media_descriptor_type:  db 0xF0
bpb_sectors_per_fat:        dw 9
bpb_sectors_per_track:      dw 18
bpb_heads:                  dw 2
bpb_hidden_sectors:         dd 0
bpb_large_sectors:          dd 0

; EXTENDED BOOT RECORD SECTION (EBR)
ebr_drive_number:           db 0
ebr_windows_nt_flags:       db 0
ebr_signature:              db 0x29
ebr_volume_id:              dd 0
ebr_volume_label:           db 'FLOPPY 3.5 '
ebr_system_id:              db 'FAT12   '

section .text
stage_one_main:
    xor     ax, ax
    xor     bx, bx
    xor     cx, cx
    xor     dx, dx
    mov     ds, ax
    mov     es, ax
    mov     ss, ax
    mov     sp, FIRST_STAGE_ADDRESS

    mov     si, stage_one_header
    call    stage_one_print
    mov     si, stage_one_post
    call    stage_one_print

    mov     al, SECOND_STAGE_SECTOR_COUNT
    mov     di, LOAD_SECOND_STAGE_ATTEMPS
    mov     ch, SECOND_STAGE_CYLINDER
    mov     cl, SECOND_STAGE_SECTOR
    mov     dh, SECOND_STAGE_HEAD
    mov     dl, [ebr_drive_number]
    mov     bx, SECOND_STAGE_ADDRESS

stage_one_load_second_stage:
    mov     ah, SECOND_STAGE_SECTOR
    int     DISK_SERVICE_INTERRUPT
    jc      .load_second_stage_retry

    mov     si, stage_one_header
    call    stage_one_print
    mov     si, stage_two_load_success
    call    stage_one_print
    jmp     stage_two_main

.load_second_stage_retry:
    test    di, di
    jz      .halt
    mov     si, stage_one_header
    call    stage_one_print
    mov     si, stage_two_load_failed
    call    stage_one_print
    call    .disk_reset
    dec     di
    jmp     stage_one_load_second_stage

.disk_reset:
    push    ax
    mov     ax, DISK_SERVICE_RESET
    int     DISK_SERVICE_INTERRUPT
    jc      .halt
    pop     ax
    ret

.halt:
    jmp     .halt

stage_one_print:
    push    si
    push    ax
    push    bx
.print_loop:
    lodsb
    test    al, al
    je      .done_print
    mov     bh, 0 ; page is unimportant in this case
    mov     ah, WRITE_CHARACTER_TELETYPE
    int     VIDEO_INTERRUPT 
    jmp     .print_loop
.done_print:
    pop     bx
    pop     ax
    pop     si
    ret

stage_one_header:               db "[STAGE ONE]:  ", 0x00
stage_one_post:                 db "POST completed.", 0x0A, 0x0D, 0x00
stage_two_load_success:         db "Stage two load was successful!", 0x0A, 0x0D, 0x00
stage_two_load_failed:          db "Stage two load failed", 0x0A, 0x0D, 0x00

times 510-($-$$) db 0
dw BOOTABLE_PARTITION_SIGNATURE

stage_two_main:
