; boot.asm
use16
org 0x7C00

_start:
  cli ; Clear interrupts to prevent any unwanted behavior during boot
  cld ; Make sure the direction flag is clear for string operations

  mov ax, 0x0000
  mov ds, ax
  mov es, ax
  mov ss, ax
  mov sp, 0x7C00

  call start
.halt:
  hlt
  jmp .halt


VGA_MODE_640x480_16_COLOR = 0x12
VGA_FRAMEBUFFER_SEGMENT = 0xA000
VGA_SEQUENCER_INDEX = 0x03C4
VGA_SEQUENCER_DATA = 0x03C5

macro VGA_SET_MODE mode {
  mov ah, 0x00
  mov al, mode
  int 0x10
}

macro VGA_SET_PROP mode, value {
  mov dx, mode
  mov al, value
  out dx, al
}


start:
  VGA_SET_MODE VGA_MODE_640x480_16_COLOR

  ; ES = 0xA000 is the segment for the VGA framebuffer in mode 0x12
  mov ax, VGA_FRAMEBUFFER_SEGMENT
  mov es, ax
  xor di, di ; Start at the beginning of the framebuffer

  ; Enable writes to all 4 planes
  VGA_SET_PROP VGA_SEQUENCER_INDEX, 0x02 ; Select plane mask register (0x02)
  VGA_SET_PROP VGA_SEQUENCER_DATA, 0x0F ; Enable all planes (0-3)

  SCREEN_WIDTH = 640 / 8

  ; Writes 8 pixels at x=0..7, y=0
  mov byte [es:di + SCREEN_WIDTH * 0], 0xFF
  ; Writes 8 pixels at x=0..7, y=1
  mov byte [es:di + SCREEN_WIDTH * 1], 0xFF
  ; Writes 8 pixels at x=0..7, y=2
  mov byte [es:di + SCREEN_WIDTH * 2], 0xFF
  ; Writes 8 pixels at x=0..7, y=3
  mov byte [es:di + SCREEN_WIDTH * 3], 0xFF

  ret



;# .echo:
;#   mov ah, 0x00
;#   int 0x16 ; Wait for a key press
;#   test ah, ah ; Check if the key is a special key (like arrow keys, function keys, etc.)
;#   jz .halt ; End the program
;#   mov ah, 0x0E
;#   int 0x10 ; Echo the key back to the screen
;#   jmp .echo


;# ; Print message to the screen
;# ; Arguments:
;# ;  si - pointer to the null-terminated string to print
;# ; Returns:
;# ; None
;# print:
;#   lodsb
;#   test al, al
;#   jz .done
;#   mov ah, 0x0E
;#   int 0x10
;#   jmp print
;# .done:
;#   ret


msg db "Hello on interactive echo system", 0
; msg db "System halted.", 0

times 510 - ($ - $$) db 0 ; Target 510 bytes for the boot sector
dw 0xAA55 ; Boot signature
