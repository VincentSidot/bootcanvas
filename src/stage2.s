; Stage 2: VGA image viewer
include 'constants.inc'

use16
org STAGE2_LOAD_ADDRESS

macro VGA_SET_MODE mode {
  mov ah, 0x00
  mov al, mode
  int 0x10
}

macro OUTB mode, value {
  mov dx, mode
  mov al, value
  out dx, al
}


VGA_MODE_640x480_16_COLOR = 0x12
VGA_FRAMEBUFFER_SEGMENT = 0xA000
VGA_GRAPHICS_DATA  = 0x03CF
VGA_GRAPHICS_INDEX = 0x03CE
VGA_SEQUENCER_DATA = 0x03C5
VGA_SEQUENCER_INDEX = 0x03C4

start:
  VGA_SET_MODE VGA_MODE_640x480_16_COLOR

  SCREEN_WIDTH = 640
  SCREEN_HEIGHT = 480
  SCREEN_SIZE = (SCREEN_WIDTH * SCREEN_HEIGHT) / 8 ; Each byte represents
  SCREEN_WIDTH_BYTES = SCREEN_WIDTH / 8 ; Number of bytes per line

  VGA_GREEN = 0x02
  VGA_RED = 0x04

  call getsize ; Get the image size from the image header
  call init_attr_palette ; Initialize the VGA palette to a known state
  call palette ; Set the VGA palette to match the image palette

  call display_image ; Display the image on the screen

  jmp halt

halt:
  hlt
  jmp halt

getsize:
  mov ax, IMAGE_LOAD_SEGMENT
  mov es, ax
  mov ax, word [es:IMAGE_LOAD_OFFSET] ; Load the image header
  add ax, IMAGE_LOAD_OFFSET
  ; Store the end address of the image for later use
  mov word [end_image], ax
  ret

init_attr_palette:
  xor bl, bl

  .loop:
  mov bh, bl        ; map entry N -> DAC color N
  mov ax, 0x1000    ; set individual palette register
  int 0x10

  inc bl
  cmp bl, 16
  jb .loop

ret

palette:
  ; Set the palette to match the image palette.
  mov ax, IMAGE_LOAD_SEGMENT
  mov es, ax
  mov si, IMAGE_LOAD_OFFSET + 2; Start of the palette data
  xor bx, bx ; Start at the first palette entry
  .loop:
  mov dh, byte [es:si] ; Red
  shr dh, 2 ; Convert from 8-bit to 6-bit color (0-63)
  inc si

  mov ch, byte [es:si] ; Green
  shr ch, 2 ; Convert from 8-bit to 6-bit color (0-63)
  inc si

  mov cl, byte [es:si] ; Blue
  shr cl, 2 ; Convert from 8-bit to 6-bit color (0-63)
  inc si

  mov ax, 0x1010 ; BIOS set palette entry function
  int 0x10
  inc bx ; Move to the next palette entry
  cmp bx, 16 ; We have 16 palette entries in mode 0x12
  jb .loop

ret

display_image:
 ; Read pixel from image data.
 ; Image pixels are compressed by RLE (4bit rep, 4bit index)
 mov ax, IMAGE_LOAD_SEGMENT
 mov ds, ax
 mov si, IMAGE_LOAD_OFFSET + 2 + 16 * 3; Start of the palette data

 mov cx, 0; X coordinate
 mov dx, 0; Y coordinate

 mov ds, ax ; Set DS to 0

 .loop:
 cmp si, word [cs:end_image] ; Check if we've reached the end of the image data
 jae .done
 lodsb

 ; AL = [rep(4bit) | index(4bit)]
 ; We need to write 'rep' pixels of color 'index' to the screen
 mov bl, al
 shr bl, 4    ; Get the rep count (number of pixels to write)
 and al, 0x0F ; Get the color index (0-15)

 .rep_loop:
  call set_pixel ; Set the pixel at (cx, dx) to color index in AL
  inc cx
  cmp cx, SCREEN_WIDTH
  jne .continue
  ; Move to the next line
  inc dx
  xor cx, cx ; Reset x to 0
  .continue:
  dec bl
  jnz .rep_loop

  ; Loop back to read the next pixel data
  jmp .loop
 .done:
  ret

set_pixel:
  push ax
  push bx
  push cx
  push dx
  push si
  push di
  ; Input: AL = color index (0-15), CX = x, DX = y
  ; Calculate the byte offset in the framebuffer
  ; Framebuffer layout: 4 planes, 8pixels per byte
  ; Byte offset = (y * SCREEN_WIDTH_BYTES) + (x / 8)
  push ax ; Save the color index
  mov ax, dx ; y
  mov dx, SCREEN_WIDTH_BYTES
  mul dx ; ax = y * SCREEN_WIDTH_BYTES
  mov si, cx ; save x
  shr si, 3 ; x / 8
  add si, ax ; si = (y * SCREEN_WIDTH_BYTES) + (x / 8)


  mov dx, VGA_SEQUENCER_INDEX
  mov al, 0x02 ; Select plane mask register (0x02)
  out dx, al

  mov dx, VGA_FRAMEBUFFER_SEGMENT
  mov es, dx


  pop bx ; Restore the color index to AL

  ; Compute the pixel index within the byte (0-7)
  ; Pixel index = x % 8
  and cl, 7 ; cl = x % 8
  ; Create a bitmask for the pixel index
  mov ah, 0x80
  shr ah, cl ; ch = 0x80 >> (x % 8) = reversed
  mov bh, ah
  not bh ; Invert the bitmask to clear the pixel

  mov cl, 0 ; We have 4 planes to write to
  .loop:

  mov dx, VGA_GRAPHICS_INDEX
  mov al, 0x04
  out dx, al

  mov dx, VGA_GRAPHICS_DATA
  mov al, cl                 ; read plane = current plane
  out dx, al

  mov dx, VGA_SEQUENCER_DATA
  mov al, 1
  shl al, cl ; Select the plane
  out dx, al ; Set the plane mask to select the current plane

  mov dh, byte [es:si] ; Get the color bit for the current plane

  test al, bl ; Check
  jz .clear_bit
  .set_bit:
  or dh, ah
  jmp .write
  .clear_bit:
  and dh, bh ; Clear the bit
  .write:
  mov byte [es:si], dh
  inc cl
  cmp cl, 4 ; We have 4 planes to write to
  jb .loop

  pop di
  pop si
  pop dx
  pop cx
  pop bx
  pop ax

  ret


end_image: dw 0 ; End address of the image

; Pad to closest 512-byte sector boundary
DATA_SIZE = ($ - $$)
CLOSEST_SECTOR_SIZE = ((DATA_SIZE + 511) / 512) * 512

; Fill the remaining space with zeros
times (CLOSEST_SECTOR_SIZE - DATA_SIZE) db 0
