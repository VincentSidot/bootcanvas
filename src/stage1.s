; Stage 1 bootloader code (stage1.s)
include 'constants.inc'

use16
org STAGE1_LOAD_ADDRESS

; IMAGE_SIZE_B is provided by the build system and represents the size of the VGA image in bytes
IMAGE_SECTORS = (IMAGE_SIZE_B + 511) / 512 ; Number of sectors needed to load the VGA image

; STAGE2_SIZE_B is provided by the build system and represents the size of stage2 in bytes
STAGE2_SECTORS = (STAGE2_SIZE_B + 511) / 512 ; Number of sectors needed to load stage2

; IMAGE header is a u16 value at the beginning of the image file, and is passed
; via IMAGE_VALIDATION_VALUE via the build system

SLEEP_DURATION = 1000 ; Duration to sleep before jumping to stage2 (in milliseconds)
BIOS_TICKS_PER_SECOND = 18 ; Number of BIOS timer ticks per second
SLEEP_TICKS = (SLEEP_DURATION * BIOS_TICKS_PER_SECOND) / 1000 ; Convert sleep duration to BIOS ticks

BIOS_TIMER_OFFSET = 0x006C ; BIOS timer tick count address

_start:
  cli ; Clear interrupts to prevent any unwanted behavior during boot
  cld ; Make sure the direction flag is clear for string operations

  mov ax, 0x0000
  mov ds, ax
  mov es, ax
  mov ss, ax
  mov sp, 0x7C00

  sti ; Enable interrupts

  ; Save the boot drive number passed by the BIOS in DL
  mov [boot_drive], dl

  ; Load stage2 from the disk to STAGE2_LOAD_ADDRESS
  mov word [dap_count], STAGE2_SECTORS
  mov word [dap_offset], STAGE2_LOAD_ADDRESS
  mov word [dap_segment], 0x0000 ; no segment needed here.
  mov dword [dap_lba], 1 ; LBA sector number, 0 is the boot sector
  mov dword [dap_lba + 4], 0

  mov dl, [boot_drive] ; Drive number from bootloader
  call read_lba
  jc .disk_error_stg2

  ; Load image from the disk to IMAGE_LOAD_ADDRESS
  mov word [dap_count], IMAGE_SECTORS
  mov word [dap_offset], IMAGE_LOAD_OFFSET
  mov word [dap_segment], IMAGE_LOAD_SEGMENT
  mov dword [dap_lba], 1 + STAGE2_SECTORS
  mov dword [dap_lba + 4], 0

  mov dl, [boot_drive] ; Drive number from bootloader
  call read_lba
  jc .disk_error_img

  jmp .validate_image

.image_valid:
  jmp 0x0000:STAGE2_LOAD_ADDRESS ; Jump to the loaded stage2 code

.validate_image:
  ; Validate the image by checking the header value
  mov ax, IMAGE_LOAD_SEGMENT
  mov es, ax
  mov ax, word [es:IMAGE_LOAD_OFFSET] ; Load the image header
  cmp ax, IMAGE_VALIDATION_VALUE ; Compare with the expected validation value
  je .image_valid

  mov si, error_img_invalid
  call print
  jmp .halt

.disk_error_stg2:
  ; Handle disk read error (e.g., print an error message or blink the screen)
  mov si, error_stg2
  call print
  jmp .halt
.disk_error_img:
  ; Handle disk read error (e.g., print an error message or blink the screen)
  mov si, error_img
  call print
.halt:
  hlt
  jmp .halt

; Print message
; input: ds:si = pointer to null-terminated string
print:
  lodsb
  test al, al
  jz .done
  mov ah, 0x0E ; BIOS teletype output function
  int 0x10
  jmp print
  .done:
  ret

; input:
;   - dl = boot drive
;  DAP already filled with the parameters
read_lba:
  mov ah, 0x42
  mov si, dap
  int 0x13
  ret

error_stg2 db "Bootloader failed to load stage2!", 0
error_img db "Bootloader failed to load the image!", 0
error_img_invalid db "Bootloader loaded an invalid image!", 0

boot_drive db 0 ; Save the boot drive number passed by the BIOS

dap:
  db 0x10          ; size of packet
  db 0x00          ; reserved
dap_count:
  dw 0             ; sectors to read
dap_offset:
  dw 0             ; destination offset
dap_segment:
  dw 0             ; destination segment
dap_lba:
  dq 0             ; starting LBA sector

times 510 - ($ - $$) db 0 ; Target 510 bytes for the boot sector
dw 0xAA55 ; Boot signature
